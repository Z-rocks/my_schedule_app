// Phase 8：列表型实体（作业 / 考试）的通用同步服务。
//
// ## 为什么不复用 `CourseSyncService`
//
// 两者共享 90% 的流程（调插件入口 → 归类结果 → 只对网络失败重试 → 增量落盘），
// 但差异是**类型层面**的：课程有 `sectionTimes` / `allUnits` 两个回传字段，
// 作业与考试的载荷是另一个数组、另一个模型。
//
// 三条路：① 把 `CourseSyncService` 泛型化（要动 Phase 4.3 已交付且带测试的代码，
// 风险最高）；② 复制两份几乎相同的服务（维护成本翻倍）；
// ③ **本文件**：把"与实体无关"的那部分抽成泛型服务，课程服务保持原样。
//
// 选 ③：`CourseSyncService` 一行不改，作业与考试共用一个实现，
// 将来再有"列表型"插件能力（如成绩）只需再加一个 [PluginEntitySpec]。
//
// ## 分层（CONTEXT 3.1）
//
//   插件 —— 认识学校字段，产出内核模型的 JSON
//   本服务 —— 只做"调用 → 归类 → 重试 → 增量落盘"，**不认识任何学校字段**
//   页面 —— 把 [SyncReport] 渲染成人话
//
// 服务层与 Provider 之间靠 [EntityStore] 这个最小接口解耦
// （CONTEXT 4.5：Provider 之间不互相引用；这里连"服务认识 Provider"都避免了）。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/exam.dart';
import '../models/homework.dart';
import '../models/plugin_course_ref.dart';
import '../models/sync_report.dart';
import '../runtime/js_sandbox.dart';
import '../runtime/plugin_handle.dart';

/// 一个"可按 id 增量落盘"的实体集合。
///
/// 由 `HomeworkProvider` / `ExamProvider` 实现。服务层只依赖这两个方法，
/// 因此它既能作用于 Provider，也能在测试里用一个假的 Map 实现。
///
/// [save] 的语义是"落盘 + 更新内存"，且**实现方负责保留用户覆盖层**
/// （插件传下来的模型不带 `userOverride`，直接覆盖会冲掉用户的修改）。
abstract class EntityStore<T> {
  /// 按 id 查找已有条目；不存在返回 `null`。
  T? getById(String id);

  /// 落盘并更新内存。
  Future<void> save(T item);
}

/// 一次"列表型实体"同步的插件契约。
///
/// 泛型 [T] 是内核模型（[Homework] / [Exam]），四个回调把"模型差异"挡在服务之外。
class PluginEntitySpec<T> {
  const PluginEntitySpec({
    required this.entry,
    required this.payloadKey,
    required this.parse,
    required this.idOf,
    required this.fingerprintOf,
    required this.hasOverride,
    required this.itemLabel,
  });

  /// 插件入口函数名（如 `fetchHomeworks`）。
  final String entry;

  /// 插件返回对象里承载数组的键名（如 `homeworks`）。
  final String payloadKey;

  /// 把一条 JSON 解析成模型；坏数据返回 `null`（该条被跳过）。
  final T? Function(Map<String, Object?> json) parse;

  /// 取实体的 id（用于定位已有条目、统计重复）。
  final String Function(T item) idOf;

  /// 取"原始字段指纹"（**必须排除用户覆盖层**，见 [_persist] 的说明）。
  final String Function(T item) fingerprintOf;

  /// 该条目是否带用户覆盖层（用于统计"有 N 条保留了你的修改"）。
  final bool Function(T item) hasOverride;

  /// 面向用户的名词，如 `作业`；用于日志与提示文案。
  ///
  /// 量词不在这里：它只影响 UI 文案，而 UI 侧（`PluginEntitySyncPage`）
  /// 本来就要自己拿一份（页面在同步之前就要显示"已选 N 门"这类文案）。
  final String itemLabel;
}

/// 取课程引用列表的结果（`fetchCourseList` 专用，不走增量落盘）。
class CourseRefFetchResult {
  const CourseRefFetchResult({
    this.refs = const <PluginCourseRef>[],
    this.error = '',
    this.warnings = const <String>[],
  });

  /// 插件返回的课程引用（已按 id 去重）。
  final List<PluginCourseRef> refs;

  /// 失败原因；空串表示成功。
  final String error;

  /// 插件给出的非致命警告。
  final List<String> warnings;

  /// 是否成功（注意：**成功且为空列表**是合法结果——确实一门课都没有）。
  bool get isSuccess => error.isEmpty;

  /// 失败结果。
  factory CourseRefFetchResult.failure(String error) =>
      CourseRefFetchResult(error: error);
}

/// 列表型实体同步服务（纯静态类）。
///
/// 契约：**任何情况都不抛异常**，失败一律返回带 [SyncOutcome] 的 [SyncReport]。
class PluginEntitySyncService {
  /// 纯静态工具类，禁止实例化。
  PluginEntitySyncService._();

  // ───────────────────────── 进度阶段名 ─────────────────────────

  /// 正在向插件请求数据（会带尝试次数）。
  static const String kStageFetching = 'fetching';

  /// 正在把解析出的条目落盘。
  static const String kStageSaving = 'saving';

  // ───────────────────────── 重试策略 ─────────────────────────

  /// 总尝试次数上限（首发 + 重试）。
  ///
  /// 与课程同步一致取 3：校园网抖动场景够用，又不会让用户对着转圈等太久。
  /// **注意**：重试会**重放整个抓取流程**，所以只对网络类失败重试——
  /// 结构异常、凭证过期重试只会白白多打一遍接口（学习通还有风控）。
  static const int kMaxAttempts = 3;

  /// 第 N 次重试前的等待时长（索引 0 = 第一次重试）。
  ///
  /// 比课程同步更长：作业抓取会连打多个请求，学习通有反爬，
  /// 退避太短等于连续施压。
  static const List<Duration> kRetryBackoff = <Duration>[
    Duration(milliseconds: 1200),
    Duration(milliseconds: 3000),
  ];

  /// 单次调用插件的超时。
  ///
  /// 比课程同步的 20s 宽裕得多：抓 N 门课的作业要发约 `4 × N` 个请求，
  /// 且宿主是**严格串行**的（风控要求）。60s 能覆盖"勾 3~5 门课"的正常耗时；
  /// 勾太多课本来就会撞风控，UI 侧有提示引导分批。
  static const Duration kSyncTimeout = Duration(seconds: 60);

  /// 系统类失败（重试无用）的文案，按错误短标识映射。
  ///
  /// 这些标识来自 `PluginContext._errorName`（宿主自己的枚举），**与学校无关**。
  static const Map<String, String> _kHttpErrorHints = <String, String>{
    'bad_certificate': 'HTTPS 证书校验未通过，请确认 App 是重新编译安装的版本。',
    'cancelled': '请求已被取消，请重试。',
    'unknown': '网络层返回了未知错误。',
  };

  // ───────────────────────── 契约工厂 ─────────────────────────

  /// 作业的同步契约。
  static PluginEntitySpec<Homework> homeworkSpec() => PluginEntitySpec<Homework>(
        entry: 'fetchHomeworks',
        payloadKey: 'homeworks',
        itemLabel: '作业',
        parse: _parseHomework,
        idOf: (Homework h) => h.id,
        fingerprintOf: _homeworkFingerprint,
        hasOverride: (Homework h) => h.userOverride != null,
      );

  /// 考试的同步契约。
  static PluginEntitySpec<Exam> examSpec() => PluginEntitySpec<Exam>(
        entry: 'fetchExams',
        payloadKey: 'exams',
        itemLabel: '考试',
        parse: _parseExam,
        idOf: (Exam e) => e.id,
        fingerprintOf: _examFingerprint,
        hasOverride: (Exam e) => e.userOverride != null,
      );

  /// 抓取作业入口的入参键名（插件约定）。
  static const String kArgCourses = 'courses';

  /// 抓取作业正文的开关（插件约定，仅作业入口使用）。
  static const String kArgWithContent = 'withContent';

  /// 构造 `fetchHomeworks` / `fetchExams` 的入参。
  ///
  /// [refs] 会被 `toJson()` **原样**交给插件——内核不认识里面的字段。
  static Map<String, dynamic> buildCoursesArgs(
    List<PluginCourseRef> refs, {
    bool withContent = true,
  }) {
    return <String, dynamic>{
      kArgCourses: refs.map((PluginCourseRef r) => r.toJson()).toList(),
      kArgWithContent: withContent,
    };
  }

  // ───────────────────────── 课程引用列表 ─────────────────────────

  /// 调用插件的 `fetchCourseList` 拿"可勾选的课程列表"。
  ///
  /// 与 [sync] 的区别：本方法**不落盘**、不产出 [SyncReport]——它拿的是
  /// 插件自报的原始课程对象（[PluginCourseRef]），仅供勾选界面使用，
  /// 不是内核的 [Course]。
  ///
  /// 入口名默认 `fetchCourseList`：这是"作业 / 考试能力"的插件约定
  /// （与 `fetchCourses` 区分开——后者产出内核课程模型，用于课表）。
  static Future<CourseRefFetchResult> fetchCourseRefs({
    required String pluginId,
    required PluginHandle? handle,
    String entry = 'fetchCourseList',
    void Function(String stage, String message)? onProgress,
  }) async {
    if (handle == null) {
      return CourseRefFetchResult.failure('插件未加载，请先在插件列表中启用它。');
    }
    if (!handle.entries.contains(entry)) {
      return CourseRefFetchResult.failure(
        '该插件未提供课程列表入口（$entry），无法列出可抓取的课程。',
      );
    }

    final _CallResult call = await _callEntry(
      handle: handle,
      entry: entry,
      args: null,
      payloadKey: 'courses',
      onProgress: onProgress,
      progressLabel: '正在获取课程列表…',
    );

    if (!call.isSuccess) return CourseRefFetchResult.failure(call.reason);

    final List<PluginCourseRef> refs =
        dedupeCourseRefs(parseCourseRefs(call.payload!['courses']));
    debugPrint('[PluginEntitySyncService] $pluginId 列出 ${refs.length} 门课程');
    return CourseRefFetchResult(refs: refs, warnings: call.warnings);
  }

  // ───────────────────────── 同步主流程 ─────────────────────────

  /// 执行一次实体同步（作业 / 考试）。
  ///
  /// - [handle] 由 `PluginProvider.getHandle(pluginId)` 提供；
  /// - [spec] 决定入口名、载荷键与解析方式；
  /// - [store] 落盘目标（`HomeworkProvider` / `ExamProvider`）；
  /// - [args] 透传给插件入口的入参（作业 / 考试都要 `{courses: [...]}`）；
  /// - [onProgress] 可选进度回调（在 await 之间同步调用，可直接 setState）；
  /// - [onReport] **无论成败**都会被调用一次，供调用方沉淀站内消息。
  ///
  /// 重试语义：只重试网络类失败（超时 / 连不上 / 5xx）。
  static Future<SyncReport> sync<T>({
    required String pluginId,
    required PluginHandle? handle,
    required PluginEntitySpec<T> spec,
    required EntityStore<T> store,
    Map<String, dynamic>? args,
    void Function(String stage, String message)? onProgress,
    void Function(SyncReport report)? onReport,
  }) async {
    final SyncReport report = await _sync<T>(
      pluginId: pluginId,
      handle: handle,
      spec: spec,
      store: store,
      args: args,
      onProgress: onProgress,
    );
    // 放在这里而不是每个 return 前，是为了**不可能漏掉**某条失败路径。
    onReport?.call(report);
    return report;
  }

  static Future<SyncReport> _sync<T>({
    required String pluginId,
    required PluginHandle? handle,
    required PluginEntitySpec<T> spec,
    required EntityStore<T> store,
    Map<String, dynamic>? args,
    void Function(String stage, String message)? onProgress,
  }) async {
    final Stopwatch watch = Stopwatch()..start();

    if (handle == null) {
      return SyncReport.failure(
        pluginId: pluginId,
        outcome: SyncOutcome.unavailable,
        reason: '插件未加载，请先在插件列表中启用它。',
        duration: watch.elapsed,
      );
    }
    if (!handle.entries.contains(spec.entry)) {
      return SyncReport.failure(
        pluginId: pluginId,
        outcome: SyncOutcome.unsupported,
        reason: '该插件未提供${spec.itemLabel}同步入口（${spec.entry}）。',
        duration: watch.elapsed,
      );
    }

    final _CallResult call = await _callEntry(
      handle: handle,
      entry: spec.entry,
      args: args,
      payloadKey: spec.payloadKey,
      onProgress: onProgress,
      progressLabel: '正在抓取${spec.itemLabel}…',
    );

    if (call.isSuccess) {
      return _persist<T>(
        pluginId: pluginId,
        spec: spec,
        store: store,
        payload: call.payload!,
        attempts: call.attempts,
        httpErrors: call.httpErrors,
        onProgress: onProgress,
        watch: watch,
      );
    }

    return SyncReport.failure(
      pluginId: pluginId,
      outcome: call.outcome,
      reason: call.reason,
      attempts: call.attempts,
      httpErrors: call.httpErrors,
      warnings: call.warnings,
      duration: watch.elapsed,
    );
  }

  /// 调用插件入口（含重试与归类）——**作业 / 考试 / 课程列表三条路径共用**。
  ///
  /// 返回的 [_CallResult] 里要么有 `payload`（成功），要么有 `outcome + reason`。
  static Future<_CallResult> _callEntry({
    required PluginHandle handle,
    required String entry,
    required Map<String, dynamic>? args,
    required String payloadKey,
    required String progressLabel,
    void Function(String stage, String message)? onProgress,
  }) async {
    final List<String> seenHttpErrors = <String>[];

    for (int attempt = 1; attempt <= kMaxAttempts; attempt++) {
      onProgress?.call(
        kStageFetching,
        attempt == 1
            ? progressLabel
            : '正在重试（第 $attempt 次，共 $kMaxAttempts 次）…',
      );

      final JsSandboxResult result = await _execute(handle, entry, args);
      for (final String error in result.httpErrors) {
        if (!seenHttpErrors.contains(error)) seenHttpErrors.add(error);
      }

      final _Classified classified = _classify(result, payloadKey);

      if (classified.outcome == SyncOutcome.success) {
        return _CallResult.ok(
          payload: classified.payload!,
          warnings: classified.warnings,
          attempts: attempt,
          httpErrors: seenHttpErrors,
        );
      }

      // 不可重试 → 立刻返回，把原因原样交给 UI。
      if (classified.outcome != SyncOutcome.networkError) {
        return _CallResult.fail(
          outcome: classified.outcome,
          reason: classified.reason,
          warnings: classified.warnings,
          attempts: attempt,
          httpErrors: seenHttpErrors,
        );
      }

      // 可重试但次数用尽 → 返回失败（附带"已重试过"的事实）。
      if (attempt >= kMaxAttempts) {
        return _CallResult.fail(
          outcome: SyncOutcome.networkError,
          reason: '${classified.reason}（已重试 $kMaxAttempts 次仍未成功，'
              '请检查是否连上了校园网 / VPN）',
          warnings: classified.warnings,
          attempts: attempt,
          httpErrors: seenHttpErrors,
        );
      }

      final Duration delay = kRetryBackoff[
          (attempt - 1).clamp(0, kRetryBackoff.length - 1)];
      onProgress?.call(
        kStageFetching,
        '网络失败，${delay.inMilliseconds}ms 后重试…',
      );
      await Future<void>.delayed(delay);
    }

    // 理论不可达（循环内每条路径都 return）；兜底避免"函数末尾无返回"。
    return _CallResult.fail(
      outcome: SyncOutcome.failed,
      reason: '同步未产生结果。',
      attempts: kMaxAttempts,
      httpErrors: seenHttpErrors,
    );
  }

  /// 调用插件入口；异常在这里被吞掉并转成 `error` 结果。
  static Future<JsSandboxResult> _execute(
    PluginHandle handle,
    String entry,
    Map<String, dynamic>? args,
  ) async {
    try {
      return await handle.execute(entry, args: args, timeout: kSyncTimeout);
    } catch (e) {
      debugPrint('[PluginEntitySyncService] 调用 $entry 抛异常：$e');
      return JsSandboxResult.error('调用插件入口函数异常：$e');
    }
  }

  /// 把一次执行结果归类成"成功 / 可重试 / 不可重试"。
  static _Classified _classify(JsSandboxResult result, String payloadKey) {
    switch (result.status) {
      case JsSandboxStatus.timeout:
        return _Classified.fail(
          SyncOutcome.timeout,
          '插件执行超时（抓取的课程太多或网络无响应）。可少勾几门课再试。',
        );
      case JsSandboxStatus.unavailable:
        return _Classified.fail(
          SyncOutcome.unavailable,
          '插件不可用：${result.message ?? '沙箱未就绪'}',
        );
      case JsSandboxStatus.error:
        // 插件入口抛错（JS 异常）或重放轮数超限 —— 统一按不可重试处理。
        return _Classified.fail(
          SyncOutcome.protocolError,
          '插件执行出错：${result.message ?? '未知错误'}',
        );
      case JsSandboxStatus.success:
        break;
    }

    final String? value = result.value;
    if (value == null || value.isEmpty) {
      return _Classified.fail(SyncOutcome.protocolError, '插件没有返回任何内容。');
    }

    final Object? decoded = _tryDecode(value);
    if (decoded is! Map) {
      return _Classified.fail(
        SyncOutcome.protocolError,
        '插件返回值不是 JSON 对象（可能是插件版本与内核不匹配）。',
      );
    }

    final Map<String, Object?> map = _asStringKeyedMap(decoded);
    final List<String> warnings = _stringList(map['warnings']);

    // 插件约定：失败返回 {error: '人话原因'}。
    final String pluginError = _asString(map['error']);
    if (pluginError.isNotEmpty) {
      return _classifyPluginError(
        pluginError: pluginError,
        payload: map,
        warnings: warnings,
        httpErrors: result.httpErrors,
      );
    }

    if (map[payloadKey] is! List) {
      return _Classified.fail(
        SyncOutcome.protocolError,
        '插件返回值里没有 $payloadKey 数组。',
        warnings: warnings,
      );
    }

    return _Classified.ok(map, warnings: warnings);
  }

  /// 插件返回了 `{error: ...}` —— 判断它是"可重试的网络问题"还是"别的"。
  ///
  /// 判定顺序（从最可靠到最兜底）：
  /// 1. 插件显式声明 `retryable: true`（Phase 4.3 起的约定）；
  /// 2. 宿主的 HTTP 错误类别（`timeout` / `connection` / `bad_response`）；
  /// 3. 都没有 → 按不可重试处理（保守）。
  static _Classified _classifyPluginError({
    required String pluginError,
    required Map<String, Object?> payload,
    required List<String> warnings,
    required List<String> httpErrors,
  }) {
    final bool declaredRetryable = payload['retryable'] == true;
    final String errorKind = _asString(payload['errorKind']).toLowerCase();
    final String effectiveKind =
        errorKind.isNotEmpty ? errorKind : _lastHttpError(httpErrors);

    if (declaredRetryable || _isTransientHttpError(effectiveKind)) {
      return _Classified.fail(
        SyncOutcome.networkError,
        '网络请求失败：$pluginError',
        warnings: warnings,
      );
    }

    if (effectiveKind.isNotEmpty &&
        _kHttpErrorHints.containsKey(effectiveKind)) {
      return _Classified.fail(
        SyncOutcome.failed,
        '$pluginError\n${_kHttpErrorHints[effectiveKind]}',
        warnings: warnings,
      );
    }

    if (_looksLikeAuthProblem(pluginError)) {
      return _Classified.fail(
        SyncOutcome.authRequired,
        pluginError,
        warnings: warnings,
      );
    }

    return _Classified.fail(
      SyncOutcome.protocolError,
      pluginError,
      warnings: warnings,
    );
  }

  /// 把解析出的条目增量落盘。
  ///
  /// **增量策略**（与 `CourseSyncService` 一致）：
  /// - 库里没有该 id → 写入（`added`）；
  /// - 有且原始字段一致 → **跳过落盘**（`unchanged`）；
  /// - 有且原始字段不同 → 覆盖写入（`updated`）。
  ///
  /// **覆盖层保留**：传给 [EntityStore.save] 的是插件给的**原始模型**
  /// （不带 `userOverride`），由实现方负责把用户已有的覆盖层挂回去。
  /// 本方法**不碰** `userOverride`，也不做任何删除——插件里消失的作业 / 考试
  /// 同样保留（历史记录不该因为教务系统清理而消失）。
  static Future<SyncReport> _persist<T>({
    required String pluginId,
    required PluginEntitySpec<T> spec,
    required EntityStore<T> store,
    required Map<String, Object?> payload,
    required int attempts,
    required List<String> httpErrors,
    required void Function(String stage, String message)? onProgress,
    required Stopwatch watch,
  }) async {
    final List<String> warnings = _stringList(payload['warnings']);
    final List<Object?> rawList = payload[spec.payloadKey]! as List<Object?>;

    // 逐条解析；坏数据跳过并计数（用于提示"有 N 条被跳过"）。
    final Map<String, T> byId = <String, T>{};
    int unparsable = 0;
    for (int i = 0; i < rawList.length; i++) {
      final Object? item = rawList[i];
      if (item is! Map) {
        unparsable++;
        continue;
      }
      final T? parsed = spec.parse(_asStringKeyedMap(item));
      if (parsed == null || spec.idOf(parsed).isEmpty) {
        debugPrint('[PluginEntitySyncService] 第 $i 条${spec.itemLabel}'
            '缺少 id 或无法解析，已跳过');
        unparsable++;
        continue;
      }
      byId[spec.idOf(parsed)] = parsed;
    }

    // 因重复 id 被覆盖的条数：解析成功的总数 - 去重后的条数。
    final int duplicated = (rawList.length - unparsable) - byId.length;
    final int skipped = unparsable + duplicated;

    onProgress?.call(kStageSaving, '正在保存${spec.itemLabel}…');

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int userEdited = 0;

    for (final T incoming in byId.values) {
      final String id = spec.idOf(incoming);
      final T? existing = store.getById(id);
      if (existing == null) {
        added++;
        await store.save(incoming);
        continue;
      }
      if (spec.fingerprintOf(existing) == spec.fingerprintOf(incoming)) {
        unchanged++;
        continue;
      }
      updated++;
      // 这条"用户改动没被同步冲掉"是可见证据（CONTEXT 3.3），单独统计。
      if (spec.hasOverride(existing)) userEdited++;
      await store.save(incoming);
    }

    debugPrint('[PluginEntitySyncService] $pluginId ${spec.itemLabel}同步完成：'
        '新增 $added、更新 $updated、未变 $unchanged、跳过 $skipped'
        '${warnings.isEmpty ? '' : '、警告 ${warnings.length} 条'}');

    return SyncReport(
      pluginId: pluginId,
      outcome: SyncOutcome.success,
      added: added,
      updated: updated,
      unchanged: unchanged,
      skipped: skipped,
      userEdited: userEdited,
      warnings: warnings,
      attempts: attempts,
      httpErrors: httpErrors,
      duration: watch.elapsed,
    );
  }

  // ───────────────────────── 解析与指纹 ─────────────────────────

  /// 解析一条作业 JSON；`id` 为空视为坏数据。
  static Homework? _parseHomework(Map<String, Object?> json) {
    try {
      final Homework homework = Homework.fromJson(_toDynamicMap(json));
      return homework.id.isEmpty ? null : homework;
    } catch (e) {
      debugPrint('[PluginEntitySyncService] 作业解析失败，已跳过：$e');
      return null;
    }
  }

  /// 解析一条考试 JSON；`id` 为空视为坏数据。
  static Exam? _parseExam(Map<String, Object?> json) {
    try {
      final Exam exam = Exam.fromJson(_toDynamicMap(json));
      return exam.id.isEmpty ? null : exam;
    } catch (e) {
      debugPrint('[PluginEntitySyncService] 考试解析失败，已跳过：$e');
      return null;
    }
  }

  /// 作业的"原始字段指纹"：**不含** `userOverride`。
  ///
  /// 只比原始字段是有意的——用户的覆盖层变化（改了截止时间、勾了已完成）
  /// 不该被算成"插件数据变了"，否则用户每勾一次，下次同步都会多写一次盘。
  ///
  /// 手写拼接而非 `jsonEncode(homework.toJson())`：`toJson` 含 `userOverride`，
  /// 要先剥离；手写也顺手把列表字段归一，避免顺序不同造成假差异。
  static String _homeworkFingerprint(Homework h) {
    final List<String> parts = <String>[
      'id=${h.id}',
      'title=${h.title}',
      'desc=${h.description}',
      'course=${h.courseName}',
      'courseId=${h.courseId}',
      'deadline=${h.deadline?.toIso8601String()}',
      'publish=${h.publishTime?.toIso8601String()}',
      'completed=${h.completed}',
      'status=${h.submitStatus}',
      'source=${h.sourcePluginId}',
    ];
    final List<String> attachments = List<String>.of(h.attachments)..sort();
    parts.add('attachments=${attachments.join(',')}');
    return parts.join('|');
  }

  /// 考试的"原始字段指纹"：**不含** `userOverride`。
  static String _examFingerprint(Exam e) {
    return <String>[
      'id=${e.id}',
      'name=${e.name}',
      'start=${e.startTime.toIso8601String()}',
      'end=${e.endTime?.toIso8601String()}',
      'location=${e.location}',
      'seat=${e.seatNumber}',
      'type=${e.examType}',
      'unit=${e.unit}',
      'duration=${e.durationMinutes}',
      'courseId=${e.courseId}',
      'courseName=${e.courseName}',
      'note=${e.note}',
      'source=${e.sourcePluginId}',
    ].join('|');
  }

  // ───────────────────────── 纯函数工具 ─────────────────────────

  /// 宿主的 HTTP 错误标识里，哪些属于"重试可能成功"。
  ///
  /// - `timeout` —— 连接 / 发送 / 接收超时：网络抖动，最值得重试；
  /// - `connection` —— 连不上（DNS / 路由 / 校园网未连）；
  /// - `bad_response` —— 收到 5xx 等异常响应：服务端临时故障。
  ///
  /// **不含** `bad_certificate`（配置问题）与 `cancelled`（用户主动取消）。
  static bool _isTransientHttpError(String kind) {
    switch (kind) {
      case 'timeout':
      case 'connection':
      case 'bad_response':
        return true;
      default:
        return false;
    }
  }

  /// 取最后一个 HTTP 错误标识（与 `ctx.lastHttpError` 语义一致）。
  static String _lastHttpError(List<String> httpErrors) =>
      httpErrors.isEmpty ? '' : httpErrors.last.toLowerCase();

  /// 文案启发式：判断插件这句 error 是否属于"凭证问题"。
  ///
  /// 插件在 Cookie 为空时**根本不发请求**，宿主侧没有任何 HTTP 错误可依据，
  /// 所以只能靠文案。这类判断只影响提示与是否重试，不影响数据正确性。
  static bool _looksLikeAuthProblem(String message) {
    const List<String> keywords = <String>[
      '未登录',
      '登录已过期',
      '登录过期',
      '重新登录',
      'Cookie',
      'cookie',
      '凭证',
      '无权限',
      '401',
      '403',
    ];
    for (final String keyword in keywords) {
      if (message.contains(keyword)) return true;
    }
    return false;
  }

  /// 安全 jsonDecode：坏 JSON 返回 `null`，不抛异常。
  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('[PluginEntitySyncService] 解析插件返回值失败：$e');
      return null;
    }
  }

  /// 把任意 `Map` 转成 `Map<String, Object?>`（键统一 toString）。
  static Map<String, Object?> _asStringKeyedMap(Map<dynamic, dynamic> raw) {
    final Map<String, Object?> result = <String, Object?>{};
    raw.forEach((dynamic key, dynamic value) {
      if (key != null) result['$key'] = value;
    });
    return result;
  }

  /// `Map<String, Object?>` → `Map<String, dynamic>`（模型 `fromJson` 的入参类型）。
  static Map<String, dynamic> _toDynamicMap(Map<String, Object?> raw) {
    final Map<String, dynamic> result = <String, dynamic>{};
    raw.forEach((String key, Object? value) => result[key] = value);
    return result;
  }

  /// 取字符串字段，非字符串时返回空串。
  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return '$value';
  }

  /// 把任意值转成字符串列表（忽略空值）。
  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.where((Object? e) => e != null).map((Object? e) => '$e')
        .toList(growable: false);
  }
}

/// 一次入口调用的结果（成功带 `payload`，失败带 `outcome + reason`）。
class _CallResult {
  const _CallResult._({
    required this.outcome,
    required this.reason,
    required this.warnings,
    required this.attempts,
    required this.httpErrors,
    this.payload,
  });

  factory _CallResult.ok({
    required Map<String, Object?> payload,
    required List<String> warnings,
    required int attempts,
    required List<String> httpErrors,
  }) =>
      _CallResult._(
        outcome: SyncOutcome.success,
        reason: '',
        warnings: warnings,
        attempts: attempts,
        httpErrors: httpErrors,
        payload: payload,
      );

  factory _CallResult.fail({
    required SyncOutcome outcome,
    required String reason,
    required int attempts,
    required List<String> httpErrors,
    List<String> warnings = const <String>[],
  }) =>
      _CallResult._(
        outcome: outcome,
        reason: reason,
        warnings: warnings,
        attempts: attempts,
        httpErrors: httpErrors,
      );

  final SyncOutcome outcome;
  final String reason;
  final List<String> warnings;
  final int attempts;
  final List<String> httpErrors;

  /// 仅在 [outcome] 为 `success` 时非空。
  final Map<String, Object?>? payload;

  bool get isSuccess => outcome == SyncOutcome.success;
}

/// 一次执行结果的归类中间态。
class _Classified {
  const _Classified._({
    required this.outcome,
    this.reason = '',
    this.payload,
    this.warnings = const <String>[],
  });

  factory _Classified.ok(
    Map<String, Object?> payload, {
    List<String> warnings = const <String>[],
  }) =>
      _Classified._(
        outcome: SyncOutcome.success,
        payload: payload,
        warnings: warnings,
      );

  factory _Classified.fail(
    SyncOutcome outcome,
    String reason, {
    List<String> warnings = const <String>[],
  }) =>
      _Classified._(outcome: outcome, reason: reason, warnings: warnings);

  final SyncOutcome outcome;
  final String reason;

  /// 仅在 [outcome] 为 `success` 时非空。
  final Map<String, Object?>? payload;
  final List<String> warnings;
}

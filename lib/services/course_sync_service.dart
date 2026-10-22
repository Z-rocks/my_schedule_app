// Phase 4.3：课程数据同步服务（增量 / 覆盖层保留 / 失败重试）。
//
// 本文件把原先写死在 `PluginDetailPage._syncNow` 里的同步流程搬到服务层，
// 原因是那一版把"网络重试、结果分类、落盘策略"全都塞在页面里，导致：
//   ① 其它入口（Phase 4.4 的课表页同步按钮、定时同步）无法复用；
//   ② 失败原因只剩一句中文，无法判断"该不该重试"；
//   ③ UI 拿不到中间进度，只能给一个"正在同步…"然后干等。
//
// 分层（CONTEXT 3.1：内核不认识任何学校字段）：
//   插件      —— 负责"拉数据 + 转成内核的 Course JSON"（各校字段名只有它知道）
//   本服务    —— 负责"调用 → 归类结果 → 重试 → 增量落盘"（完全没有学校信息）
//   页面      —— 只负责把 [SyncReport] 渲染成人话
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course.dart';
import '../models/semester_config.dart';
import '../models/sync_report.dart';
import '../models/time_place.dart';
import '../providers/course_provider.dart';
import '../runtime/js_sandbox.dart';
import '../runtime/plugin_handle.dart';

/// 同步进度回调：`stage` 是稳定的机器可读阶段名（UI 靠它选图标/文案），
/// `message` 是可以直接显示的进度文案。
typedef SyncProgressCallback = void Function(String stage, String message);

/// 同步结束回调（**Phase 7**）：无论成功失败都会被调用一次。
///
/// 用途：让调用方把同步结果**沉淀成一条站内消息**（`MessageProvider`），
/// 而不是只弹一个转瞬即逝的 SnackBar。
/// 本服务不直接依赖 `MessageProvider`——那是 Provider 层的职责，
/// 服务层只负责"告诉调用方结果"。
typedef SyncReportCallback = void Function(SyncReport report);

/// 课程同步服务（纯静态类）。
///
/// 契约：**任何情况都不抛异常**，失败一律返回带 [SyncOutcome] 的 [SyncReport]。
/// 页面只需要 `report.isSuccess ? 成功提示 : 失败提示`，不需要 try/catch。
class CourseSyncService {
  /// 纯静态工具类，禁止实例化。
  CourseSyncService._();

  // ───────────────────────── 进度阶段名 ─────────────────────────

  /// 正在向教务系统请求数据（会带尝试次数）。
  static const String kStageFetching = 'fetching';

  /// 正在把解析出的课程落盘。
  static const String kStageSaving = 'saving';

  // ───────────────────────── 重试策略 ─────────────────────────

  /// 总尝试次数上限（首发 + 重试）。3 次在"校园网抖动"场景下够用，
  /// 又不会让用户对着转圈等太久。
  static const int kMaxAttempts = 3;

  /// 第 N 次重试前的等待时长（索引 0 = 第一次重试）。
  ///
  /// 指数退避：教务系统在压力下返回 5xx 时，立刻重试通常还是失败。
  static const List<Duration> kRetryBackoff = <Duration>[
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  /// 单次调用插件的超时。
  ///
  /// 比沙箱默认的 1s 宽裕得多：`fetchCourses` 内部要发 2 个网络请求，
  /// 而每个请求自身还有 10s 连接 / 15s 接收超时（`PluginContext`）。
  /// 这里给 20s，实际瓶颈在网络而不在 JS 执行。
  static const Duration kSyncTimeout = Duration(seconds: 20);

  /// 系统类失败（重试无用）的文案，按错误短标识映射。
  ///
  /// 这些标识来自 `PluginContext._errorName`（宿主自己的枚举），
  /// **与学校无关**，所以在这里硬编码不违反 CONTEXT 3.1。
  static const Map<String, String> _kHttpErrorHints = <String, String>{
    'bad_certificate':
        'HTTPS 证书校验未通过。若教务系统用自签证书，请确认 App 是重新编译安装的版本。',
    'cancelled': '请求已被取消，请重试。',
    'unknown': '网络层返回了未知错误。',
  };

  /// 执行一次课程同步。
  ///
  /// - [handle] 由 `PluginProvider.getHandle(pluginId)` 提供；
  /// - [courses] 落盘目标（`CourseProvider`）；
  /// - [onProgress] 可选进度回调（在 await 之间同步调用，可直接 setState）；
  /// - [semester] 学期配置，注入给插件当 `ctx.semester`。**只有**需要把
  ///   "具体日期"换算成"第几周"的插件才会用到（例如大物实验系统给的是
  ///   `2026/9/14` 而不是周次），不传就是 `null`，插件应自行降级。
  ///
  /// 重试语义：**只重试网络类失败**（超时 / 连不上 / 5xx）。凭证过期、
  /// 响应结构异常、插件不可用等一律不重试——重试只会让用户多等一轮。
  static Future<SyncReport> sync({
    required String pluginId,
    required PluginHandle? handle,
    required CourseProvider courses,
    SyncProgressCallback? onProgress,
    SyncReportCallback? onReport,
    SemesterConfig? semester,
  }) async {
    final SyncReport report = await _sync(
      pluginId: pluginId,
      handle: handle,
      courses: courses,
      onProgress: onProgress,
      semester: semester,
    );
    // 无论成败都通知一次：调用方（页面）用它落一条站内消息。
    // 放在这里而不是每个 return 前，是为了**不可能漏掉**某条失败路径。
    onReport?.call(report);
    return report;
  }

  /// `sync` 的实际实现。
  ///
  /// 拆出来是因为 [sync] 要在**所有**返回路径之后统一回调 `onReport`，
  /// 而原实现有 7 个 return —— 逐个加回调必然会漏。
  static Future<SyncReport> _sync({
    required String pluginId,
    required PluginHandle? handle,
    required CourseProvider courses,
    SyncProgressCallback? onProgress,
    SemesterConfig? semester,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    final List<String> seenHttpErrors = <String>[];
    // 学期摘要转成 JS 侧能直接吃的字面量；没配学期就是 null（插件自己降级）。
    final Map<String, Object?>? semesterPayload = _semesterPayload(semester);
    // 排查"实验没按日期落位"时第一眼要看的就是这行：注入了什么、有没有注入。
    debugPrint('[CourseSyncService] 注入学期配置：'
        '${semesterPayload ?? '未配置（插件将退回系统周次）'}');

    if (handle == null) {
      return SyncReport.failure(
        pluginId: pluginId,
        outcome: SyncOutcome.unavailable,
        reason: '插件未加载，请先在插件列表中启用它。',
        duration: watch.elapsed,
      );
    }

    // 插件没声明 fetchCourses 时不必执行——直接说清楚，别让它报"未定义函数"。
    if (!handle.entries.contains('fetchCourses')) {
      return SyncReport.failure(
        pluginId: pluginId,
        outcome: SyncOutcome.unsupported,
        reason: '该插件未提供课程同步入口（fetchCourses）。',
        duration: watch.elapsed,
      );
    }

    for (int attempt = 1; attempt <= kMaxAttempts; attempt++) {
      onProgress?.call(
        kStageFetching,
        attempt == 1
            ? '正在向教务系统请求数据…'
            : '正在重试（第 $attempt 次，共 $kMaxAttempts 次）…',
      );

      final JsSandboxResult result =
          await _executeFetch(handle, semester: semesterPayload);
      for (final String error in result.httpErrors) {
        if (!seenHttpErrors.contains(error)) seenHttpErrors.add(error);
      }

      final _FetchStatus status = _classify(result);

      if (status.outcome == SyncOutcome.success) {
        return _persist(
          pluginId: pluginId,
          courses: courses,
          payload: status.payload!,
          attempts: attempt,
          httpErrors: seenHttpErrors,
          onProgress: onProgress,
          watch: watch,
        );
      }

      // 不可重试 → 立刻返回，把原因原样交给 UI。
      if (status.outcome != SyncOutcome.networkError) {
        return SyncReport.failure(
          pluginId: pluginId,
          outcome: status.outcome,
          reason: status.reason,
          attempts: attempt,
          httpErrors: seenHttpErrors,
          warnings: status.warnings,
          duration: watch.elapsed,
        );
      }

      // 可重试但次数用尽 → 返回失败（附带已重试过的事实）。
      if (attempt >= kMaxAttempts) {
        return SyncReport.failure(
          pluginId: pluginId,
          outcome: SyncOutcome.networkError,
          reason: '${status.reason}（已重试 $kMaxAttempts 次仍未成功，'
              '请检查是否连上了校园网 / VPN）',
          attempts: attempt,
          httpErrors: seenHttpErrors,
          warnings: status.warnings,
          duration: watch.elapsed,
        );
      }

      // 退避后重试。等待期间沙箱是空闲的，不影响其它插件。
      final Duration delay = kRetryBackoff[
          (attempt - 1).clamp(0, kRetryBackoff.length - 1)];
      onProgress?.call(
        kStageFetching,
        '网络失败，${delay.inMilliseconds}ms 后重试…',
      );
      await Future<void>.delayed(delay);
    }

    // 理论不可达（循环内每条路径都 return）；兜底避免"函数末尾无返回"。
    return SyncReport.failure(
      pluginId: pluginId,
      outcome: SyncOutcome.failed,
      reason: '同步未产生结果。',
      attempts: kMaxAttempts,
      httpErrors: seenHttpErrors,
      duration: watch.elapsed,
    );
  }

  /// 调用插件的 `fetchCourses`；异常在这里被吞掉并转成 `error` 结果。
  ///
  /// `handle.execute` 本身已承诺不抛异常，这里是最后一道保险
  /// （例如 `PluginContext` 内部读到坏 JSON 之外的意外）。
  static Future<JsSandboxResult> _executeFetch(
    PluginHandle handle, {
    Map<String, Object?>? semester,
  }) async {
    try {
      return await handle.execute(
        'fetchCourses',
        timeout: kSyncTimeout,
        semester: semester,
      );
    } catch (e) {
      debugPrint('[CourseSyncService] 调用 fetchCourses 抛异常：$e');
      return JsSandboxResult.error('调用插件入口函数异常：$e');
    }
  }

  /// 学期配置 → 注入给插件的 `ctx.semester` 载荷。
  ///
  /// `startDate` 只保留年月日（`YYYY-MM-DD`）：插件是拿它做"日期差 ÷ 7"
  /// 的整数运算，时分秒带上只会引入时区/夏令时误差。
  static Map<String, Object?>? _semesterPayload(SemesterConfig? config) {
    if (config == null) return null;
    final DateTime start = config.startDate;
    final String ymd = '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    return <String, Object?>{
      'startDate': ymd,
      'totalWeeks': config.totalWeeks,
    };
  }

  /// 把一次执行结果归类成"成功 / 可重试 / 不可重试"。
  ///
  /// 判定顺序很重要：先看沙箱四态（宿主自己的结论最可靠），再看插件返回的
  /// `error` 文案，最后才看 HTTP 错误类别。
  static _FetchStatus _classify(JsSandboxResult result) {
    switch (result.status) {
      case JsSandboxStatus.timeout:
        return _FetchStatus.fail(
          SyncOutcome.timeout,
          '插件执行超时（可能卡在死循环或网络请求无响应）。',
        );
      case JsSandboxStatus.unavailable:
        return _FetchStatus.fail(
          SyncOutcome.unavailable,
          '插件不可用：${result.message ?? '沙箱未就绪'}',
        );
      case JsSandboxStatus.error:
        // 插件入口抛错（JS 异常）或重放轮数超限。重放轮数超限有可能是
        // 网络抖动导致的反复重排，但 JS 抛错不会自愈 —— 统一按不可重试处理。
        return _FetchStatus.fail(
          SyncOutcome.protocolError,
          '插件执行出错：${result.message ?? '未知错误'}',
        );
      case JsSandboxStatus.success:
        break;
    }

    final String? value = result.value;
    if (value == null || value.isEmpty) {
      return _FetchStatus.fail(
        SyncOutcome.protocolError,
        '插件没有返回任何内容。',
      );
    }

    final Object? decoded = _tryDecode(value);
    if (decoded is! Map) {
      return _FetchStatus.fail(
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

    if (map['courses'] is! List) {
      return _FetchStatus.fail(
        SyncOutcome.protocolError,
        '插件返回值里没有 courses 数组。',
        warnings: warnings,
      );
    }

    return _FetchStatus.ok(map, warnings: warnings);
  }

  /// 插件返回了 `{error: ...}` —— 判断它是"可重试的网络问题"还是"别的"。
  ///
  /// 判定顺序（从最可靠到最兜底）：
  /// 1. **插件显式声明** `retryable: true` —— Phase 4.3 起的约定。插件最清楚
  ///    自己这次失败是不是网络层的（只有它能区分"响应结构不符"和"请求没发出去"）；
  /// 2. **宿主的 HTTP 错误类别** —— 给没升级契约的老插件兜底：宿主自己记录到
  ///    了 `timeout` / `connection` / `bad_response`，那也一定是网络问题；
  /// 3. 都没有 → 按不可重试处理（保守：宁可让用户手动重试，也不要自动空转）。
  ///
  /// 全程**不解析插件的 response body**，只用宿主的错误枚举与插件的布尔标志，
  /// 因此不涉及任何学校相关字段（CONTEXT 3.1）。
  static _FetchStatus _classifyPluginError({
    required String pluginError,
    required Map<String, Object?> payload,
    required List<String> warnings,
    required List<String> httpErrors,
  }) {
    final bool declaredRetryable = payload['retryable'] == true;
    final String errorKind = _asString(payload['errorKind']).toLowerCase();
    final String effectiveKind =
        errorKind.isNotEmpty ? errorKind : _lastHttpError(httpErrors);

    // 1) 网络类失败：插件声明了，或宿主的错误类别说明是网络问题。
    if (declaredRetryable || _isTransientHttpError(effectiveKind)) {
      return _FetchStatus.fail(
        SyncOutcome.networkError,
        '网络请求失败：$pluginError',
        warnings: warnings,
      );
    }

    // 2) 系统类问题（证书 / 被取消 / 未知）：重试无用，但要给可执行的建议。
    if (effectiveKind.isNotEmpty && _kHttpErrorHints.containsKey(effectiveKind)) {
      return _FetchStatus.fail(
        SyncOutcome.failed,
        '$pluginError\n${_kHttpErrorHints[effectiveKind]}',
        warnings: warnings,
      );
    }

    // 3) 没有任何网络失败 → 插件自己判定为不可继续。
    //    最常见的是"Cookie 为空 / 已过期"，其次是"响应结构异常"。
    //    这两类都**不值得重试**，但要引导用户做正确的动作。
    if (_looksLikeAuthProblem(pluginError)) {
      return _FetchStatus.fail(
        SyncOutcome.authRequired,
        pluginError,
        warnings: warnings,
      );
    }

    return _FetchStatus.fail(
      SyncOutcome.protocolError,
      pluginError,
      warnings: warnings,
    );
  }

  /// 把解析出的课程增量落盘。
  ///
  /// **增量策略**（Phase 4.3 的核心）：
  /// - 库里没有该 id → 写入（`added`）；
  /// - 有且原始字段一致 → **跳过落盘**（`unchanged`），只做一次字符串比较就省掉
  ///   一次 Hive 写 + 一次 notifyListeners，课程多时差别明显；
  /// - 有且原始字段不同 → 覆盖写入（`updated`）。
  ///
  /// **覆盖层保留**：这里传给 `saveCourse` 的是插件给的**原始课程**（不带
  /// `userOverride`），由 `CourseProvider.saveCourse` 负责把用户已有的覆盖层
  /// 挂回去（CONTEXT 3.3）。本方法**不碰** `userOverride`，也不做任何删除——
  /// 教务系统里消失的课程同样保留，只能由用户显式隐藏。
  static Future<SyncReport> _persist({
    required String pluginId,
    required CourseProvider courses,
    required Map<String, Object?> payload,
    required int attempts,
    required List<String> httpErrors,
    required SyncProgressCallback? onProgress,
    required Stopwatch watch,
  }) async {
    final List<String> warnings = _stringList(payload['warnings']);
    final List<Course> parsed = parseCourses(payload['courses']);

    // 同一次同步里如果插件返回了重复 id，后者会覆盖前者；这里先去重，
    // 保证计数与最终落盘结果一致（最终结果里一个 id 只会有一条）。
    final Map<String, Course> byId = <String, Course>{};
    for (final Course course in parsed) {
      byId[course.id] = course;
    }

    // 触发提示的"没被采纳"条目 = 解析失败的 + 因重复 id 被覆盖的。
    // 两者互不重叠：解析失败的条目根本没进 parsed，不会出现在 byId 里。
    final int skipped =
        _countUnparsable(payload['courses']) + (parsed.length - byId.length);

    // "插件返回了空数组"是合法结果（这学期确实没选课），但与"拉到了课"要区分开，
    // 所以照样成功返回，只是计数全为 0。
    onProgress?.call(kStageSaving, '正在保存课程…');

    int added = 0;
    int updated = 0;
    int unchanged = 0;
    int userEdited = 0;

    for (final Course incoming in byId.values) {
      final Course? existing = courses.getById(incoming.id);
      if (existing == null) {
        added++;
        await courses.saveCourse(incoming);
        continue;
      }
      if (_normalize(existing) == _normalize(incoming)) {
        unchanged++;
        continue;
      }
      updated++;
      if (existing.userOverride != null) userEdited++;
      await courses.saveCourse(incoming);
    }

    debugPrint('[CourseSyncService] $pluginId 同步完成：新增 $added、更新 $updated、'
        '未变 $unchanged、跳过 $skipped、其中带用户修改 $userEdited'
        '${warnings.isEmpty ? '' : '、警告 ${warnings.length} 条'}');

    return SyncReport(
      pluginId: pluginId,
      outcome: SyncOutcome.success,
      added: added,
      updated: updated,
      unchanged: unchanged,
      skipped: skipped,
      userEdited: userEdited,
      sectionTimes: _asInt(payload['sectionTimes']),
      allUnits: _asDoubleOrNull(payload['allUnits']),
      warnings: warnings,
      attempts: attempts,
      httpErrors: httpErrors,
      duration: watch.elapsed,
    );
  }

  // ───────────────────────── 纯函数工具 ─────────────────────────

  /// 逐条把插件返回的课程 JSON 解析成 [Course]；坏数据跳过、不抛异常。
  ///
  /// 暴露为公开静态方法是为了让"解析容错"这段可被独立复用与检查
  /// （页面不再自己实现一份）。
  static List<Course> parseCourses(Object? raw) {
    if (raw is! List) return const <Course>[];
    final List<Course> result = <Course>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is! Map) {
        debugPrint('[CourseSyncService] 第 $i 条课程不是对象，已跳过');
        continue;
      }
      try {
        final Course course = Course.fromJson(_asStringKeyedMap(item));
        if (course.id.isEmpty) {
          debugPrint('[CourseSyncService] 第 $i 条课程缺少 id，已跳过');
          continue;
        }
        result.add(course);
      } catch (e) {
        // Course.fromJson 本身已经很宽容，这里只是最后一道保险。
        debugPrint('[CourseSyncService] 第 $i 条课程解析失败，已跳过：$e');
      }
    }
    return result;
  }

  /// 统计插件返回里**无法解析**的条目数（供 UI 提示"有 N 条被跳过"）。
  static int _countUnparsable(Object? raw) {
    if (raw is! List) return 0;
    int bad = 0;
    for (final Object? item in raw) {
      if (item is! Map) {
        bad++;
        continue;
      }
      try {
        if (Course.fromJson(_asStringKeyedMap(item)).id.isEmpty) bad++;
      } catch (_) {
        bad++;
      }
    }
    return bad;
  }

  /// 课程的"原始字段指纹"：**不含** `userOverride`。
  ///
  /// 只比原始字段是有意的——用户的覆盖层变化不该被算成"教务数据变了"，
  /// 否则用户每改一次课程名，下次同步都会被判成 updated 而多写一次盘。
  ///
  /// 手写拼接而非 `jsonEncode(course.toJson())`：
  /// ① `toJson` 含 `userOverride`，要先剥离；② 手写能把 `weeks` 归一成
  /// 与顺序无关的形式，避免教务系统两次返回的周次顺序不同就误判成"变化"。
  static String _normalize(Course course) {
    final List<String> parts = <String>[
      'id=${course.id}',
      'name=${course.name}',
      'teacher=${course.teacher}',
      'unit=${course.unit}',
      'category=${course.category}',
      'source=${course.sourcePluginId}',
    ];
    final List<String> places = course.timePlaces
        .map((TimePlace p) => '${p.day}/${p.startSession}/${p.length}/'
            '${p.room}/${p.weekType.name}/${_sortedWeeks(p.weeks)}')
        .toList()
      ..sort();
    parts.addAll(places);
    return parts.join('|');
  }

  /// 周次列表归一：去重 + 升序，消除"顺序不同"造成的假差异。
  static String _sortedWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final List<int> copy = List<int>.of(weeks)..sort();
    final List<int> unique = <int>[];
    for (final int week in copy) {
      if (unique.isEmpty || unique.last != week) unique.add(week);
    }
    return unique.join(',');
  }

  /// 宿主自己的 HTTP 错误标识里，哪些属于"重试可能成功"。
  ///
  /// 这条判断有两种用途：
  /// ① 插件**没有**显式声明 `retryable` 时的兜底（例如插件把 `ctx.http` 的
  ///    `throw` 吞掉、或干脆没写 `try/catch`）；
  /// ② 插件声明了 `retryable: true` 时，用 `effectiveKind` 决定提示文案。
  ///
  /// - `timeout` —— 连接/发送/接收超时：网络抖动，最值得重试；
  /// - `connection` —— 连不上（DNS / 路由 / 校园网未连）：重试一次成本很低；
  /// - `bad_response` —— 收到了 5xx 等异常响应（NCST 插件把 `status >= 500`
  ///   归到这一类）：服务端临时故障，可重试。
  ///
  /// **不含** `bad_certificate`（配置问题，重试无用）与 `cancelled`
  /// （用户主动取消）。`unknown` 也不在其中——原因不明时不做无谓重试。
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

  /// 取最后一个 HTTP 错误标识（与 `ctx.lastHttpError` 的语义保持一致）。
  static String _lastHttpError(List<String> httpErrors) =>
      httpErrors.isEmpty ? '' : httpErrors.last.toLowerCase();

  /// 文案启发式：判断插件这句 error 是否属于"凭证问题"。
  ///
  /// 为什么要靠文案：`fetchCourses` 在 Cookie 为空时**根本不发请求**，
  /// 所以宿主侧没有任何 HTTP 错误可依据（CONTEXT 3.6 / NCST 插件第 33 行）。
  /// 这类判断只影响**提示文案与是否重试**，不影响数据正确性，因此
  /// 用保守的关键字匹配即可。匹配不到就归为 protocolError（同样不重试）。
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
      debugPrint('[CourseSyncService] 解析插件返回值失败：$e');
      return null;
    }
  }

  /// 把任意 `Map` 转成 `Map<String, Object?>`（键统一 toString）。
  static Map<String, Object?> _asStringKeyedMap(Map<dynamic, dynamic> raw) {
    final Map<String, Object?> result = <String, Object?>{};
    raw.forEach((dynamic key, dynamic value) {
      if (key != null) result[key.toString()] = value;
    });
    return result;
  }

  /// 取字符串字段，非字符串时返回空串。
  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  /// 取整数字段，非法时返回 0。
  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  /// 取浮点字段，非法时返回 `null`（用于区分"没提供"与"0 学分"）。
  static double? _asDoubleOrNull(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// 把任意值转成字符串列表（忽略非标量项）。
  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .where((Object? e) => e != null)
        .map((Object? e) => '$e')
        .toList(growable: false);
  }
}

/// 一次执行结果的归类中间态。
class _FetchStatus {
  const _FetchStatus._({
    required this.outcome,
    this.reason = '',
    this.payload,
    this.warnings = const <String>[],
  });

  /// 成功：`payload` 为插件返回的完整对象。
  factory _FetchStatus.ok(
    Map<String, Object?> payload, {
    List<String> warnings = const <String>[],
  }) =>
      _FetchStatus._(
        outcome: SyncOutcome.success,
        payload: payload,
        warnings: warnings,
      );

  /// 失败：`reason` 为面向用户的文案。
  factory _FetchStatus.fail(
    SyncOutcome outcome,
    String reason, {
    List<String> warnings = const <String>[],
  }) =>
      _FetchStatus._(outcome: outcome, reason: reason, warnings: warnings);

  final SyncOutcome outcome;
  final String reason;

  /// 仅在 [outcome] 为 `success` 时非空。
  final Map<String, Object?>? payload;
  final List<String> warnings;
}

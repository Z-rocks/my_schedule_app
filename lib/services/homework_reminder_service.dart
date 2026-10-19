// 作业提醒服务：设置读写 + 排期计算 + 下发原生 + 生命周期刷新。
//
// 分层（与 `PluginEntitySyncService` 一致）：
//   本服务   —— 只做"读设置 → 算排期 → 下发原生"，不认识 UI
//   原生侧   —— 只做"按时叫醒 → 校验 → 发通知"，不认识作业/插件
//
// 刷新时机（`HomeworkReminderController`）：
//   - 作业列表变化（同步、勾完成、改截止、隐藏）
//   - 插件启用 / 卸载变化
//   - App 回到前台（系统可能清过闹钟，且用户可能刚在别处提交了作业）
//   - 设置页保存后主动调用
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/widgets.dart';

import '../models/homework.dart';
import '../models/homework_reminder_plan.dart';
import '../models/homework_reminder_settings.dart';
import '../models/plugin_course_ref.dart';
import '../models/plugin_meta.dart';
import '../providers/homework_provider.dart';
import '../providers/plugin_provider.dart';
import 'reminder_bridge.dart';
import 'storage_service.dart';

/// 设置存 `settings` Box 的键。
const String kHomeworkReminderSettingsKey = 'homework_reminder_settings';

/// 课程 ref 缓存键前缀（完整键 `homework_reminder_courses:<pluginId>`）。
///
/// 为什么要缓存：后台校验要调 `fetchHomeworks`，而入参是"上次同步勾选的课程
/// ref"。用户不会天天去同步页勾课程，所以必须把上一次的入参留下来，
/// 否则每次提醒都得先多拉一次课程列表（学习通有风控，能省则省）。
const String kHomeworkReminderRefsKeyPrefix = 'homework_reminder_courses:';

/// 作业提醒服务（纯静态）。
class HomeworkReminderService {
  HomeworkReminderService._();

  /// 读设置；坏数据回落默认值。
  static HomeworkReminderSettings loadSettings() {
    try {
      return HomeworkReminderSettings.decode(
        StorageService.settingsBox.get(kHomeworkReminderSettingsKey),
      );
    } catch (error) {
      debugPrint('[HomeworkReminder] 读设置失败（用默认值）：$error');
      return const HomeworkReminderSettings();
    }
  }

  /// 存设置并立刻按新设置重排。
  ///
  /// 返回重排后的提醒条数（0 = 没有可排的，UI 可据此提示"暂无即将截止的作业"）。
  static Future<int> saveSettings(
    HomeworkReminderSettings settings, {
    required Iterable<Homework> homeworks,
    required Iterable<String> pluginIds,
  }) async {
    final HomeworkReminderSettings normalized = settings.copyWith();
    try {
      await StorageService.settingsBox
          .put(kHomeworkReminderSettingsKey, normalized.encode());
    } catch (error, stackTrace) {
      debugPrint('[HomeworkReminder] 保存设置失败：$error');
      debugPrint('$stackTrace');
    }
    return refresh(
      homeworks: homeworks,
      pluginIds: pluginIds,
      settings: normalized,
    );
  }

  /// 读某插件上次同步用的课程 ref；没有 / 坏数据返回空列表。
  static List<PluginCourseRef> loadCourseRefs(String pluginId) {
    if (pluginId.isEmpty) return const <PluginCourseRef>[];
    try {
      final String? raw =
          StorageService.settingsBox.get('$kHomeworkReminderRefsKeyPrefix$pluginId');
      return _decodeRefs(raw);
    } catch (error) {
      debugPrint('[HomeworkReminder] 读 $pluginId 的课程缓存失败：$error');
      return const <PluginCourseRef>[];
    }
  }

  /// 记下某插件本次同步用的课程 ref（作业同步成功后调用）。
  ///
  /// 空列表视为"清空"——用户如果把课程全取消勾选了，就别留旧入参。
  static Future<void> saveCourseRefs(
    String pluginId,
    List<PluginCourseRef> refs,
  ) async {
    if (pluginId.isEmpty) return;
    final String key = '$kHomeworkReminderRefsKeyPrefix$pluginId';
    try {
      if (refs.isEmpty) {
        await StorageService.settingsBox.delete(key);
        return;
      }
      await StorageService.settingsBox.put(
        key,
        '{"courses":${_encodeRefs(refs)}}',
      );
    } catch (error) {
      debugPrint('[HomeworkReminder] 保存 $pluginId 的课程缓存失败：$error');
    }
  }

  /// 按当前作业 + 设置重算排期并下发原生。返回排期条数。
  ///
  /// 关闭状态会**清掉原生全部闹钟**，避免"关了还在响"。
  static Future<int> refresh({
    required Iterable<Homework> homeworks,
    required Iterable<String> pluginIds,
    HomeworkReminderSettings? settings,
    DateTime? now,
  }) async {
    final HomeworkReminderSettings effective = settings ?? loadSettings();
    if (!effective.isEffective) {
      await ReminderBridge.cancelAll();
      return 0;
    }

    final Map<String, List<PluginCourseRef>> refsByPlugin =
        <String, List<PluginCourseRef>>{};
    for (final String pluginId in pluginIds) {
      refsByPlugin[pluginId] = loadCourseRefs(pluginId);
    }

    final List<HomeworkReminderItem> items = buildHomeworkReminderPlan(
      homeworks: homeworks,
      settings: effective,
      now: now ?? DateTime.now(),
      refsByPlugin: refsByPlugin,
    );

    final bool ok = await ReminderBridge.syncPlan(
      HomeworkReminderPlan(items).encode(),
    );
    if (!ok) {
      debugPrint('[HomeworkReminder] 排期下发原生失败（${items.length} 条）');
    }
    return items.length;
  }

  /// 构造一条"立即触发"的排期，供设置页的「立即测试完整链路」使用。
  ///
  /// 挑最近截止的未完成作业，把 `fireAt` 设为当前时刻；其余字段与真实排期
  /// **完全一致**（含课程 ref），所以点一次就能真实走通
  /// 「起引擎 → 加载插件 → 调 API 查状态 → 决定发不发通知」整条链路。
  /// 没有可测作业时返回 null。
  static HomeworkReminderItem? buildProbeItem({
    required Iterable<Homework> homeworks,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    Homework? best;
    for (final Homework hw in homeworks) {
      if (hw.isCompleted || hw.isHidden) continue;
      final DateTime? due = hw.displayDeadline;
      if (due == null || !due.isAfter(at)) continue;
      if (best == null ||
          due.isBefore(best.displayDeadline ?? DateTime(9999))) {
        best = hw;
      }
    }
    if (best == null) return null;
    final DateTime deadline = best.displayDeadline!;
    final List<PluginCourseRef> refs = loadCourseRefs(best.sourcePluginId);
    return HomeworkReminderItem(
      homeworkId: best.id,
      pluginId: best.sourcePluginId,
      title: best.displayTitle,
      courseName: best.courseName,
      deadline: deadline,
      fireAt: at,
      offsetMinutes: deadline.difference(at).inMinutes,
      slot: 1,
      totalSlots: 1,
      courseId: best.courseId,
      courseRef: matchCourseRefForCheck(
        courseId: best.courseId,
        pluginId: best.sourcePluginId,
        refs: refs,
      )?.toJson(),
      notifyWhenCheckFails: loadSettings().notifyWhenCheckFails,
    );
  }

  /// 把后台校验入口的回调句柄登记给原生（App 启动时调用一次）。
  ///
  /// [entrypoint] 必须是 **`main.dart` 里的 `homeworkNotificationCheckMain`**：
  /// AOT 只按函数名在根库查找，换成别的库里的函数 release 会解析失败。
  ///
  /// 句柄缺失（例如代码被 tree-shake）时只记日志：原生会退化为
  /// "到点不校验、直接提醒"，功能仍然可用。
  static Future<void> registerBackgroundCheckHandle(Function entrypoint) async {
    if (!ReminderBridge.isSupported) return;
    try {
      final CallbackHandle? handle =
          PluginUtilities.getCallbackHandle(entrypoint);
      if (handle == null) {
        debugPrint('[HomeworkReminder] 拿不到后台校验回调句柄，'
            '原生将跳过状态校验');
        return;
      }
      final bool ok = await ReminderBridge.registerCheckHandle(
        handle.toRawHandle(),
      );
      debugPrint('[HomeworkReminder] 登记后台校验句柄：${ok ? '成功' : '失败'}');
    } catch (error) {
      debugPrint('[HomeworkReminder] 登记后台校验句柄异常：$error');
    }
  }

  /// 解析缓存的 ref 列表：存的是 `{"courses":[...]}`。
  static List<PluginCourseRef> _decodeRefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <PluginCourseRef>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <PluginCourseRef>[];
      return parseCourseRefs(decoded['courses']);
    } catch (error) {
      debugPrint('[HomeworkReminder] 课程缓存解析失败：$error');
      return const <PluginCourseRef>[];
    }
  }

  static String _encodeRefs(List<PluginCourseRef> refs) {
    // 直接拼 JSON 数组：ref.raw 本身就是可序列化的 Map，
    // 交给 jsonEncode 处理（避免手写转义）。
    return jsonEncode(refs.map((PluginCourseRef r) => r.toJson()).toList());
  }
}

/// 生命周期编排：数据变化 / 回前台时重排提醒。
///
/// 与 `WidgetRefreshController` 同一套路（防抖 + 观察者），
/// 差别是它**不需要持有引用**给谁用，纯副作用。
class HomeworkReminderController with WidgetsBindingObserver {
  HomeworkReminderController({
    required this.homeworkProvider,
    required this.pluginProvider,
    this.debounce = const Duration(milliseconds: 900),
  });

  final HomeworkProvider homeworkProvider;
  final PluginProvider pluginProvider;
  final Duration debounce;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;

  /// 最近一次排期条数（调试 / 设置页可展示）。
  int lastPlanCount = 0;

  /// 开始监听。幂等。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    homeworkProvider.addListener(_scheduleRefresh);
    pluginProvider.addListener(_scheduleRefresh);
    WidgetsBinding.instance.addObserver(this);
    // 启动时先排一次：覆盖"上次退出后作业/设置变化"与"系统重启清空闹钟"。
    unawaited(_refreshNow());
  }

  /// 立刻重排（设置页保存后调用，不等防抖）。
  Future<void> refreshNow() => _refreshNow();

  void _scheduleRefresh() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_refreshNow()));
  }

  Future<void> _refreshNow() async {
    if (_disposed) return;
    try {
      lastPlanCount = await HomeworkReminderService.refresh(
        homeworks: homeworkProvider.homeworks,
        pluginIds: pluginProvider.plugins.map((PluginMeta p) => p.id),
      );
    } catch (error) {
      debugPrint('[HomeworkReminder] 重排提醒失败：$error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回前台必须重排：① 系统/厂商可能清过闹钟；② 用户可能刚在网页端
      // 提交了作业，本次重排会按最新状态（含刚勾的完成）剔掉不该响的提醒。
      unawaited(_refreshNow());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    homeworkProvider.removeListener(_scheduleRefresh);
    pluginProvider.removeListener(_scheduleRefresh);
    WidgetsBinding.instance.removeObserver(this);
  }
}

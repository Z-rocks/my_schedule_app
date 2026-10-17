// 小组件数据桥（Phase W1）：Dart → Kotlin 的 MethodChannel 封装 + 刷新编排。
//
// 三条通道（详见 docs/widget_task_breakdown.md P2）：
// - `com.zys.myschedule/widget`：Dart → Kotlin。
//   `writeSnapshot(String json)` 把快照交给 Kotlin 落盘；
//   `refresh()` 让 Kotlin 触发所有已添加的小组件重读重渲染。
// - `com.zys.myschedule/nav`：Kotlin → Dart。
//   用户点小组件 → PendingIntent 拉起 MainActivity（带 `widget_target` extra）
//   → Kotlin 经此通道把目标递给 Dart，[WidgetNav.pendingTarget] 被置上，
//   `HomePage` 监听到就切 tab。
//
// **纪律：小组件是附属功能**——通道失败、快照生成失败只记日志，
// 绝不影响 App 主流程（见 [WidgetRefreshController]，所有调用点包 try/catch）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/course_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/homework_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/semester_provider.dart';
import '../providers/theme_provider.dart';
import '../services/section_time_service.dart';
import '../services/widget_snapshot_service.dart';

/// Dart → Kotlin：写快照 + 触发小组件刷新。
const MethodChannel widgetChannel = MethodChannel('com.zys.myschedule/widget');

/// Kotlin → Dart：小组件点击后的页面目标。
const MethodChannel widgetNavChannel = MethodChannel('com.zys.myschedule/nav');

/// 小组件点击 → App 内目标页。
///
/// 与 Kotlin 侧 `WidgetTargets` 常量一一对应，改一边必须同步另一边。
enum WidgetTarget {
  /// 课表页（今天 / 本周卡片）。
  home,

  /// 作业页。
  homework,

  /// 考试页。
  exam,
}

/// 四张卡片的种类（与 Kotlin `WidgetPinRequest.PROVIDERS` 的 key 对应，
/// 改一边必须同步另一边）。
enum WidgetKind {
  /// 下一节课（2×2，原「今天课表」）。
  today,

  /// 今日课程列表（4×3，原「本周课表」）。
  week,

  /// 待交作业。
  homework,

  /// 近期考试。
  exam,
}

/// 应用内请求把某张卡片加到桌面。
///
/// 只走系统原生 pin（`AppWidgetManager.requestPinAppWidget`，Android 8.0+）：
/// 桌面自己弹"是否添加"的确认框，确认后卡片直接落桌面，**不依赖任何厂商的
/// 小部件中心目录**。
///
/// ⚠️ 2026-10-17 根因修复（见 docs/widget_task_breakdown.md 6.3）：
/// 曾经为了"进小米小部件中心"在 manifest 里声明了 `miuiWidget`，
/// 结果把系统 pin 改道去了小米云端目录的详情页（对未上架应用永远是空页面），
/// 表现就是"点了没反应、桌面找不到卡片"。那次声明已全部移除。
///
/// 返回 `true` 只代表**系统接单**（桌面会弹确认框）；真正加没加进桌面，
/// 看 [WidgetPinEvents] 的回调或 [isWidgetAdded]。
/// 返回 `false` = 当前桌面不支持 / 调用失败，调用方应回退到手动引导文案。
/// 通道异常一律吞掉只记日志——小组件是附属功能，不影响 App 主流程。
Future<bool> requestPinWidget(WidgetKind kind) async {
  try {
    final bool? ok = await widgetChannel.invokeMethod<bool>(
      'requestPinWidget',
      <String, dynamic>{'kind': kind.name},
    );
    return ok ?? false;
  } catch (error) {
    debugPrint('[Widget] requestPinWidget(${kind.name}) 失败（忽略）: $error');
    return false;
  }
}

/// 当前桌面是否支持"应用请求固定小部件"。
Future<bool> isPinWidgetSupported() async {
  try {
    final bool? ok =
        await widgetChannel.invokeMethod<bool>('isPinWidgetSupported');
    return ok ?? false;
  } catch (error) {
    debugPrint('[Widget] isPinWidgetSupported 失败（忽略）: $error');
    return false;
  }
}

/// 桌面上是否已经加了某类卡片（至少 1 张）。
///
/// 这是"真的加进去了"的唯一可靠来源：`getAppWidgetIds` 非空才算数，
/// pin 的返回值与回调查询都只代表"系统接单"。
Future<bool> isWidgetAdded(WidgetKind kind) async {
  try {
    final bool? added = await widgetChannel.invokeMethod<bool>(
      'isWidgetAdded',
      <String, dynamic>{'kind': kind.name},
    );
    return added ?? false;
  } catch (error) {
    debugPrint('[Widget] isWidgetAdded(${kind.name}) 失败（忽略）: $error');
    return false;
  }
}

/// 一次"添加到桌面"的结果。
class WidgetPinEvent {
  const WidgetPinEvent({
    required this.kind,
    required this.accepted,
    required this.appWidgetId,
  });

  /// 哪张卡片。
  final WidgetKind kind;

  /// 桌面是否真的建了卡片实例（false = 用户取消 / 桌面没接）。
  final bool accepted;

  /// 系统分配的 AppWidget id，没建成时为 -1。
  final int appWidgetId;
}

/// pin 结果广播：Kotlin `WidgetPinResultReceiver` → 这里。
///
/// `requestPinAppWidget` 的 successCallback 只在**卡片真的进了工作区**时发出，
/// 所以它能把"已添加"和"用户取消"分开——返回 true 做不到这件事。
class WidgetPinEvents {
  WidgetPinEvents._();

  static final StreamController<WidgetPinEvent> _controller =
      StreamController<WidgetPinEvent>.broadcast();

  static bool _hooked = false;

  /// 结果流（广播型，无订阅者时丢弃，不影响 App）。
  static Stream<WidgetPinEvent> get stream => _controller.stream;

  /// 挂上 Kotlin 回调（幂等）。引导页 initState 里调一次即可。
  static void hook() {
    if (_hooked) return;
    _hooked = true;
    widgetChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onPinResult') return null;
      final Object? rawArgs = call.arguments;
      if (rawArgs is! Map) return null;
      final Object? kindName = rawArgs['kind'];
      WidgetKind? kind;
      for (final WidgetKind candidate in WidgetKind.values) {
        if (candidate.name == kindName) {
          kind = candidate;
          break;
        }
      }
      if (kind == null) return null;
      final Object? id = rawArgs['appWidgetId'];
      _controller.add(
        WidgetPinEvent(
          kind: kind,
          accepted: rawArgs['accepted'] == true,
          appWidgetId: id is num ? id.toInt() : -1,
        ),
      );
      return null;
    });
  }
}

/// 小组件点击跳转的中转站。
///
/// Kotlin 把目标经 [widgetNavChannel] 发来；HomePage 监听
/// [pendingTarget] 并据此切 tab（模块被用户关闭时找不到对应 tab，
/// 就停在课表页，不报错）。
class WidgetNav {
  WidgetNav._();

  /// 待处理的目标；非 null 时 HomePage 应该消费它并置回 null。
  static final ValueNotifier<WidgetTarget?> pendingTarget =
      ValueNotifier<WidgetTarget?>(null);

  static bool _initialized = false;

  /// 注册通道。在 `main()` 里 providers 装配完成后调用一次。
  ///
  /// 同时处理冷启动竞态：widget 拉起 App 时 Dart 引擎还没起来，
  /// MainActivity 会把 extra 暂存，等这里主动来取（`takeInitialTarget`）。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    widgetNavChannel.setMethodCallHandler(
      (MethodCall call) async => _onNavCall(call),
    );
    try {
      final String? initial =
          await widgetNavChannel.invokeMethod<String>('takeInitialTarget');
      if (initial != null) _applyTarget(initial);
    } catch (error) {
      debugPrint('[WidgetNav] 取初始目标失败（忽略）: $error');
    }
  }

  static Future<dynamic> _onNavCall(MethodCall call) async {
    switch (call.method) {
      case 'onTarget':
        _applyTarget(call.arguments as String?);
        return null;
      default:
        return null;
    }
  }

  static void _applyTarget(String? value) {
    switch (value) {
      case 'home':
      case 'homework':
      case 'exam':
        pendingTarget.value = WidgetTarget.values
            .firstWhere((WidgetTarget t) => t.name == value);
        break;
      default:
        break; // 未知目标忽略，停在默认页
    }
  }
}

/// 刷新编排：监听各 Provider → 生成快照 → 写 Kotlin → 触发刷新。
///
/// - **防抖**：Provider 常常连续多次通知（一次同步写几十条数据），
///   合并成一次刷新，避免 MethodChannel 被打爆。
/// - **Sources of failure 一律兜底**：任何异常只 debugPrint。
class WidgetRefreshController with WidgetsBindingObserver {
  WidgetRefreshController({
    required this._courseProvider,
    required this._homeworkProvider,
    required this._examProvider,
    required this._semesterProvider,
    required this._pluginProvider,
    required this._themeProvider,
  });

  final CourseProvider _courseProvider;
  final HomeworkProvider _homeworkProvider;
  final ExamProvider _examProvider;
  final SemesterProvider _semesterProvider;
  final PluginProvider _pluginProvider;
  final ThemeProvider _themeProvider;

  /// 防抖窗口：Provider 通知停下来的 0.6s 后才真正生成一次快照。
  static const Duration _debounce = Duration(milliseconds: 600);

  Timer? _timer;
  bool _started = false;

  /// 开始监听。重复调用安全（幂等）。
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _courseProvider.addListener(_scheduleRefresh);
    _homeworkProvider.addListener(_scheduleRefresh);
    _examProvider.addListener(_scheduleRefresh);
    _semesterProvider.addListener(_scheduleRefresh);
    _pluginProvider.addListener(_scheduleRefresh);
    _themeProvider.addListener(_scheduleRefresh);
    // App 启动后立刻推一次（冷启动可能跨天，上次快照可能已过期）。
    _scheduleRefresh();
  }

  /// 停止监听（测试 / 销毁用）。
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _courseProvider.removeListener(_scheduleRefresh);
    _homeworkProvider.removeListener(_scheduleRefresh);
    _examProvider.removeListener(_scheduleRefresh);
    _semesterProvider.removeListener(_scheduleRefresh);
    _pluginProvider.removeListener(_scheduleRefresh);
    _themeProvider.removeListener(_scheduleRefresh);
    _timer?.cancel();
    _timer = null;
  }

  /// 回到前台时刷新一次：可能跨天、跨周次、后台被系统杀掉過。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(refreshNow());
    });
  }

  /// 立即生成并推送一次快照（公开给测试与手动触发用）。
  ///
  /// 失败只记日志：Kotlin 通道在纯 Flutter 环境（无小组件 / 测试）里
  /// 本就不存在，那是预期状态而不是错误。
  Future<void> refreshNow() async {
    try {
      final SectionTimes? sectionTimes =
          SectionTimeService.fromPlugins(_pluginProvider.plugins);
      final List<int> palette = _themeProvider.currentTheme.courseCardColors
          .map((Color c) => c.toARGB32())
          .toList(growable: false);

      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: _courseProvider.visibleCourses,
        semester: _semesterProvider.config,
        homeworks: _homeworkProvider.displayHomeworks,
        exams: _examProvider.displayExams,
        sectionTimes: sectionTimes,
        palette: palette,
      );

      final String json = jsonEncode(snapshot.toJson());
      await widgetChannel.invokeMethod<void>(
        'writeSnapshot',
        <String, dynamic>{'json': json},
      );
      await widgetChannel.invokeMethod<void>('refresh');
    } catch (error, stackTrace) {
      debugPrint('[Widget] 快照刷新失败（忽略，不影响主流程）: $error');
      debugPrint('$stackTrace');
    }
  }
}

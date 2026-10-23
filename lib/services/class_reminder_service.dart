// 上课提醒服务：设置读写 + 排期下发 + 生命周期重排。
//
// 三层职责刻意分开：
// - `class_reminder_plan.dart`：纯计算（可单测，不碰存储与平台）；
// - 本文件 `ClassReminderService`：读设置、算排期、下发到原生；
// - 本文件 `ClassReminderController`：监听数据变化 / 回前台，触发重排。
//
// ## 为什么要在这么多时机重排
//
// 排期只覆盖未来 7 天，靠"重排"把窗口一直往前推。触发点有四个：
// 1. App 启动（`start()` 里先排一次）——覆盖"上次退出后过了好几天"；
// 2. 课程数据变化（同步 / 编辑 / 隐藏）——课变了排期必须跟着变；
// 3. 学期配置变化——换了学期，周次全部重算；
// 4. 回到前台——系统或厂商 ROM 可能清过闹钟，重排一次最省心。
//
// 少任何一个都会出现"某类场景下提醒静默失效"，而这类失效用户很难察觉
// （只会觉得"今天怎么没提醒"），所以宁可多排几次。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../models/class_reminder_settings.dart';
import '../models/course.dart';
import '../models/semester_config.dart';
import '../providers/course_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/semester_provider.dart';
import 'app_log.dart';
import 'class_reminder_plan.dart';
import 'reminder_bridge.dart';
import 'section_time_service.dart';
import 'storage_service.dart';

/// 上课提醒服务（纯静态）。
class ClassReminderService {
  ClassReminderService._();

  /// 读设置。未配置 / 坏数据一律返回默认（关闭）。
  static ClassReminderSettings loadSettings() {
    try {
      return ClassReminderSettings.tryDecode(
        StorageService.settingsBox.get(kClassReminderSettingsKey),
      );
    } catch (error) {
      debugPrint('[ClassReminder] 读设置失败（按默认处理）：$error');
      return const ClassReminderSettings();
    }
  }

  /// 存设置。落盘失败只记日志，不回滚内存（与 SemesterProvider 一致）。
  static Future<void> saveSettings(ClassReminderSettings settings) async {
    try {
      await StorageService.settingsBox
          .put(kClassReminderSettingsKey, settings.encode());
    } catch (error, stack) {
      debugPrint('[ClassReminder] 存设置失败：$error');
      AppLog.e('class_reminder', '保存上课提醒设置失败',
          error: error, stack: stack);
    }
  }

  /// 重算并下发排期，返回本次排上的条数。
  ///
  /// 关闭 / 没配学期 / 没有课 都会**清空**已有排期再返回 0——
  /// 否则用户关掉开关后，之前排好的闹钟还会继续响。
  static Future<int> refresh({
    required List<Course> courses,
    required SemesterConfig? config,
    required Map<int, String> sectionTimes,
    DateTime? now,
  }) async {
    final ClassReminderSettings settings = loadSettings();
    if (!settings.isEffective || config == null || courses.isEmpty) {
      await ReminderBridge.cancelClassPlan();
      return 0;
    }

    try {
      final List<ClassReminderItem> items = buildClassReminderPlan(
        courses: courses,
        config: config,
        sectionTimes: sectionTimes,
        settings: settings,
        now: now ?? DateTime.now(),
      );
      final String plan = jsonEncode(<String, dynamic>{
        'version': kClassReminderPlanVersion,
        'items': items.map((ClassReminderItem i) => i.toJson()).toList(),
      });
      await ReminderBridge.syncClassPlan(plan);
      return items.length;
    } catch (error, stack) {
      debugPrint('[ClassReminder] 下发排期失败：$error');
      AppLog.e('class_reminder', '下发上课提醒排期失败',
          error: error, stack: stack);
      return 0;
    }
  }

  /// 取消全部（关闭开关时调用）。
  static Future<void> cancel() => ReminderBridge.cancelClassPlan();
}

/// 生命周期编排：数据变化 / 回前台时重排上课提醒。
///
/// 与 `HomeworkReminderController` 同一套路（防抖 + 观察者），
/// 差别是它还要盯 `SemesterProvider`（换学期等于整套周次重算）。
class ClassReminderController with WidgetsBindingObserver {
  ClassReminderController({
    required this.courseProvider,
    required this.semesterProvider,
    required this.pluginProvider,
    this.debounce = const Duration(milliseconds: 900),
  });

  final CourseProvider courseProvider;
  final SemesterProvider semesterProvider;
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
    courseProvider.addListener(_scheduleRefresh);
    semesterProvider.addListener(_scheduleRefresh);
    pluginProvider.addListener(_scheduleRefresh);
    WidgetsBinding.instance.addObserver(this);
    // 启动先排一次：覆盖"上次退出后过了好几天"与"系统重启清空闹钟"。
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
      final int count = await ClassReminderService.refresh(
        courses: courseProvider.visibleCourses,
        config: semesterProvider.config,
        sectionTimes: _resolveSectionTimes(),
      );
      // 只在条数变化时记日志：回前台会频繁重排，每次都记会把日志淹掉。
      if (count != lastPlanCount) {
        AppLog.i('class_reminder', '上课提醒排期更新', <String, Object?>{
          'count': count,
          'previous': lastPlanCount,
        });
      }
      lastPlanCount = count;
    } catch (error) {
      debugPrint('[ClassReminder] 重排失败：$error');
    }
  }

  /// 作息优先用插件同步下来的真实值，没有就回落到内置默认表。
  ///
  /// 不能因为"没装插件"就不排：手动添加课程的用户同样需要上课提醒。
  Map<int, String> _resolveSectionTimes() {
    final SectionTimes? times =
        SectionTimeService.fromPlugins(pluginProvider.plugins);
    if (times == null || times.isEmpty) return kDefaultSectionTimes;
    return times.times;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNow());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    courseProvider.removeListener(_scheduleRefresh);
    semesterProvider.removeListener(_scheduleRefresh);
    pluginProvider.removeListener(_scheduleRefresh);
    WidgetsBinding.instance.removeObserver(this);
  }
}

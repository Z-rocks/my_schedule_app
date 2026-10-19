// 后台作业状态校验（headless isolate 入口）。
//
// ## 为什么需要它
//
// 通知到点时要先问一句"这份作业是不是已经交了"——用户经常在网页端交了，
// 却忘了回 App 里勾"已完成"。若不校验，就会对已完成的作业反复催。
// 但通知触发时 App 往往在后台甚至进程已死，主 isolate 里的
// `HomeworkProvider` / 插件运行时都不在，只能在闹钟触发时**临时起一个
// Flutter 引擎**跑本文件的入口函数。
//
// ## 三条铁律（改动前务必看）
//
// 1. **不要碰 Hive**。主 App 若在运行，它已持有 Box 锁；本 isolate 再开同一个
//    Box 会直接抛错（Hive 不支持多 isolate 并发）。所以这里：
//    - 作业信息、课程 ref 全部由原生从排期里带进来（[payload]）；
//    - `PluginContext` 内部的 storage 读取失败会被它自己 catch 成空表，安全。
// 2. **不要初始化 StorageService / 任何 Provider**。本 isolate 只做一件事：
//    加载一个插件 → 调一次 `fetchHomeworks` → 回传状态。
// 3. **任何异常都必须变成 `unknown`**。原生侧收到 unknown 时按用户设置决定
//    "仍然提醒"或"跳过"，绝不能因为校验崩了就不提醒（那是更坏的失败）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/homework_reminder_plan.dart';
import '../models/plugin_course_ref.dart';
import '../runtime/js_sandbox.dart';
import '../runtime/plugin_handle.dart';
import '../runtime/plugin_runtime.dart';
import 'plugin_storage_service.dart';

/// 与 Kotlin `ReminderContract.CHANNEL_CHECK` 必须一致。
const String kHomeworkCheckChannelName = 'com.zys.myschedule/reminder_check';

/// 校验状态。
enum HomeworkCheckStatus {
  /// 插件明确显示已完成 → 不打扰用户。
  completed,

  /// 仍待完成 → 正常提醒。
  pending,

  /// 校验不出来（未登录 / 断网 / 插件不可用 / 用户自建作业）。
  unknown,
}

/// 一次校验的结果。
class HomeworkCheckResult {
  const HomeworkCheckResult(this.status, [this.reason = '']);

  final HomeworkCheckStatus status;
  final String reason;

  bool get isCompleted => status == HomeworkCheckStatus.completed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.name,
        'reason': reason,
      };
}

/// 后台校验的**实际实现**（由 `main.dart` 里的入口函数转发进来）。
///
/// ## ⚠️ 为什么真正的入口不在这里
///
/// AOT（release）下 `DartEntrypoint` 只按函数名在**根库**（`main.dart`）里查找，
/// 完全忽略 `callbackLibraryPath`。函数放在本文件里会出现：
/// debug（JIT）跑得好好的，release 一触发就是
/// `Could not resolve main entrypoint function` → 引擎起不来 → 校验永远失败。
/// 所以 `homeworkNotificationCheckMain` 必须声明在 `main.dart`，
/// 这里只保留实现。
///
/// 生命周期：原生起引擎 → 执行入口函数 → 注册通道 handler 并通知 `ready`
/// → 原生 `run` 下传作业信息 → 校验 → 回传 `result` → 原生销毁引擎。
void runHomeworkCheckEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(kHomeworkCheckChannelName);

  channel.setMethodCallHandler((MethodCall call) async {
    if (call.method != 'run') return null;
    final Map<String, dynamic> payload =
        HomeworkStatusChecker._asStringKeyed(call.arguments);
    HomeworkCheckResult result;
    try {
      result = await HomeworkStatusChecker.check(payload);
    } catch (error, stackTrace) {
      debugPrint('[HomeworkCheck] 校验异常：$error');
      debugPrint('$stackTrace');
      result = HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '校验异常：$error',
      );
    }
    try {
      await channel.invokeMethod<void>('result', result.toJson());
    } catch (error) {
      debugPrint('[HomeworkCheck] 回传结果失败：$error');
    }
    return null;
  });

  // 告诉原生"handler 已就绪，可以把作业信息发过来了"。
  channel.invokeMethod<void>('ready').catchError((Object error) {
    debugPrint('[HomeworkCheck] 通知原生 ready 失败：$error');
  });
}

/// 校验实现：只依赖"插件文件 + Cookie"，不依赖任何 Provider / Hive。
class HomeworkStatusChecker {
  HomeworkStatusChecker._();

  /// 单次 `fetchHomeworks` 的超时。
  ///
  /// 原生侧整体等待上限是 30s（见 Kotlin `ReminderContract.CHECK_TIMEOUT_MS`），
  /// 这里 15s：`withContent: false` 时只需"课程主页 → 作业列表"两层请求，
  /// 正常 1~3s 完成；给 15s 是留给校园网 / WebVPN 慢链路。
  static const Duration kFetchTimeout = Duration(seconds: 15);

  /// 拉课程列表的超时（仅在排期里没带 courseRef 时才需要）。
  static const Duration kCourseListTimeout = Duration(seconds: 8);

  /// 执行一次状态校验。
  ///
  /// [payload] 字段（由 Kotlin 从排期项原样转发）：
  /// `homeworkId` / `pluginId` / `courseId` / `courseRef`(可空) / `title`。
  static Future<HomeworkCheckResult> check(Map<String, dynamic> payload) async {
    final String homeworkId = '${payload['homeworkId'] ?? ''}';
    final String pluginId = '${payload['pluginId'] ?? ''}';
    final String courseId = '${payload['courseId'] ?? ''}';
    if (homeworkId.isEmpty) {
      return const HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '缺少作业 ID',
      );
    }
    // 用户自建作业没有远端状态可查，直接按"待完成"提醒。
    if (pluginId.isEmpty || pluginId == 'user') {
      return const HomeworkCheckResult(
        HomeworkCheckStatus.pending,
        '用户自建作业，无需校验',
      );
    }

    final String? pluginPath =
        await PluginStorageService.getPluginJsPath(pluginId);
    if (pluginPath == null) {
      return HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '插件 $pluginId 未安装',
      );
    }

    final PluginRuntime runtime = PluginRuntime();
    try {
      final PluginHandle handle = await runtime.loadPlugin(path: pluginPath);
      if (!handle.isUsable) {
        return HomeworkCheckResult(
          HomeworkCheckStatus.unknown,
          '插件不可用：${handle.reason ?? handle.status.name}',
        );
      }
      if (!handle.entries.contains('fetchHomeworks')) {
        return const HomeworkCheckResult(
          HomeworkCheckStatus.unknown,
          '插件不支持抓取作业',
        );
      }

      // ── 1. 定课程 ref（排期里带了就用，没带就现拉课程列表匹配）──
      PluginCourseRef? ref = _refFromPayload(
        payload['courseRefJson'] ?? payload['courseRef'],
      );
      ref ??= await _resolveRefFromCourseList(
        handle: handle,
        courseId: courseId,
        pluginId: pluginId,
      );
      if (ref == null) {
        return HomeworkCheckResult(
          HomeworkCheckStatus.unknown,
          '找不到该作业所属课程（courseId=$courseId），'
              '请打开 App 同步一次作业',
        );
      }

      // ── 2. 抓这门课的作业，找目标作业的完成状态 ──
      //    withContent: false —— 只要状态，不要正文，少发请求（学习通风控）。
      final JsSandboxResult result = await handle.execute(
        'fetchHomeworks',
        args: <String, dynamic>{
          'courses': <dynamic>[ref.toJson()],
          'withContent': false,
        },
        timeout: kFetchTimeout,
      );

      return interpretFetchResult(result, homeworkId);
    } catch (error) {
      debugPrint('[HomeworkCheck] $pluginId 校验失败：$error');
      return HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '校验失败：$error',
      );
    } finally {
      // 沙箱必须销毁：本 isolate 生命很短，不销毁等于泄漏 QuickJS 上下文。
      await runtime.dispose();
    }
  }

  /// 从排期带过来的 courseRef 还原成插件入参对象。
  ///
  /// 原生侧为了不与 Dart 的对象模型耦合，传的是 JSON 字符串
  /// （`courseRefJson`）；这里也兼容直接传 Map 的情况（便于单测）。
  static PluginCourseRef? _refFromPayload(Object? raw) {
    if (raw is String) {
      if (raw.trim().isEmpty) return null;
      final Object? decoded = _tryDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> map = _asStringKeyed(decoded);
      return map.isEmpty ? null : PluginCourseRef(map);
    }
    if (raw is! Map) return null;
    final Map<String, dynamic> map = _asStringKeyed(raw);
    return map.isEmpty ? null : PluginCourseRef(map);
  }

  /// 排期里没有 courseRef 时，调 `fetchCourseList` 现找一条匹配的。
  ///
  /// 只在"用户上次同步后课程结构变了"时才会走到，属于兜底路径。
  static Future<PluginCourseRef?> _resolveRefFromCourseList({
    required PluginHandle handle,
    required String courseId,
    required String pluginId,
  }) async {
    if (!handle.entries.contains('fetchCourseList')) return null;
    final JsSandboxResult result = await handle.execute(
      'fetchCourseList',
      timeout: kCourseListTimeout,
    );
    if (!result.isSuccess || result.value == null) return null;
    final Object? decoded = _tryDecode(result.value!);
    if (decoded is! Map) return null;
    final List<PluginCourseRef> refs = parseCourseRefs(decoded['courses']);
    return matchCourseRefForCheck(
      courseId: courseId,
      pluginId: pluginId,
      refs: refs,
    );
  }

  /// 解析 `fetchHomeworks` 的返回：定位目标作业，读 `completed`。
  ///
  /// 抽成可测方法（@visibleForTesting）：这是整个功能里**唯一决定
  /// "要不要打扰用户"的判断**，错一次就会漏提醒或误报，必须能单测。
  @visibleForTesting
  static HomeworkCheckResult interpretFetchResult(
    JsSandboxResult result,
    String homeworkId,
  ) {
    if (!result.isSuccess) {
      return HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '抓取作业失败：${result.message ?? result.status.name}',
      );
    }
    final Object? decoded = _tryDecode(result.value ?? '');
    if (decoded is! Map) {
      return const HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '插件返回值不是 JSON 对象',
      );
    }
    final String error = '${decoded['error'] ?? ''}';
    if (error.isNotEmpty) {
      return HomeworkCheckResult(HomeworkCheckStatus.unknown, error);
    }
    final Object? list = decoded['homeworks'];
    if (list is! List) {
      return const HomeworkCheckResult(
        HomeworkCheckStatus.unknown,
        '插件返回值里没有 homeworks 数组',
      );
    }
    for (final Object? item in list) {
      if (item is! Map) continue;
      final Map<String, dynamic> json = _asStringKeyed(item);
      if ('${json['id'] ?? ''}' != homeworkId) continue;
      final bool completed = json['completed'] == true ||
          '${json['completed'] ?? ''}'.toLowerCase() == 'true';
      return HomeworkCheckResult(
        completed ? HomeworkCheckStatus.completed : HomeworkCheckStatus.pending,
        completed ? '远端已是完成状态' : '远端仍未完成',
      );
    }
    // 这门课里找不到该作业：多半是教务系统把它归档 / 删了。
    // 按"待完成"处理（宁可提醒），原因写清楚便于排查。
    return const HomeworkCheckResult(
      HomeworkCheckStatus.pending,
      '远端列表里没找到该作业（可能已归档），按待完成处理',
    );
  }

  static Object? _tryDecode(String raw) {
    if (raw.isEmpty || raw == 'undefined') return null;
    try {
      return jsonDecode(raw);
    } catch (error) {
      debugPrint('[HomeworkCheck] JSON 解析失败：$error');
      return null;
    }
  }

  static Map<String, dynamic> _asStringKeyed(Object? raw) {
    final Map<String, dynamic> result = <String, dynamic>{};
    if (raw is! Map) return result;
    raw.forEach((dynamic key, dynamic value) {
      if (key != null) result['$key'] = value;
    });
    return result;
  }
}

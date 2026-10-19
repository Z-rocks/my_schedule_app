// App 入口：装配 Provider 树（含 PluginProvider → ModuleProvider 的能力联动）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'models/message.dart';
import 'providers/course_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/homework_provider.dart';
import 'providers/message_provider.dart';
import 'providers/module_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/semester_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'services/storage_service.dart';
import 'services/homework_check_entry.dart';
import 'services/homework_reminder_service.dart';
import 'services/widget_bridge.dart';

Future<void> main() async {
  // 必须先初始化绑定，Hive.initFlutter() 依赖平台通道（path_provider）。
  WidgetsFlutterBinding.ensureInitialized();

  // 打开 Hive Box；失败不会抛异常，只记日志，App 仍能以"无数据"状态启动。
  await StorageService.init();

  // 先把持久化状态读进内存，再起 UI——避免首帧闪一下默认值
  // （例如导航栏先显示默认 4 个模块、再跳成用户配置的样子）。
  final CourseProvider courseProvider = CourseProvider();
  await courseProvider.loadFromStorage();

  // 作业与考试（Phase 8）：同样先把持久化状态读进内存，再起 UI——
  // 否则用户切到作业页时会先看到一瞬间的"暂无作业"再跳成真实列表。
  final HomeworkProvider homeworkProvider = HomeworkProvider();
  await homeworkProvider.loadFromStorage();

  final ExamProvider examProvider = ExamProvider();
  await examProvider.loadFromStorage();

  final ModuleProvider moduleProvider = ModuleProvider();
  await moduleProvider.loadFromStorage();

  final SemesterProvider semesterProvider = SemesterProvider();
  await semesterProvider.loadFromStorage();

  final SettingsProvider settingsProvider = SettingsProvider();
  await settingsProvider.loadFromStorage();

  final ThemeProvider themeProvider = ThemeProvider();
  await themeProvider.loadFromStorage();
  // Phase 6：把上次用的皮肤重新套上（皮肤 ID 已由 loadFromStorage 读出）。
  // 找不到对应皮肤时 rootBundle 会返回 null，此时保持默认主题——
  // 不因为"皮肤没了"就让启动失败。
  await themeProvider.restoreStoredSkin();

  // 消息：Phase 7 起从 Hive 载入（之前是纯内存，重启即丢）。
  final MessageProvider messageProvider = MessageProvider();
  await messageProvider.loadFromStorage();

  // 插件：先读列表，再加载所有已启用插件的运行时（失败只降级，不影响启动）。
  // `onNotify` 把插件的 `ctx.notify.schedule(...)` 变成一条**站内消息**——
  // 用回调注入而不是让 PluginProvider 持有 MessageProvider（CONTEXT 4.5：
  // Provider 之间不直接互相引用）。
  final PluginProvider pluginProvider = PluginProvider(
    onNotify: (String pluginId, String title, String body, String triggerAtIso) {
      debugPrint('[Notify] 插件 $pluginId 计划提醒「$title」@$triggerAtIso');
      unawaited(
        messageProvider.addMessagePersisted(
          buildPluginNotifyMessage(
            pluginId: pluginId,
            title: title,
            body: body,
            triggerAtIso: triggerAtIso,
          ),
        ),
      );
    },
  );
  await pluginProvider.loadFromStorage();
  await pluginProvider.loadAllEnabledPlugins();

  // 小组件（Phase W1）：装配快照刷新编排——之后任何课表 / 作业 / 考试 /
  // 学期 / 主题变化都会推一份新快照给 Kotlin 侧小组件。
  // 不持有引用：controller 被各 Provider 的监听闭包与 WidgetsBinding
  // 观察者列表持有，生命周期与 App 进程一致，不会中途被 GC。
  WidgetRefreshController(
    courseProvider: courseProvider,
    homeworkProvider: homeworkProvider,
    examProvider: examProvider,
    semesterProvider: semesterProvider,
    pluginProvider: pluginProvider,
    themeProvider: themeProvider,
  ).start();

  // 作业提醒（Phase 9）：先把后台校验入口的回调句柄交给原生（闹钟触发时
  // 原生靠它起临时引擎跑 `homeworkNotificationCheckMain`），再启动编排器——
  // 之后作业 / 插件 / 回前台变化都会重排提醒。
  await HomeworkReminderService.registerBackgroundCheckHandle(
    homeworkNotificationCheckMain,
  );
  HomeworkReminderController(
    homeworkProvider: homeworkProvider,
    pluginProvider: pluginProvider,
  ).start();

  runApp(buildApp(
    courseProvider: courseProvider,
    homeworkProvider: homeworkProvider,
    examProvider: examProvider,
    moduleProvider: moduleProvider,
    semesterProvider: semesterProvider,
    settingsProvider: settingsProvider,
    themeProvider: themeProvider,
    pluginProvider: pluginProvider,
    messageProvider: messageProvider,
  ));
}

/// 把插件的 `ctx.notify.schedule(...)` 参数变成一条站内消息（**Phase 7**）。
///
/// 放在 `main.dart` 顶层而不是 `MessageProvider` 里：它是"插件调用约定 →
/// 内核消息模型"的**适配**，不属于消息状态管理本身。
///
/// 幂等性说明：插件入口函数会被执行多次，但 `ctx.notify` 的副作用**只在最终轮
/// 提交**（CONTEXT 3.6），所以这里不会收到重复通知。消息 id 用
/// `notify_<pluginId>_<triggerAtIso>` 也是第二道防线——即便重复提交，
/// 同 id 会覆盖而不是新增一条。
Message buildPluginNotifyMessage({
  required String pluginId,
  required String title,
  required String body,
  required String triggerAtIso,
}) {
  final DateTime? triggerAt = DateTime.tryParse(triggerAtIso);
  return Message(
    id: 'notify_${pluginId}_$triggerAtIso',
    type: MessageType.other,
    title: title.isEmpty ? '插件提醒' : title,
    body: triggerAt == null
        ? body
        : '${body.isEmpty ? '' : '$body\n'}计划时间：'
            '${triggerAt.year}/${triggerAt.month}/${triggerAt.day} '
            '${triggerAt.hour.toString().padLeft(2, '0')}:'
            '${triggerAt.minute.toString().padLeft(2, '0')}',
    // createdAt 用"现在"（消息的产生时间），计划时间写在正文里：
    // 列表按产生时间倒序才符合直觉，用计划时间排序会让未来的提醒排到最前。
    createdAt: DateTime.now(),
    sourcePluginId: pluginId,
    extra: <String, dynamic>{'triggerAt': triggerAtIso},
  );
}

/// 构建完整的 App（Provider 树 + 根组件）。
///
/// 抽成函数是为了让 widget 测试能直接 `pumpWidget(buildApp())`，
/// 验证的即是 `main()` 真正使用的这棵 Provider 树，而不是测试里另写一份。
///
/// 各可选参数由 `main()` 传入**已完成存储加载**的实例；
/// 不传时（测试、预览）内部自建空实例，此时不会访问 Hive。
///
/// 生命周期：`CourseProvider` / `HomeworkProvider` / `ExamProvider` /
/// `MessageProvider` / `SemesterProvider` / `SettingsProvider` /
/// `ThemeProvider` / `PluginProvider` 走 `.value`，
/// 实例归调用方所有，不随 Provider 树销毁而 dispose。
/// `ModuleProvider` 由 `ChangeNotifierProxyProvider` 创建（该 Provider 没有
/// `.value` 变体），因此注入的实例会被 Provider 树接管生命周期——
/// 在 App 生命周期内不会销毁，所以实际没有差别；但**不要**把同一个
/// ModuleProvider 实例同时传给两棵 Provider 树（先卸载的那棵会 dispose 它）。
Widget buildApp({
  CourseProvider? courseProvider,
  HomeworkProvider? homeworkProvider,
  ExamProvider? examProvider,
  ModuleProvider? moduleProvider,
  SemesterProvider? semesterProvider,
  SettingsProvider? settingsProvider,
  ThemeProvider? themeProvider,
  PluginProvider? pluginProvider,
  MessageProvider? messageProvider,
}) {
  return MultiProvider(
    // Provider 顺序即依赖顺序：被依赖者必须排在依赖者之前。
    // `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>`
    // 依赖 PluginProvider，所以 PluginProvider 必须先声明。
    providers: [
      // 1. 主题（无依赖）
      if (themeProvider != null)
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider)
      else
        ChangeNotifierProvider<ThemeProvider>(
          create: (BuildContext context) => ThemeProvider(),
        ),
      // 2. 插件（无依赖，但被 ModuleProvider 依赖）
      // Phase 3.3 起可由 main() 传入已加载完插件运行时的实例；不传时自建空实例。
      if (pluginProvider != null)
        ChangeNotifierProvider<PluginProvider>.value(value: pluginProvider)
      else
        ChangeNotifierProvider<PluginProvider>(
          create: (BuildContext context) => PluginProvider(),
        ),
      // 3. 模块（依赖 PluginProvider 的能力集合）
      ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>(
        create: (BuildContext context) => moduleProvider ?? ModuleProvider(),
        update: (
          BuildContext context,
          PluginProvider pluginProvider,
          ModuleProvider? moduleProvider,
        ) {
          // 首次 build 时 moduleProvider 为 null，需要自建；
          // 后续 PluginProvider 通知时会带着已有实例再次进入这里。
          final ModuleProvider provider = moduleProvider ?? ModuleProvider();

          // 把插件声明的能力推给模块层，决定 homework 的可用性。
          //
          // 这里**不会**在 build 阶段触发 notifyListeners：
          // ModuleProvider.updateCapabilities 只在模块可用性真正变化时才通知，
          // 而「能力集合没变」是绝大多数重建的实际情况（包括首次 build）。
          // 即使真的变化（用户刚启用了插件），该通知发生在
          // PluginProvider.notifyListeners 引发的重建过程中，
          // Provider 会把它合并进本次重建，不会形成循环。
          provider.updateCapabilities(pluginProvider.allCapabilities);
          return provider;
        },
      ),
      // 4. 课程（无依赖）
      // 传入实例时用 .value：实例归调用方所有，不随 Provider 树销毁而 dispose。
      if (courseProvider != null)
        ChangeNotifierProvider<CourseProvider>.value(value: courseProvider)
      else
        ChangeNotifierProvider<CourseProvider>(
          create: (BuildContext context) => CourseProvider(),
        ),
      // 5. 作业（无依赖，Phase 8）
      // 作业与考试页各自 watch 自己的 Provider；两者都实现 `EntityStore`，
      // 由 `PluginEntitySyncService` 落盘（服务层不认识 Provider，只认接口）。
      if (homeworkProvider != null)
        ChangeNotifierProvider<HomeworkProvider>.value(value: homeworkProvider)
      else
        ChangeNotifierProvider<HomeworkProvider>(
          create: (BuildContext context) => HomeworkProvider(),
        ),
      // 6. 考试（无依赖，Phase 8）
      if (examProvider != null)
        ChangeNotifierProvider<ExamProvider>.value(value: examProvider)
      else
        ChangeNotifierProvider<ExamProvider>(
          create: (BuildContext context) => ExamProvider(),
        ),
      // 7. 消息（无依赖）
      // Phase 7 起可由 main() 传入已从 Hive 载入的实例。
      if (messageProvider != null)
        ChangeNotifierProvider<MessageProvider>.value(value: messageProvider)
      else
        ChangeNotifierProvider<MessageProvider>(
          create: (BuildContext context) => MessageProvider(),
        ),
      // 8. 学期（无依赖）
      if (semesterProvider != null)
        ChangeNotifierProvider<SemesterProvider>.value(value: semesterProvider)
      else
        ChangeNotifierProvider<SemesterProvider>(
          create: (BuildContext context) => SemesterProvider(),
        ),
      // 9. UI 偏好（无依赖）
      if (settingsProvider != null)
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider)
      else
        ChangeNotifierProvider<SettingsProvider>(
          create: (BuildContext context) => SettingsProvider(),
        ),
    ],
    child: const MyApp(),
  );
}
/// 作业提醒的后台校验入口（由原生通过 `DartCallbackHandle` 调起）。
///
/// ## ⚠️ 必须留在 main.dart
///
/// AOT（release）下 `DartEntrypoint` 只按函数名在**根库**里查找，完全忽略
/// `callbackLibraryPath`。把入口放到别的文件会出现：debug 正常，release 一触发
/// 就报 `Could not resolve main entrypoint function`，引擎起不来，校验永远失败。
/// 实际逻辑在 `runHomeworkCheckEntrypoint()`（services/homework_check_entry.dart）。
@pragma('vm:entry-point')
void homeworkNotificationCheckMain() => runHomeworkCheckEntrypoint();

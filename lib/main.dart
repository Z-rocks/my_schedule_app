// App 入口：装配 Provider 树（含 PluginProvider → ModuleProvider 的能力联动）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/course_provider.dart';
import 'providers/message_provider.dart';
import 'providers/module_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/semester_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  // 必须先初始化绑定，Hive.initFlutter() 依赖平台通道（path_provider）。
  WidgetsFlutterBinding.ensureInitialized();

  // 打开 Hive Box；失败不会抛异常，只记日志，App 仍能以"无数据"状态启动。
  await StorageService.init();

  // 先把持久化状态读进内存，再起 UI——避免首帧闪一下默认值
  // （例如导航栏先显示默认 4 个模块、再跳成用户配置的样子）。
  final CourseProvider courseProvider = CourseProvider();
  await courseProvider.loadFromStorage();

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

  // 插件：先读列表，再加载所有已启用插件的运行时（失败只降级，不影响启动）。
  final PluginProvider pluginProvider = PluginProvider();
  await pluginProvider.loadFromStorage();
  await pluginProvider.loadAllEnabledPlugins();

  runApp(buildApp(
    courseProvider: courseProvider,
    moduleProvider: moduleProvider,
    semesterProvider: semesterProvider,
    settingsProvider: settingsProvider,
    themeProvider: themeProvider,
    pluginProvider: pluginProvider,
  ));
}

/// 构建完整的 App（Provider 树 + 根组件）。
///
/// 抽成函数是为了让 widget 测试能直接 `pumpWidget(buildApp())`，
/// 验证的即是 `main()` 真正使用的这棵 Provider 树，而不是测试里另写一份。
///
/// 五个可选参数由 `main()` 传入**已完成存储加载**的实例；
/// 不传时（测试、预览）内部自建空实例，此时不会访问 Hive。
///
/// 生命周期：`CourseProvider` / `SemesterProvider` / `SettingsProvider` /
/// `ThemeProvider` / `PluginProvider` 走 `.value`，实例归调用方所有，
/// 不随 Provider 树销毁而 dispose。
/// `ModuleProvider` 由 `ChangeNotifierProxyProvider` 创建（该 Provider 没有
/// `.value` 变体），因此注入的实例会被 Provider 树接管生命周期——
/// 在 App 生命周期内不会销毁，所以实际没有差别；但**不要**把同一个
/// ModuleProvider 实例同时传给两棵 Provider 树（先卸载的那棵会 dispose 它）。
Widget buildApp({
  CourseProvider? courseProvider,
  ModuleProvider? moduleProvider,
  SemesterProvider? semesterProvider,
  SettingsProvider? settingsProvider,
  ThemeProvider? themeProvider,
  PluginProvider? pluginProvider,
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
      // 5. 消息（无依赖）
      ChangeNotifierProvider<MessageProvider>(
        create: (BuildContext context) => MessageProvider(),
      ),
      // 6. 学期（无依赖）
      if (semesterProvider != null)
        ChangeNotifierProvider<SemesterProvider>.value(value: semesterProvider)
      else
        ChangeNotifierProvider<SemesterProvider>(
          create: (BuildContext context) => SemesterProvider(),
        ),
      // 7. UI 偏好（无依赖）
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
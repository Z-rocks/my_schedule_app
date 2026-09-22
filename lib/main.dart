// App 入口：装配 Provider 树（含 PluginProvider → ModuleProvider 的能力联动）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/course_provider.dart';
import 'providers/message_provider.dart';
import 'providers/module_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/theme_provider.dart';

void main() {
  runApp(buildApp());
}

/// 构建完整的 App（Provider 树 + 根组件）。
///
/// 抽成函数是为了让 widget 测试能直接 `pumpWidget(buildApp())`，
/// 验证的即是 `main()` 真正使用的这棵 Provider 树，而不是测试里另写一份。
Widget buildApp() {
  return MultiProvider(
    // Provider 顺序即依赖顺序：被依赖者必须排在依赖者之前。
    // `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>`
    // 依赖 PluginProvider，所以 PluginProvider 必须先声明。
    providers: [
      // 1. 主题（无依赖）
      ChangeNotifierProvider<ThemeProvider>(
        create: (BuildContext context) => ThemeProvider(),
      ),
      // 2. 插件（无依赖，但被 ModuleProvider 依赖）
      ChangeNotifierProvider<PluginProvider>(
        create: (BuildContext context) => PluginProvider(),
      ),
      // 3. 模块（依赖 PluginProvider 的能力集合）
      ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>(
        create: (BuildContext context) => ModuleProvider(),
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
      ChangeNotifierProvider<CourseProvider>(
        create: (BuildContext context) => CourseProvider(),
      ),
      // 5. 消息（无依赖）
      ChangeNotifierProvider<MessageProvider>(
        create: (BuildContext context) => MessageProvider(),
      ),
    ],
    child: const MyApp(),
  );
}
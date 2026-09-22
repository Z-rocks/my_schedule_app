// App 根组件：MaterialApp 配置 + 把 AppTheme 注入 ThemeData.extensions
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_extension.dart';

/// 应用根组件。
///
/// 必须位于 `MultiProvider` **之下**（见 `main.dart`），
/// 因为它通过 `context.watch<ThemeProvider>()` 读取当前主题；
/// 主题变化时本组件重建，`MaterialApp` 随之套用新配色。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = context.watch<ThemeProvider>().currentTheme;

    return MaterialApp(
      title: '我的课表',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: theme.primary),
        useMaterial3: true,
        // 自定义字体族；空字符串表示用系统默认字体。
        fontFamily: theme.fontFamily.isEmpty ? null : theme.fontFamily,
        // 把完整令牌集合挂到 ThemeData，UI 通过 AppThemeExtension.of(context) 读取。
        extensions: <ThemeExtension<dynamic>>[
          AppThemeExtension(theme: theme),
        ],
      ),
      home: const HomePage(),
    );
  }
}
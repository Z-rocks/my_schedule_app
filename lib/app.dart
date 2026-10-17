// App 根组件：MaterialApp 配置 + 把 AppTheme 注入 ThemeData.extensions
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'providers/theme_provider.dart';
import 'services/widget_bridge.dart';
import 'theme/app_theme.dart';
import 'theme/theme_extension.dart';

/// 应用根组件。
///
/// 必须位于 `MultiProvider` **之下**（见 `main.dart`），
/// 因为它通过 `context.watch<ThemeProvider>()` 读取当前主题；
/// 主题变化时本组件重建，`MaterialApp` 随之套用新配色。
///
/// **Phase 6 起是 `StatefulWidget`**：为了接收
/// `didChangePlatformBrightness`（系统切换深色模式时"跟随系统"要立刻生效）。
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 小组件点击跳转通道（Phase W1）：放在首帧之后注册，等 Flutter 引擎
    // 的 platform view 就绪再 invokeMethod，避免 MissingPluginException。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      unawaited(WidgetNav.init());
    });
    // 初次同步系统亮度：`system` 模式下要靠它决定用哪套配色。
    // `initState` 里 `context.read` 是合法的（Provider 在上层，
    // 且 `read` 不会注册依赖，不存在"build 前订阅"的问题）。
    _applySystemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 系统明暗模式变化（用户在系统设置里切换深色）。
  @override
  void didChangePlatformBrightness() {
    _applySystemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  /// 把系统亮度告知 [ThemeProvider]（只有 `system` 模式会真的改变主题）。
  void _applySystemBrightness(Brightness value) {
    if (!mounted) return;
    context.read<ThemeProvider>().syncSystemBrightness(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final AppTheme theme = themeProvider.currentTheme;
    final ThemeMode mode = themeProvider.themeMode;

    return MaterialApp(
      title: '校园助手',
      debugShowCheckedModeBanner: false,
      // 明暗两套都用**同一个** AppTheme（它已按 `system` 选好色表），
      // 只是喂给 `ColorScheme.fromSeed` 的 brightness 不同。
      // 真正的配色由 `AppThemeExtension` 提供，UI 一律从那里读
      // （CONTEXT 3.2），Material 自己的 colorScheme 只影响我没显式覆盖的组件。
      theme: _themeData(theme, Brightness.light),
      darkTheme: _themeData(theme, Brightness.dark),
      themeMode: mode,
      home: const HomePage(),
    );
  }

  /// 用 [AppTheme] 令牌构造 `ThemeData`。
  ///
  /// [brightness] 必须是**明确的**（不能用 `theme.brightness` 推断）：
  /// 否则"暗色模式 + 亮色皮肤"会得到一个声明亮色、实际配深色文字的
  /// `colorScheme`，Material 组件（对话框、SnackBar）的默认配色就会错。
  ThemeData _themeData(AppTheme theme, Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: theme.primary,
        brightness: brightness,
      ),
      useMaterial3: true,
      // 自定义字体族；空字符串表示用系统默认字体。
      fontFamily: theme.fontFamily.isEmpty ? null : theme.fontFamily,
      scaffoldBackgroundColor: theme.background,
      // 把完整令牌集合挂到 ThemeData，UI 通过 AppThemeExtension.of(context) 读取。
      extensions: <ThemeExtension<dynamic>>[
        AppThemeExtension(theme: theme),
      ],
    );
  }
}

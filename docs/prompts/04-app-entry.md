# 任务：App 入口 + 动态导航栏（Phase 1.4）

## 目标
生成 App 入口、MaterialApp 配置、动态底部导航栏。

## 要生成的文件

### 1. `lib/main.dart`
- `void main()` 中调用 `runApp(const MyApp())`
- 用 `MultiProvider` 包裹
- Provider 列表：
    - `ChangeNotifierProvider<ThemeProvider>`
    - `ChangeNotifierProvider<ModuleProvider>`
    - `ChangeNotifierProvider<CourseProvider>`
    - `ChangeNotifierProvider<MessageProvider>`
    - `ChangeNotifierProvider<PluginProvider>`
- **关键**：`PluginProvider` 变化时要通知 `ModuleProvider`
    - 用 `ChangeNotifierProxyProvider<PluginProvider, ModuleProvider>` 实现
    - 每次 `PluginProvider` 通知时，调用 `ModuleProvider.updateCapabilities(pluginProvider.allCapabilities)`

### 2. `lib/app.dart` — MyApp
```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context);
}
```

- `MaterialApp`
- `title: '我的课表'`
- `debugShowCheckedModeBanner: false`
- `theme`：从 `ThemeProvider` 读 `currentTheme`，构造 `ThemeData`
    - `colorScheme: ColorScheme.fromSeed(seedColor: theme.primary)`
    - `useMaterial3: true`
    - `extensions: [AppThemeExtension(theme: theme)]`
- `home: const HomePage()`

### 3. `lib/pages/home_page.dart` — HomePage
```dart
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  
  @override
  State<HomePage> createState() => _HomePageState();
}
```

**逻辑**：
- 从 `ModuleProvider` 读 `visibleModules`
- 根据 `visibleModules` 构建底部 `NavigationBar`
- 每个模块对应一个页面，通过 `switch` 映射：
  | ModuleType | 页面 |
  |------------|------|
  | timetable | `TimetableView()` |
  | courseList | `CourseListView()` |
  | exam | `ExamView()` |
  | homework | `HomeworkView()` |
  | message | `MessageView()` |
  | settings | `SettingsPage()` |
- 当前选中索引用 `_currentIndex` state 管理
- **注意**：当 `visibleModules.length` 变化时，如果 `_currentIndex` 越界，重置为 0
    - 在 `build` 里判断，或监听 `ModuleProvider` 的变化

## 约束
- 使用 Material 3 的 `NavigationBar`（不是老的 `BottomNavigationBar`）
- 导航栏图标从 `ModuleInfo.icon` 读
- 导航栏标签从 `ModuleInfo.name` 读
- 不要引入 go_router，用原生 `Navigator`

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出，包含所有 import
- 写完后额外输出 API 接口清单
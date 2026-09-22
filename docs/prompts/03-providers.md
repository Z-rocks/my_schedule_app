# 任务：状态管理（Phase 1.3）

## 目标
在 `lib/providers/` 目录下生成 Provider 文件。

## 要生成的文件

### 1. `lib/providers/module_provider.dart` — ModuleProvider
```dart
class ModuleProvider extends ChangeNotifier {
  List<ModuleInfo> get allModules;
  List<ModuleInfo> get visibleModules;
  void toggle(ModuleType type, bool enabled);
  void updateCapabilities(Set<String> capabilities);
}
```

**初始模块列表**（按顺序）：
| type | name | icon | required | 初始 available | 初始 enabled |
|------|------|------|:--------:|:--------------:|:------------:|
| timetable | 课表 | Icons.calendar_month | true | true | true |
| courseList | 课程 | Icons.book_outlined | false | true | true |
| exam | 考试 | Icons.assignment_outlined | false | false | true |
| homework | 作业 | Icons.edit_note | false | false | false |
| message | 消息 | Icons.notifications_outlined | false | true | true |
| settings | 设置 | Icons.settings_outlined | true | true | true |

**visibleModules 规则**：
- `required == true` 的永远包含
- 非 required：`available && enabled` 才包含
- 最多 5 个
- 超过 5 个时：优先保留 required，其余按模块列表顺序取

**updateCapabilities**：
- 输入插件能力集合（如 `{'timetable', 'exam'}`）
- `exam` 模块：能力含 `'exam'` 时 `available = true`，否则 false
- `homework` 模块：能力含 `'homework'` 时 `available = true`，否则 false

### 2. `lib/providers/course_provider.dart` — CourseProvider
```dart
class CourseProvider extends ChangeNotifier {
  List<Course> get courses;
  List<Course> get visibleCourses;
  Course? getById(String id);
  void setCourses(List<Course> list);
  void addCourse(Course c);
  void updateCourse(Course c);
  void deleteCourse(String id);
}
```

- `visibleCourses`：过滤掉 `override?.hidden == true` 的课程
- **Phase 1 不接 Hive**，只在内存操作
- 数据为临时数据，App 重启后清空

### 3. `lib/providers/theme_provider.dart` — ThemeProvider
```dart
class ThemeProvider extends ChangeNotifier {
  AppTheme get currentTheme;
  Brightness get brightness;
  Future<void> applySkin(SkinPack skin);
  Future<void> resetTheme();
  void setBrightness(Brightness b);
  AppTheme previewSkin(SkinPack skin);
}
```

- 内部持有 `ThemeEngine`
- `applySkin` 调用 `engine.loadSkin` 后 `notifyListeners`
- `brightness` 存储用户明暗模式偏好

### 4. `lib/providers/plugin_provider.dart` — PluginProvider
```dart
class PluginProvider extends ChangeNotifier {
  List<PluginMeta> get plugins;
  List<PluginMeta> get enabledPlugins;
  Set<String> get allCapabilities;
  void addPlugin(PluginMeta p);
  void removePlugin(String id);
  void togglePlugin(String id, bool enabled);
}
```

- `allCapabilities`：所有 `enabled == true` 的插件的 `capabilities` 并集
- **Phase 1 为空列表**，只提供接口

### 5. `lib/providers/message_provider.dart` — MessageProvider
```dart
class MessageProvider extends ChangeNotifier {
  List<Message> get messages;
  int get unreadCount;
  void addMessage(Message m);
  void markAsRead(String id);
  void markAllAsRead();
  void clearOldMessages();
}
```

- `messages` 按 `createdAt` **倒序**排列
- `clearOldMessages`：删除 30 天前的消息

## 约束
- 严格遵循 `docs/CONTEXT.md`
- 所有 Provider 继承 `ChangeNotifier`
- 不引入 Hive、dio（Phase 1 只做内存状态）
- Provider 之间**不互相引用**
- 每个 Provider 顶部加文件用途注释

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出
- 写完后额外输出 API 接口清单
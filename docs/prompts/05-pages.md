# 任务：页面空态（Phase 1.5）

## 目标
生成所有模块页面的空态骨架，不实现业务逻辑。

## 要生成的文件

### 1. `lib/pages/timetable/timetable_view.dart` — TimetableView
- `Scaffold` + `AppBar`：标题"课表"，右侧 `+` 按钮
    - `+` 按钮点击：`SnackBar('添加课程（待实现）')`
- `AppBar` 下方：周次选择器（1-20 的水平数字列表，默认选中当前周）
    - 简单实现即可：`ListView.builder` horizontal + `ChoiceChip`
- Body：空态
    - 图标：`Icons.calendar_today`
    - 主文案：`"还没有课表数据"`
    - 副文案：`"点击右上角 + 添加课程，或安装插件从教务系统导入"`
    - 按钮：`"去设置安装插件"`（点击 `SnackBar('请前往设置 → 插件管理')`）

### 2. `lib/pages/course_list/course_list_view.dart` — CourseListView
- AppBar 标题"课程"
- 空态：`Icons.book_outlined` + `"暂无课程"`

### 3. `lib/pages/exam/exam_view.dart` — ExamView
- AppBar 标题"考试"
- 空态：`Icons.assignment_outlined` + `"暂无考试安排"` + 副文案 `"安装支持考试能力的插件后可导入"`

### 4. `lib/pages/homework/homework_view.dart` — HomeworkView
- AppBar 标题"作业"
- 空态：`Icons.edit_note` + `"暂无作业"` + 副文案 `"安装学习通等插件后可查看"`

### 5. `lib/pages/message/message_view.dart` — MessageView
- AppBar 标题"消息"，右侧"全部已读"按钮
    - 点击：`SnackBar('已全部标记为已读')`
- 空态：`Icons.notifications_none` + `"暂无消息"`

## 通用组件

### 6. `lib/widgets/empty_state.dart` — EmptyState
```dart
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
}
```

- 垂直居中
- 图标 `size: 80`
- 颜色从 `AppThemeExtension` 读

## 约束
- 所有页面用 `Scaffold` + `AppBar`
- 空态统一用 `EmptyState` 组件
- 颜色从 `Theme.of(context).extension<AppThemeExtension>()!.theme` 读
- 不写任何业务逻辑

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出
- 写完后额外输出 API 接口清单
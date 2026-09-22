# 任务：数据模型（Phase 1.1）

## 目标
在 `lib/models/` 目录下生成数据模型文件。

## 要生成的文件

### 1. `lib/models/course.dart` — Course
**字段**
- `id` (String)
- `name` (String)
- `teacher` (String)
- `unit` (double)
- `category` (String)
- `timePlaces` (List<TimePlace>)
- `sourcePluginId` (String) — 来源插件 ID，用户自建为 `'user'`
- `override` (UserOverride?)

**实现**
- 构造函数（使用 `required` 关键字）
- `factory Course.fromJson(Map<String, dynamic> json)`
- `Map<String, dynamic> toJson()`
- `Course copyWith({...})`

### 2. `lib/models/time_place.dart` — TimePlace
**字段**
- `day` (int) — 1-7，周一到周日
- `startSession` (int) — 起始节次，1-12
- `length` (int) — 持续节数
- `room` (String)
- `weeks` (List<int>) — 解析后的周次列表
- `rawWeeksText` (String) — 原始文本，如 `"4,6-14周"`

**实现**
- 构造函数
- `fromJson` / `toJson`
- `copyWith`

### 3. `lib/models/user_override.dart` — UserOverride
**字段**
- `customName` (String?)
- `customTeacher` (String?)
- `customColor` (int?) — ARGB 整数，如 `0xFF1E88E5`
- `note` (String?)
- `hidden` (bool) — 默认 `false`
- `customTimePlaces` (List<TimePlace>?)
- `updatedAt` (DateTime)

**实现**
- 构造函数（`hidden` 默认 false，`updatedAt` 默认 `DateTime.now()`）
- `fromJson` / `toJson`
- `copyWith`

## 约束
- 严格遵循 `docs/CONTEXT.md` 的代码规范
- 所有字段 `final`
- 只依赖 Dart 内置类型和本目录下的模型
- `fromJson` 必须处理 `null` 值和类型转换
- 时间字段用 `DateTime`，不用字符串
- 不要用 `freezed` / `build_runner`，手写实现

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出，不省略
- 写完后额外输出一份 API 接口清单，供我更新 `docs/API.md`
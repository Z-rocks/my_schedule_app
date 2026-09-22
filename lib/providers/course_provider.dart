// 课程状态：管理课程列表，与 Hive 双向同步，并按用户覆盖层过滤隐藏课程
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/course.dart';
import '../models/user_override.dart';
import '../services/override_engine.dart';
import '../services/storage_service.dart';

/// 课程列表状态。
///
/// 数据流向（CONTEXT.md 3.3）：
/// - 原始课程 → `courses` Box（key = 课程 ID）
/// - 用户覆盖层 → `overrides` Box（key = 课程 ID），由 [OverrideEngine] 管理
/// - 展示时用 `userOverride?.customXxx ?? original.xxx` 叠加
///
/// 同步写入时**只更新原始字段、不动覆盖层**，因此教务重新同步不会冲掉用户的修改。
///
/// 本类不引用任何其他 Provider。
class CourseProvider extends ChangeNotifier {
  final List<Course> _courses = <Course>[];
  bool _disposed = false;
  bool _loaded = false;

  /// 是否已从 Hive 载入过数据（UI 可据此区分"空数据"与"尚未加载"）。
  bool get isLoaded => _loaded;

  /// 全部课程（含被用户隐藏的），返回不可变视图。
  List<Course> get courses => UnmodifiableListView<Course>(_courses);

  /// 展示用课程列表：过滤掉 `userOverride?.hidden == true` 的课程。
  ///
  /// 过滤依据是 [Course.isHidden]（即 `userOverride?.hidden ?? false`）——
  /// 隐藏只影响展示，原始数据仍保留在 [courses] 中，撤销隐藏即可恢复。
  /// 保持插入顺序（课表 / 列表页的排序由 `TimetableLogic` 负责）。
  List<Course> get visibleCourses => UnmodifiableListView<Course>(
        _courses.where((Course course) => !course.isHidden).toList(),
      );

  /// 被用户隐藏的课程数量。
  int get hiddenCount => _courses.where((Course c) => c.isHidden).length;

  /// 课程总数（含隐藏）。
  int get length => _courses.length;

  /// 按 [id] 查找课程；不存在返回 `null`。
  Course? getById(String id) {
    for (final Course course in _courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  // ——————————————————————— Hive 读写 ———————————————————————

  /// 从 Hive 载入课程，并把 `overrides` Box 里的覆盖层挂载上去。
  ///
  /// 覆盖层用 [OverrideEngine.getAllOverrides] **一次性**读出后按课程 ID 索引，
  /// 避免"每门课查一次 Box"。
  ///
  /// 任何异常都不会中断启动：解析失败的单条数据被跳过，整体失败只记日志。
  Future<void> loadFromStorage() async {
    try {
      final Map<String, UserOverride> overrides =
          OverrideEngine.getAllOverrides();

      final List<Course> loaded = <Course>[];
      final Map<dynamic, String> raw = StorageService.coursesBox.toMap();
      for (final MapEntry<dynamic, String> entry in raw.entries) {
        final Course? course = _decodeCourse(entry.value);
        if (course == null) continue;

        final UserOverride? override = overrides[course.id];
        // overrides Box 是覆盖层的权威来源；万一课程 JSON 里也带了覆盖层
        // （早期版本写入的数据），则以 overrides Box 为准，都没有时保留原值。
        loaded.add(override == null
            ? course
            : course.copyWith(userOverride: override));
      }

      _courses
        ..clear()
        ..addAll(loaded);
      _loaded = true;
      _notify();
    } catch (error, stackTrace) {
      debugPrint('CourseProvider.loadFromStorage 失败: $error');
      debugPrint('$stackTrace');
      // 保持内存现状（通常为空列表），不抛异常，App 仍可用。
    }
  }

  /// 保存课程：先落盘，再更新内存并通知。
  ///
  /// 落盘时**剥离覆盖层**（[Course.copyWith] 的 `clearUserOverride`）写入
  /// `courses` Box，覆盖层另行交给 [OverrideEngine] 写 `overrides` Box——
  /// 这样"原始 + 覆盖"始终分离，重新同步原始数据不会带走用户修改。
  ///
  /// 若 [Course.userOverride] 为 `null`，**不会**去删除已有的覆盖层：
  /// 插件同步下来的原始课程本来就不带覆盖层，删了就等于冲掉用户修改。
  Future<void> saveCourse(Course c) async {
    try {
      final Course raw = c.copyWith(clearUserOverride: true);
      await StorageService.coursesBox.put(c.id, jsonEncode(raw.toJson()));

      final UserOverride? override = c.userOverride;
      if (override != null) {
        await OverrideEngine.saveOverride(c.id, override);
      }
    } catch (error, stackTrace) {
      debugPrint('CourseProvider.saveCourse(${c.id}) 落盘失败: $error');
      debugPrint('$stackTrace');
      // 落盘失败也继续更新内存：本次会话内用户的修改不丢失。
    }
    _upsert(c);
    _notify();
  }

  /// 删除课程：同时删除原始数据与它的覆盖层。
  ///
  /// 注意：CONTEXT.md 3.3 规定"删除教务课程只能隐藏或永久忽略，不能真删"。
  /// 本方法供用户自建课程（`sourcePluginId == 'user'`）与数据清理使用；
  /// 隐藏教务课程请改为写 `userOverride.hidden`。
  Future<void> deleteCourse(String id) async {
    try {
      await StorageService.coursesBox.delete(id);
      // 覆盖层以课程 ID 为 key，课程真删后它就是孤儿数据，一并清掉。
      await OverrideEngine.removeOverride(id);
    } catch (error, stackTrace) {
      debugPrint('CourseProvider.deleteCourse($id) 落盘失败: $error');
      debugPrint('$stackTrace');
    }

    final int index = _indexOf(id);
    if (index < 0) return;
    _courses.removeAt(index);
    _notify();
  }

  /// 清空课程与覆盖层（测试 / 重置用）。
  Future<void> clearAll() async {
    try {
      await StorageService.coursesBox.clear();
      await StorageService.overridesBox.clear();
    } catch (error, stackTrace) {
      debugPrint('CourseProvider.clearAll 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    _loaded = true;
    if (_courses.isEmpty) {
      _notify();
      return;
    }
    _courses.clear();
    _notify();
  }

  /// 把存进 Box 的 JSON 字符串解析成 [Course]；失败返回 `null`（跳过该条）。
  Course? _decodeCourse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json[key.toString()] = value;
      });
      return Course.fromJson(json);
    } catch (error) {
      debugPrint('CourseProvider: 跳过无法解析的课程数据: $error');
      return null;
    }
  }

  // ——————————————— 纯内存操作（不落盘） ———————————————
  // 供 loadFromStorage / 测试 / 临时预览使用；业务侧请用 saveCourse。

  /// 整体替换课程列表（仅内存）。
  void setCourses(List<Course> list) {
    _courses
      ..clear()
      ..addAll(list);
    _notify();
  }

  /// 新增或替换课程（仅内存）。同 [Course.id] 已存在则替换。
  void addCourse(Course c) {
    _upsert(c);
    _notify();
  }

  /// 更新课程（仅内存），按 [Course.id] 定位，找不到则新增（upsert）。
  void updateCourse(Course c) => addCourse(c);

  /// 清空课程列表（仅内存）。
  void clear() {
    if (_courses.isEmpty) return;
    _courses.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 已释放则不再通知，避免异步回调触发 `ChangeNotifier` 的 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _upsert(Course c) {
    final int index = _indexOf(c.id);
    if (index >= 0) {
      _courses[index] = c;
    } else {
      _courses.add(c);
    }
  }

  int _indexOf(String id) {
    for (int i = 0; i < _courses.length; i++) {
      if (_courses[i].id == id) return i;
    }
    return -1;
  }
}
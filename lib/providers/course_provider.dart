// 课程状态：内存中管理课程列表，并按用户覆盖层过滤隐藏课程
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/course.dart';

/// 课程列表状态。
///
/// **Phase 1 只做内存状态**：不接 Hive，App 重启后数据清空
/// （Phase 2 由 `StorageService` 接入 Hive Box）。
///
/// 本类不引用任何其他 Provider。
class CourseProvider extends ChangeNotifier {
  final List<Course> _courses = <Course>[];
  bool _disposed = false;

  /// 全部课程（含被用户隐藏的），返回不可变视图。
  List<Course> get courses => UnmodifiableListView<Course>(_courses);

  /// 展示用课程列表：过滤掉 `userOverride?.hidden == true` 的课程。
  ///
  /// 过滤依据是 [Course.isHidden]（即 `userOverride?.hidden ?? false`）——
  /// 隐藏只影响展示，原始数据仍保留在 [courses] 中，撤销隐藏即可恢复。
  /// 保持插入顺序（课表 / 列表页的排序在 Phase 2 的 TimetableLogic 里做）。
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

  /// 整体替换课程列表（Phase 2 从 Hive / 插件同步后用）。
  void setCourses(List<Course> list) {
    _courses
      ..clear()
      ..addAll(list);
    _notify();
  }

  /// 新增课程。
  ///
  /// 若同 [Course.id] 已存在则替换（课程 ID 是唯一键，
  /// Phase 2 会直接用它作 Hive Box 的 key，不能出现重复）。
  void addCourse(Course c) {
    final int index = _indexOf(c.id);
    if (index >= 0) {
      _courses[index] = c;
    } else {
      _courses.add(c);
    }
    _notify();
  }

  /// 更新课程（按 [Course.id] 定位）。
  ///
  /// 找不到同 id 的课程时按新增处理（upsert），调用方无需先判断是否存在。
  void updateCourse(Course c) => addCourse(c);

  /// 删除课程。
  ///
  /// 注意：CONTEXT.md 3.3 规定"删除教务课程只能隐藏或永久忽略，不能真删"。
  /// 本方法供用户自建课程（`sourcePluginId == 'user'`）与数据清理使用；
  /// 隐藏教务课程请改为写入 `userOverride.hidden`。
  void deleteCourse(String id) {
    final int index = _indexOf(id);
    if (index < 0) return;
    _courses.removeAt(index);
    _notify();
  }

  /// 清空全部课程。
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

  int _indexOf(String id) {
    for (int i = 0; i < _courses.length; i++) {
      if (_courses[i].id == id) return i;
    }
    return -1;
  }
}
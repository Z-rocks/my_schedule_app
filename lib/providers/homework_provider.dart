// Phase 8：作业状态——管理作业列表，与 Hive 双向同步。
//
// 与 `CourseProvider` 的异同：
// - **同**：原始数据落 `homeworks` Box（key = 作业 ID）、同步只更新原始字段、
//   用户改动不会被插件同步冲掉、坏数据跳过不崩。
// - **异**：课程的覆盖层存在**独立的 `overrides` Box**（由 `OverrideEngine` 管），
//   而作业的覆盖层**内联在作业 JSON 里**（`Homework.toJson()` 本来就带
//   `userOverride`）。为什么不统一？`overrides` Box 的 key 空间是"课程 ID"，
//   把作业 ID 塞进去会与课程抢同一个键空间（两者都可能是 `chaoxing:<数字>`），
//   一旦撞号就是"改作业勾选状态把课程颜色改了"这种极难排查的问题。
//   内联存储没有这个风险，且 `Homework` 模型本来就是为此设计的。
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/homework.dart';
import '../models/user_override.dart';
import '../services/plugin_entity_sync_service.dart';
import '../services/storage_service.dart';

/// 作业列表状态。
///
/// 数据流向（CONTEXT 3.3）：
/// - 原始作业 → `homeworks` Box（key = 作业 ID）
/// - 用户覆盖层 → **内联**在作业 JSON 里（见文件头注释的取舍说明）
/// - 展示时用 `userOverride?.customXxx ?? original.xxx` 叠加
///
/// 本类不引用任何其他 Provider。
class HomeworkProvider extends ChangeNotifier implements EntityStore<Homework> {
  final List<Homework> _homeworks = <Homework>[];
  bool _disposed = false;
  bool _loaded = false;

  /// 是否已从 Hive 载入过数据（UI 可据此区分"空数据"与"尚未加载"）。
  bool get isLoaded => _loaded;

  /// 全部作业（含被用户隐藏的），返回不可变视图。
  List<Homework> get homeworks => UnmodifiableListView<Homework>(_homeworks);

  /// 展示用作业列表：过滤掉被隐藏的，并按"未完成优先 → 截止时间升序"排序。
  ///
  /// 排序规则：
  /// 1. 未完成在前（已完成的沉底，不打扰用户）；
  /// 2. 组内按 [Homework.displayDeadline] 升序（**用展示截止时间**——
  ///    用户改过期的话，按用户改的排）；
  /// 3. 没有截止时间的排在**最后**（不知道什么时候交的不该顶在最前面）；
  /// 4. 仍相同则按标题，保证顺序稳定（否则每次重建列表都可能换位）。
  List<Homework> get displayHomeworks {
    final List<Homework> sorted = _homeworks
        .where((Homework h) => !h.isHidden)
        .toList();
    sorted.sort(_compareForDisplay);
    return UnmodifiableListView<Homework>(sorted);
  }

  /// 被用户隐藏的作业（供"已隐藏"页展示与恢复）。
  List<Homework> get hiddenHomeworks => UnmodifiableListView<Homework>(
        _homeworks.where((Homework h) => h.isHidden),
      );

  /// 作业总数（含隐藏）。
  int get length => _homeworks.length;

  /// 被隐藏的作业数量。
  int get hiddenCount => _homeworks.where((Homework h) => h.isHidden).length;

  /// 未完成且未隐藏的作业数量（底部导航角标 / 概览用）。
  int get pendingCount => _homeworks
      .where((Homework h) => !h.isHidden && !h.isCompleted)
      .length;

  /// 已逾期的作业数量（未完成且已过截止时间）。
  int overdueCount(DateTime now) => _homeworks
      .where((Homework h) => !h.isHidden && h.isOverdue(now))
      .length;

  /// 按 [id] 查找作业；不存在返回 `null`。
  @override
  Homework? getById(String id) {
    for (final Homework homework in _homeworks) {
      if (homework.id == id) return homework;
    }
    return null;
  }

  // ——————————————————————— Hive 读写 ———————————————————————

  /// 从 `homeworks` Box 载入全部作业。
  ///
  /// **替换**内存列表（不是累加）；解析失败的单条被跳过，整体失败只记日志。
  Future<void> loadFromStorage() async {
    try {
      final List<Homework> loaded = <Homework>[];
      final Map<dynamic, dynamic> raw = StorageService.homeworksBox.toMap();
      for (final Object? value in raw.values) {
        if (value is! String) continue;
        final Homework? homework = _decode(value);
        if (homework != null) loaded.add(homework);
      }
      _homeworks
        ..clear()
        ..addAll(loaded);
      _loaded = true;
      _notify();
    } catch (error, stackTrace) {
      _loaded = true;
      debugPrint('HomeworkProvider.loadFromStorage 失败（按无作业处理）: $error');
      debugPrint('$stackTrace');
      // 保持内存现状（通常为空列表），不抛异常，App 仍可用。
    }
  }

  /// 保存作业：先落盘，再更新内存并通知。
  ///
  /// **覆盖层保留**（本类的核心不变量）：入参不带覆盖层时，
  /// 把**内存里已有的覆盖层重新挂回去**，再整体落盘。
  ///
  /// 为什么必须重新挂回去而不是"落盘时剥离、读盘时再合"：
  /// 覆盖层与原始字段**存在同一条 JSON 里**（见文件头注释），
  /// 所以剥离就意味着这次写入真的把用户改动删了。
  /// 插件同步每次都传入无覆盖层的原始作业，这条路径一定会被踩到。
  ///
  /// 覆盖层来源优先级：入参自带的 > 内存里那条已有的。
  @override
  Future<void> save(Homework homework) async {
    final UserOverride? override =
        homework.userOverride ?? getById(homework.id)?.userOverride;
    final Homework merged = homework.copyWith(userOverride: override);
    try {
      await StorageService.homeworksBox
          .put(merged.id, jsonEncode(merged.toJson()));
    } catch (error, stackTrace) {
      debugPrint('HomeworkProvider.save(${homework.id}) 落盘失败: $error');
      debugPrint('$stackTrace');
      // 落盘失败也继续更新内存：本次会话内用户的修改不丢失。
    }
    _upsert(merged);
    _notify();
  }

  /// 设置某份作业的"已完成"状态（用户勾选）。
  ///
  /// 勾选状态写在覆盖层里（`customCompleted`），因此**插件同步不会把它冲掉**——
  /// 即使学习通那边仍然显示"未交"，用户在本地的勾选也保留。
  ///
  /// 作业不存在时返回 `false`（调用方据此提示）。
  Future<bool> setCompleted(String id, bool completed) async {
    final Homework? homework = getById(id);
    if (homework == null) {
      debugPrint('HomeworkProvider.setCompleted($id) 找不到该作业');
      return false;
    }
    final UserOverride base =
        homework.userOverride ?? UserOverride(updatedAt: DateTime.now());
    await save(
      homework.copyWith(
        userOverride:
            base.copyWith(customCompleted: completed, updatedAt: DateTime.now()),
      ),
    );
    return true;
  }

  /// 设置某份作业的"隐藏"状态。
  ///
  /// 与课程一致（CONTEXT 3.3）：教务 / 插件来源的数据**只能隐藏、不能真删**，
  /// 隐藏可撤销，且覆盖层的其他字段原样保留。
  Future<bool> setHidden(String id, bool hidden) async {
    final Homework? homework = getById(id);
    if (homework == null) {
      debugPrint('HomeworkProvider.setHidden($id) 找不到该作业');
      return false;
    }
    final UserOverride base =
        homework.userOverride ?? UserOverride(updatedAt: DateTime.now());
    await save(
      homework.copyWith(
        userOverride: base.copyWith(hidden: hidden, updatedAt: DateTime.now()),
      ),
    );
    return true;
  }

  /// 删除作业（内存 + 存储）。
  ///
  /// 供用户自建作业（`sourcePluginId == 'user'`）与数据清理使用；
  /// 隐藏插件来源的作业请改用 [setHidden]。
  Future<void> deleteHomework(String id) async {
    try {
      await StorageService.homeworksBox.delete(id);
    } catch (error, stackTrace) {
      debugPrint('HomeworkProvider.deleteHomework($id) 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    final int index = _indexOf(id);
    if (index < 0) return;
    _homeworks.removeAt(index);
    _notify();
  }

  /// 清空作业（内存 + 存储，测试 / 重置用）。
  Future<void> clearAll() async {
    try {
      await StorageService.homeworksBox.clear();
    } catch (error, stackTrace) {
      debugPrint('HomeworkProvider.clearAll 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    _loaded = true;
    if (_homeworks.isEmpty) {
      _notify();
      return;
    }
    _homeworks.clear();
    _notify();
  }

  /// 把存进 Box 的 JSON 字符串解析成 [Homework]；失败返回 `null`（跳过该条）。
  static Homework? _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json['$key'] = value;
      });
      final Homework homework = Homework.fromJson(json);
      // id 是契约键，缺了就无法定位 / 去重，视为坏数据。
      return homework.id.isEmpty ? null : homework;
    } catch (error) {
      debugPrint('HomeworkProvider: 跳过无法解析的作业数据: $error');
      return null;
    }
  }

  // ——————————————— 纯内存操作（不落盘） ———————————————
  // 供 loadFromStorage / 测试 / 临时预览使用；业务侧请用 save。

  /// 整体替换作业列表（仅内存）。
  void setHomeworks(List<Homework> list) {
    _homeworks
      ..clear()
      ..addAll(list);
    _notify();
  }

  /// 新增或替换作业（仅内存）。同 id 已存在则替换。
  void addHomework(Homework homework) {
    _upsert(homework);
    _notify();
  }

  /// 清空作业列表（仅内存）。
  void clear() {
    if (_homeworks.isEmpty) return;
    _homeworks.clear();
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

  void _upsert(Homework homework) {
    final int index = _indexOf(homework.id);
    if (index >= 0) {
      _homeworks[index] = homework;
    } else {
      _homeworks.add(homework);
    }
  }

  int _indexOf(String id) {
    for (int i = 0; i < _homeworks.length; i++) {
      if (_homeworks[i].id == id) return i;
    }
    return -1;
  }

  /// 展示排序的比较器（规则见 [displayHomeworks]）。
  static int _compareForDisplay(Homework a, Homework b) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
    final DateTime? da = a.displayDeadline;
    final DateTime? db = b.displayDeadline;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    final int byTime = da.compareTo(db);
    return byTime != 0 ? byTime : a.title.compareTo(b.title);
  }
}

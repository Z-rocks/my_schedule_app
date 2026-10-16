// Phase 8：考试状态——管理考试列表，与 Hive 双向同步。
//
// 结构上与 `HomeworkProvider` 同构（同样是"原始 + 内联覆盖层"，
// 同样实现 `EntityStore` 供 `PluginEntitySyncService` 落盘），
// 差别只在排序与统计口径：考试按**开考时间升序**（越近越前），
// 没有"已完成"概念，但有"已开始 / 未开始"的划分。
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/exam.dart';
import '../models/user_override.dart';
import '../services/plugin_entity_sync_service.dart';
import '../services/storage_service.dart';

/// 考试列表状态。
///
/// 数据流向（CONTEXT 3.3）：
/// - 原始考试 → `exams` Box（key = 考试 ID）
/// - 用户覆盖层 → **内联**在考试 JSON 里（理由见 `HomeworkProvider` 文件头）
/// - 展示时用 `userOverride?.customXxx ?? original.xxx` 叠加
///
/// 本类不引用任何其他 Provider。
class ExamProvider extends ChangeNotifier implements EntityStore<Exam> {
  final List<Exam> _exams = <Exam>[];
  bool _disposed = false;
  bool _loaded = false;

  /// 是否已从 Hive 载入过数据（UI 可据此区分"空数据"与"尚未加载"）。
  bool get isLoaded => _loaded;

  /// 全部考试（含被用户隐藏的），返回不可变视图。
  List<Exam> get exams => UnmodifiableListView<Exam>(_exams);

  /// 展示用考试列表：过滤掉被隐藏的，并按"未开始优先 → 开考时间升序"排序。
  ///
  /// 排序规则：
  /// 1. 未开始的在前（考完的沉底）；
  /// 2. 组内按 [Exam.displayStartTime] 升序（**用展示时间**——用户改过就按改的排）；
  /// 3. 仍相同则按科目名，保证顺序稳定。
  List<Exam> get displayExams {
    final List<Exam> sorted = _exams
        .where((Exam e) => !e.isHidden)
        .toList();
    final DateTime now = DateTime.now();
    sorted.sort((Exam a, Exam b) => _compareForDisplay(a, b, now));
    return UnmodifiableListView<Exam>(sorted);
  }

  /// 被用户隐藏的考试（供"已隐藏"页展示与恢复）。
  List<Exam> get hiddenExams => UnmodifiableListView<Exam>(
        _exams.where((Exam e) => e.isHidden),
      );

  /// 考试总数（含隐藏）。
  int get length => _exams.length;

  /// 被隐藏的考试数量。
  int get hiddenCount => _exams.where((Exam e) => e.isHidden).length;

  /// 尚未开考且未隐藏的考试数量（底部导航角标 / 概览用）。
  int get upcomingCount {
    final DateTime now = DateTime.now();
    return _exams.where((Exam e) => !e.isHidden && !e.hasStarted(now)).length;
  }

  /// 最近一场未开始的考试；没有则返回 `null`。
  ///
  /// 供"下一次考试还有几天"这类概览使用。跳过已隐藏的。
  Exam? nextExam(DateTime now) {
    Exam? best;
    for (final Exam exam in _exams) {
      if (exam.isHidden || exam.hasStarted(now)) continue;
      if (best == null ||
          exam.displayStartTime.isBefore(best.displayStartTime)) {
        best = exam;
      }
    }
    return best;
  }

  /// 按 [id] 查找考试；不存在返回 `null`。
  @override
  Exam? getById(String id) {
    for (final Exam exam in _exams) {
      if (exam.id == id) return exam;
    }
    return null;
  }

  // ——————————————————————— Hive 读写 ———————————————————————

  /// 从 `exams` Box 载入全部考试。
  ///
  /// **替换**内存列表（不是累加）；解析失败的单条被跳过，整体失败只记日志。
  Future<void> loadFromStorage() async {
    try {
      final List<Exam> loaded = <Exam>[];
      final Map<dynamic, dynamic> raw = StorageService.examsBox.toMap();
      for (final Object? value in raw.values) {
        if (value is! String) continue;
        final Exam? exam = _decode(value);
        if (exam != null) loaded.add(exam);
      }
      _exams
        ..clear()
        ..addAll(loaded);
      _loaded = true;
      _notify();
    } catch (error, stackTrace) {
      _loaded = true;
      debugPrint('ExamProvider.loadFromStorage 失败（按无考试处理）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 保存考试：先落盘，再更新内存并通知。
  ///
  /// **覆盖层保留**：入参不带覆盖层时，把内存里已有的覆盖层重新挂回去
  /// （理由与实现取舍见 `HomeworkProvider.save`）。
  @override
  Future<void> save(Exam exam) async {
    final UserOverride? override = exam.userOverride ?? getById(exam.id)?.userOverride;
    final Exam merged = exam.copyWith(userOverride: override);
    try {
      await StorageService.examsBox.put(merged.id, jsonEncode(merged.toJson()));
    } catch (error, stackTrace) {
      debugPrint('ExamProvider.save(${exam.id}) 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    _upsert(merged);
    _notify();
  }

  /// 设置某场考试的"隐藏"状态。
  ///
  /// 与课程 / 作业一致：插件来源的数据只能隐藏、不能真删，隐藏可撤销。
  Future<bool> setHidden(String id, bool hidden) async {
    final Exam? exam = getById(id);
    if (exam == null) {
      debugPrint('ExamProvider.setHidden($id) 找不到该考试');
      return false;
    }
    final UserOverride base =
        exam.userOverride ?? UserOverride(updatedAt: DateTime.now());
    await save(
      exam.copyWith(
        userOverride: base.copyWith(hidden: hidden, updatedAt: DateTime.now()),
      ),
    );
    return true;
  }

  /// 删除考试（内存 + 存储）。供用户自建考试与数据清理使用。
  Future<void> deleteExam(String id) async {
    try {
      await StorageService.examsBox.delete(id);
    } catch (error, stackTrace) {
      debugPrint('ExamProvider.deleteExam($id) 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    final int index = _indexOf(id);
    if (index < 0) return;
    _exams.removeAt(index);
    _notify();
  }

  /// 清空考试（内存 + 存储，测试 / 重置用）。
  Future<void> clearAll() async {
    try {
      await StorageService.examsBox.clear();
    } catch (error, stackTrace) {
      debugPrint('ExamProvider.clearAll 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    _loaded = true;
    if (_exams.isEmpty) {
      _notify();
      return;
    }
    _exams.clear();
    _notify();
  }

  /// 把存进 Box 的 JSON 字符串解析成 [Exam]；失败返回 `null`（跳过该条）。
  static Exam? _decode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic key, dynamic value) {
        if (key != null) json['$key'] = value;
      });
      final Exam exam = Exam.fromJson(json);
      return exam.id.isEmpty ? null : exam;
    } catch (error) {
      debugPrint('ExamProvider: 跳过无法解析的考试数据: $error');
      return null;
    }
  }

  // ——————————————— 纯内存操作（不落盘） ———————————————
  // 供 loadFromStorage / 测试 / 临时预览使用；业务侧请用 save。

  /// 整体替换考试列表（仅内存）。
  void setExams(List<Exam> list) {
    _exams
      ..clear()
      ..addAll(list);
    _notify();
  }

  /// 新增或替换考试（仅内存）。同 id 已存在则替换。
  void addExam(Exam exam) {
    _upsert(exam);
    _notify();
  }

  /// 清空考试列表（仅内存）。
  void clear() {
    if (_exams.isEmpty) return;
    _exams.clear();
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

  void _upsert(Exam exam) {
    final int index = _indexOf(exam.id);
    if (index >= 0) {
      _exams[index] = exam;
    } else {
      _exams.add(exam);
    }
  }

  int _indexOf(String id) {
    for (int i = 0; i < _exams.length; i++) {
      if (_exams[i].id == id) return i;
    }
    return -1;
  }

  /// 展示排序的比较器（规则见 [displayExams]）。
  static int _compareForDisplay(Exam a, Exam b, DateTime now) {
    final bool aStarted = a.hasStarted(now);
    final bool bStarted = b.hasStarted(now);
    if (aStarted != bStarted) return aStarted ? 1 : -1;
    final int byTime = a.displayStartTime.compareTo(b.displayStartTime);
    return byTime != 0 ? byTime : a.name.compareTo(b.name);
  }
}

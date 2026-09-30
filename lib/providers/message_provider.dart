// 消息状态：管理通知消息列表，维护已读状态并清理过期消息
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/message.dart';
import '../services/storage_service.dart';

/// 消息保留天数：超过这个天数的消息由 [MessageProvider.clearOldMessages] 清理。
const int kMessageRetentionDays = 30;

/// 消息列表状态。
///
/// 消息来源两类：
/// - **插件**：`ctx.notify.schedule(...)` → 内核对它生成一条系统消息
///   （见 `PluginContext` 的 `onNotify` 回调）；
/// - **内核**：同步完成等事件主动写一条（见 `CourseSyncService` 的调用方）。
///
/// **Phase 7 起接入 Hive**（`messages` Box，key = 消息 ID）——
/// 之前是纯内存，重启即丢，与 CONTEXT 3.5「消息 → Hive Box」不符。
/// 本类不引用任何其他 Provider。
class MessageProvider extends ChangeNotifier {
  MessageProvider({List<Message>? messages}) {
    if (messages != null) {
      _messages.addAll(messages);
      _sortDescending();
    }
  }

  /// 内部列表**始终**按 [Message.createdAt] 倒序（最新的在最前）。
  final List<Message> _messages = <Message>[];
  bool _disposed = false;
  bool _loaded = false;

  /// 是否已从 Hive 载入过（UI 可区分"没有消息"与"尚未加载"）。
  bool get isLoaded => _loaded;

  /// 全部消息，按 [Message.createdAt] 倒序，返回不可变视图。
  List<Message> get messages => UnmodifiableListView<Message>(_messages);

  /// 未读消息数量（底部导航角标用）。
  int get unreadCount =>
      _messages.where((Message m) => m.isUnread).length;

  /// 消息总数。
  int get length => _messages.length;

  /// 按 [id] 查找消息；不存在返回 `null`。
  Message? getById(String id) {
    for (final Message message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  // ——————————————————————— Hive 读写 ———————————————————————

  /// 从 `messages` Box 载入全部消息。
  ///
  /// **替换**内存列表（不是累加）；解析失败的单条数据被跳过。
  /// 载入后顺手清掉过期消息（保留 30 天），避免历史的无用数据一直留着。
  Future<void> loadFromStorage() async {
    try {
      final DateTime cutoff =
          DateTime.now().subtract(const Duration(days: kMessageRetentionDays));
      final Map<dynamic, dynamic> raw = StorageService.messagesBox.toMap();
      final List<Message> kept = <Message>[];
      final List<String> expiredIds = <String>[];

      raw.forEach((dynamic key, dynamic value) {
        if (key is! String || value is! String) return;
        final Message? message = _decode(value);
        if (message == null) return;
        // 过期的直接不载入内存，并记下来准备从 Box 删掉
        if (message.createdAt.isBefore(cutoff)) {
          expiredIds.add(message.id);
        } else {
          kept.add(message);
        }
      });

      _messages
        ..clear()
        ..addAll(kept);
      _sortDescending();
      _loaded = true;

      if (expiredIds.isNotEmpty) {
        debugPrint('MessageProvider: 清理 ${expiredIds.length} 条过期消息');
        await _deleteFromStorage(expiredIds);
      }
      _notify();
    } catch (error, stackTrace) {
      _loaded = true;
      debugPrint('MessageProvider.loadFromStorage 失败（按无消息处理）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 落盘单条消息（**先落盘再更新内存**，与 `CourseProvider` 一致）。
  ///
  /// 落盘失败仍更新内存：本次会话的提示不该因为存储问题而丢。
  Future<void> addMessagePersisted(Message m) async {
    try {
      await StorageService.messagesBox.put(m.id, jsonEncode(m.toJson()));
    } catch (error, stackTrace) {
      debugPrint('MessageProvider.addMessagePersisted(${m.id}) 落盘失败: $error');
      debugPrint('$stackTrace');
    }
    addMessage(m);
  }

  /// 把"全部已读"落盘。
  Future<void> markAllAsReadPersisted() async {
    markAllAsRead();
    await _persistAll();
  }

  /// 把单条已读落盘。
  Future<void> markAsReadPersisted(String id) async {
    markAsRead(id);
    final Message? m = getById(id);
    if (m == null) return;
    try {
      await StorageService.messagesBox.put(id, jsonEncode(m.toJson()));
    } catch (error, stackTrace) {
      debugPrint('MessageProvider.markAsReadPersisted($id) 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 删除单条（内存 + 存储）。
  Future<void> removeMessagePersisted(String id) async {
    removeMessage(id);
    await _deleteFromStorage(<String>[id]);
  }

  /// 清空全部（内存 + 存储）。
  Future<void> clearAll() async {
    clear();
    try {
      await StorageService.messagesBox.clear();
    } catch (error, stackTrace) {
      debugPrint('MessageProvider.clearAll 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 把当前内存里的全部消息写回存储（用于批量改状态，如全部已读）。
  Future<void> _persistAll() async {
    try {
      final box = StorageService.messagesBox;
      for (final Message m in _messages) {
        await box.put(m.id, jsonEncode(m.toJson()));
      }
    } catch (error, stackTrace) {
      debugPrint('MessageProvider._persistAll 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 从存储删除若干 key；失败只记日志。
  Future<void> _deleteFromStorage(Iterable<String> ids) async {
    try {
      final box = StorageService.messagesBox;
      for (final String id in ids) {
        await box.delete(id);
      }
    } catch (error, stackTrace) {
      debugPrint('MessageProvider._deleteFromStorage 落盘失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 解析存进 Box 的 JSON；坏数据返回 `null`（跳过该条）。
  static Message? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = <String, dynamic>{};
      decoded.forEach((dynamic k, dynamic v) {
        if (k != null) json['$k'] = v;
      });
      final Message message = Message.fromJson(json);
      // 没有 id 的消息无法被定位/删除，视为坏数据
      return message.id.isEmpty ? null : message;
    } catch (error) {
      debugPrint('MessageProvider: 跳过无法解析的消息数据: $error');
      return null;
    }
  }

  // ——————————————— 纯内存操作（不落盘） ———————————————
  // 供 loadFromStorage / 测试 / 临时预览使用；业务侧请用上面带 Persisted 的方法。

  /// 新增消息；同 id 已存在则替换。
  ///
  /// 插入后立即重排，保证 [messages] 始终倒序。
  void addMessage(Message m) {
    final int index = _indexOf(m.id);
    if (index >= 0) {
      _messages[index] = m;
    } else {
      _messages.add(m);
    }
    _sortDescending();
    _notify();
  }

  /// 标记单条消息为已读。找不到该 id 或已是已读时为空操作。
  void markAsRead(String id) {
    final int index = _indexOf(id);
    if (index < 0) return;
    if (_messages[index].read) return;
    _messages[index] = _messages[index].copyWith(read: true);
    _notify();
  }

  /// 全部标记为已读。没有未读消息时为空操作。
  void markAllAsRead() {
    if (unreadCount == 0) return;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].isUnread) {
        _messages[i] = _messages[i].copyWith(read: true);
      }
    }
    _notify();
  }

  /// 删除超过 [kMessageRetentionDays] 天的消息（内存 + 存储）。
  ///
  /// [now] 便于测试注入固定时间；不传则用 `DateTime.now()`。
  /// 返回被删除的消息数量；没有可删的则不落盘也不通知。
  ///
  /// **Phase 7**：从"纯内存"改为**同时落盘**——否则"清理了但没删 Box"，
  /// 下次启动过期消息又回来了。
  Future<int> clearOldMessages({DateTime? now}) async {
    final DateTime reference = now ?? DateTime.now();
    final DateTime cutoff =
        reference.subtract(const Duration(days: kMessageRetentionDays));
    final List<String> expiredIds = <String>[
      for (final Message m in _messages)
        if (m.createdAt.isBefore(cutoff)) m.id,
    ];
    if (expiredIds.isEmpty) return 0;

    _messages.removeWhere((Message m) => expiredIds.contains(m.id));
    _notify();
    await _deleteFromStorage(expiredIds);
    return expiredIds.length;
  }

  /// 删除单条消息。
  void removeMessage(String id) {
    final int index = _indexOf(id);
    if (index < 0) return;
    _messages.removeAt(index);
    _notify();
  }

  /// 清空全部消息。
  void clear() {
    if (_messages.isEmpty) return;
    _messages.clear();
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

  /// 按创建时间倒序排列（新的在前）；时间相同时按 id 稳定排序，
  /// 避免同一毫秒插入的多条消息顺序抖动。
  void _sortDescending() {
    _messages.sort((Message a, Message b) {
      final int byTime = b.createdAt.compareTo(a.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
  }

  int _indexOf(String id) {
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].id == id) return i;
    }
    return -1;
  }
}
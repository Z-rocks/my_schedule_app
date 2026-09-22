// 消息状态：管理通知消息列表，维护已读状态并清理过期消息
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/message.dart';

/// 消息保留天数：超过这个天数的消息由 [MessageProvider.clearOldMessages] 清理。
const int kMessageRetentionDays = 30;

/// 消息列表状态。
///
/// 消息由本地通知服务（Phase 7）或插件产生；Phase 1 只做内存状态。
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

  /// 删除超过 [kMessageRetentionDays] 天的消息。
  ///
  /// [now] 便于测试注入固定时间；不传则用 `DateTime.now()`。
  /// 返回被删除的消息数量；没有可删的则不通知。
  int clearOldMessages({DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime cutoff =
        reference.subtract(const Duration(days: kMessageRetentionDays));
    final int before = _messages.length;
    _messages.removeWhere((Message m) => m.createdAt.isBefore(cutoff));
    final int removed = before - _messages.length;
    if (removed > 0) _notify();
    return removed;
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
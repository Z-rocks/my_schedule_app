// 消息页：列出真实消息，支持已读标记、删除与下拉刷新
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message.dart';
import '../../providers/message_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 消息页。
///
/// **Phase 1.5 是空态骨架；Phase 7 起接真实数据**：
/// 列表来自 `MessageProvider`（已从 Hive 载入），"全部已读"是真的写状态，
/// 单条可左滑删除，下拉可刷新（并顺带清掉超过 30 天的旧消息）。
class MessageView extends StatelessWidget {
  const MessageView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final MessageProvider provider = context.watch<MessageProvider>();
    final List<Message> messages = provider.messages;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('消息'),
        centerTitle: true,
        actions: <Widget>[
          if (messages.isNotEmpty)
            TextButton(
              onPressed: provider.unreadCount == 0
                  ? null
                  : () => _markAllAsRead(context, provider),
              child: Text(
                provider.unreadCount == 0
                    ? '已全部已读'
                    : '全部已读(${provider.unreadCount})',
                style: TextStyle(
                  fontSize: theme.bodySize,
                  // 没有未读时置灰：可点的按钮与不可点的看起来必须不一样
                  color: provider.unreadCount == 0
                      ? theme.onPrimary.withValues(alpha: 0.5)
                      : theme.onPrimary,
                ),
              ),
            ),
        ],
      ),
      body: messages.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: '暂无消息',
              subtitle: '同步结果与插件提醒会出现在这里',
            )
          : RefreshIndicator(
              color: theme.primary,
              onRefresh: () => _refresh(context, provider),
              child: ListView.builder(
                padding: EdgeInsets.all(theme.cardPadding),
                itemCount: messages.length,
                itemBuilder: (BuildContext context, int index) {
                  final Message message = messages[index];
                  return Dismissible(
                    // key 必须稳定且唯一：用消息 id，不用下标
                    key: ValueKey<String>('msg-${message.id}'),
                    direction: DismissDirection.endToStart,
                    background: _DismissBackground(theme: theme),
                    onDismissed: (DismissDirection _) =>
                        _delete(context, provider, message),
                    child: _MessageCard(
                      message: message,
                      onTap: () => _openMessage(context, provider, message),
                    ),
                  );
                },
              ),
            ),
    );
  }

  /// 全部已读（内存 + 落盘）。
  static Future<void> _markAllAsRead(
    BuildContext context,
    MessageProvider provider,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await provider.markAllAsReadPersisted();
    messenger.showSnackBar(
      const SnackBar(content: Text('已全部标记为已读')),
    );
  }

  /// 下拉刷新：重新从存储读一遍，并顺手清理过期消息。
  static Future<void> _refresh(
    BuildContext context,
    MessageProvider provider,
  ) async {
    final int removed = await provider.clearOldMessages();
    await provider.loadFromStorage();
    if (!context.mounted) return;
    if (removed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 $removed 条过期消息')),
      );
    }
  }

  /// 点一条消息：标为已读。
  ///
  /// 不做"跳转到对应条目"——`Message.targetId` 目前没有产生方
  /// （插件通知不带目标，内核同步消息也不指向单条课程）。
  /// 等真有带目标的来源再加跳转，避免写一条永远走不到的分支。
  static Future<void> _openMessage(
    BuildContext context,
    MessageProvider provider,
    Message message,
  ) async {
    if (message.read) return;
    await provider.markAsReadPersisted(message.id);
  }

  static Future<void> _delete(
    BuildContext context,
    MessageProvider provider,
    Message message,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await provider.removeMessagePersisted(message.id);
    messenger.showSnackBar(
      SnackBar(content: Text('已删除「${message.title}」')),
    );
  }
}

/// 左滑删除时的背景。
class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.only(right: theme.cardPadding * 1.5),
      margin: EdgeInsets.only(bottom: theme.gridGap * 2),
      decoration: BoxDecoration(
        color: theme.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      child: Icon(Icons.delete_outline, color: theme.error),
    );
  }
}

/// 单条消息卡片。
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final bool unread = message.isUnread;

    return Card(
      margin: EdgeInsets.only(bottom: theme.gridGap * 2),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        // 未读描一圈主色边：比只靠"未读小圆点"更容易扫到
        side: unread
            ? BorderSide(color: theme.primary.withValues(alpha: 0.5))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_iconFor(message.type), color: _colorFor(message.type, theme)),
              SizedBox(width: theme.cardPadding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            message.title,
                            style: TextStyle(
                              fontSize: theme.bodySize,
                              // 未读用标题字重，已读用常规 —— 一眼能分出
                              fontWeight:
                                  unread ? theme.titleFontWeight : null,
                              color: theme.onBackground,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: theme.gridGap * 2,
                            height: theme.gridGap * 2,
                            decoration: BoxDecoration(
                              color: theme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (message.body.isNotEmpty) ...<Widget>[
                      SizedBox(height: theme.gridGap),
                      Text(
                        message.body,
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    SizedBox(height: theme.gridGap),
                    Text(
                      '${message.type.label} · ${_formatTime(message.createdAt)}',
                      style: TextStyle(
                        fontSize: theme.captionSize,
                        color: theme.onBackground.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 消息类型 → 图标。
  static IconData _iconFor(MessageType type) {
    switch (type) {
      case MessageType.course:
        return Icons.calendar_month;
      case MessageType.exam:
        return Icons.assignment_outlined;
      case MessageType.homework:
        return Icons.edit_note;
      case MessageType.grade:
        return Icons.bar_chart;
      case MessageType.system:
        return Icons.sync;
      case MessageType.other:
        return Icons.notifications_none;
    }
  }

  /// 消息类型 → 强调色（全部取自主题令牌，不硬编码）。
  static Color _colorFor(MessageType type, AppTheme theme) {
    switch (type) {
      case MessageType.exam:
        return theme.examHighlight;
      case MessageType.homework:
        return theme.homeworkHighlight;
      case MessageType.grade:
        return theme.success;
      case MessageType.course:
      case MessageType.system:
      case MessageType.other:
        return theme.primary;
    }
  }

  /// 相对时间：`刚刚` / `N 分钟前` / `N 小时前` / `昨天` / `M月d日`。
  ///
  /// 不引入 `intl`：它虽然在 pubspec 里，但项目至今没用过（`formatDateYmd`
  /// 也是手写的），为一句相对时间引入格式化体系不划算。
  static String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24 && time.day == now.day) {
      return '${diff.inHours} 小时前';
    }
    final DateTime yesterday = now.subtract(const Duration(days: 1));
    if (time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day) {
      return '昨天';
    }
    return '${time.month}月${time.day}日';
  }
}

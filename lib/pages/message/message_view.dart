// 消息页（空态骨架）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';

/// 消息页。
///
/// **Phase 1.5 只做空态骨架**：不接 `MessageProvider`，也不做真实的已读标记。
/// 消息列表与已读状态在 Phase 7（通知 + 消息）接入。
class MessageView extends StatelessWidget {
  const MessageView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('消息'),
        centerTitle: true,
        actions: <Widget>[
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已全部标记为已读')),
            ),
            child: Text(
              '全部已读',
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: const EmptyState(
        icon: Icons.notifications_none,
        title: '暂无消息',
      ),
    );
  }
}
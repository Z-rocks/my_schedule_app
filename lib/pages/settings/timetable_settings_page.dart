// 课表设置页（Phase 1.6 占位：控件可用但不保存）
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';

/// 每节高度的可调范围（逻辑像素）。
const double kMinCellHeight = 40;
const double kMaxCellHeight = 100;

/// 课表设置页。
///
/// **Phase 1.6 只做交互占位**：控件能操作（改内部 state），但不写入任何存储，
/// 退出页面即丢失。Phase 2 接入 Hive 后会把这些值落到 `settings` Box 并驱动
/// `AppTheme` 的 `showWeekend` / `timetableCellHeight`。
class TimetableSettingsPage extends StatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  State<TimetableSettingsPage> createState() => _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends State<TimetableSettingsPage> {
  bool _showWeekend = true;
  bool _showSessionTime = true;
  double _cellHeight = 60;

  void _showPending() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('（待实现）')));
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('课表设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: theme.sectionGap),
        children: <Widget>[
          SwitchListTile(
            title: Text(
              '显示周末',
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
            value: _showWeekend,
            activeThumbColor: theme.primary,
            onChanged: (bool value) {
              setState(() => _showWeekend = value);
              _showPending();
            },
          ),
          SwitchListTile(
            title: Text(
              '显示节次时间',
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
            value: _showSessionTime,
            activeThumbColor: theme.primary,
            onChanged: (bool value) {
              setState(() => _showSessionTime = value);
              _showPending();
            },
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.cardPadding,
              vertical: theme.cardPadding / 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      '每节高度',
                      style: TextStyle(
                        fontSize: theme.bodySize,
                        color: theme.onBackground,
                      ),
                    ),
                    Text(
                      '${_cellHeight.round()}',
                      style: TextStyle(
                        fontSize: theme.bodySize,
                        color: theme.onBackground.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _cellHeight,
                  min: kMinCellHeight,
                  max: kMaxCellHeight,
                  divisions: ((kMaxCellHeight - kMinCellHeight) / 10).round(),
                  activeColor: theme.primary,
                  onChanged: (double value) => setState(() => _cellHeight = value),
                  onChangeEnd: (double _) => _showPending(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
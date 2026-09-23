// 课表设置页（Phase 1.6 占位：控件可用但不保存）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/semester_provider.dart';
import '../../providers/settings_provider.dart';
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

  /// 每节高度。
  ///
  /// 初值取自 [AppTheme.timetableCellHeight]（见 [didChangeDependencies]），
  /// 这里先给一个范围下限占位——首次 build 之前就会被主题值覆盖。
  double _cellHeight = kMinCellHeight;

  /// 是否已经从主题读取过初值。
  ///
  /// [didChangeDependencies] 会在依赖变化时**重复**触发（例如切换皮肤导致
  /// Theme 变化），用它保证主题值只在首次生效，之后一律以用户拖动为准。
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    // 不能放在 initState：那里拿不到 InheritedWidget（Theme 还没准备好）。
    _cellHeight = AppThemeExtension.of(context)
        .timetableCellHeight
        .clamp(kMinCellHeight, kMaxCellHeight);
  }

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
          // 学期配置入口（Phase 2.2c 做真实页面）
          ListTile(
            title: Text(
              '学期配置',
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
            subtitle: Text(
              context.watch<SemesterProvider>().config?.name ?? '未配置',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.onBackground.withValues(alpha: 0.4),
            ),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('学期配置页待实现（Phase 2.2c）')),
            ),
          ),
          // 左右滑动切换周次（Phase 2.2b.1）
          SwitchListTile(
            title: Text(
              '左右滑动切换周次',
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
            subtitle: Text(
              '在课表页左右滑动切换周次',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
            value: context.watch<SettingsProvider>().gestureSwitchWeek,
            activeThumbColor: theme.primary,
            onChanged: (bool value) => context
                .read<SettingsProvider>()
                .setGestureSwitchWeek(value),
          ),
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
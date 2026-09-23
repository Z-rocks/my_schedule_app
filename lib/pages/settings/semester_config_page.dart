// 学期配置页：编辑唯一的学期（名称 / 第 1 周周一 / 总周数 / 备注）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/semester_config.dart';
import '../../providers/semester_provider.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/timetable_grid.dart' show kWeekdayLabels;

/// 总周数可选范围。
///
/// 下限 4 而不是 10：军训、小学期、暑期课程等短学期可能只有几周
/// （Phase 2.2c.1 修正时放宽，避免把这类配置强行收进 10 周）。
const int kMinTotalWeeks = 4;
const int kMaxTotalWeeks = 30;

/// 学期名称的最大长度（表单校验用）。
const int kMaxSemesterNameLength = 30;

/// 去掉时分秒，只保留年月日。
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 某个日期所在周的周一。
///
/// `DateTime.weekday` 是 1(周一)…7(周日)，所以往回退 `weekday - 1` 天。
DateTime mondayOfWeek(DateTime value) {
  final DateTime day = dateOnly(value);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// `2026年9月7日`。
String formatChineseDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';

/// `2026年9月7日（周一）`。
String formatChineseDateWithWeekday(DateTime value) {
  final int index = value.weekday - 1;
  final String weekday =
      index >= 0 && index < kWeekdayLabels.length ? kWeekdayLabels[index] : '';
  return '${formatChineseDate(value)}（$weekday）';
}

/// 学期配置页。
///
/// 三处入口都跳到这里：设置 → 课表设置 → 学期配置；课表页无学期时的
/// "去配置学期"按钮；课表页顶部"第 N 周"面板里的"编辑学期"。
///
/// 保存成功后 `Navigator.pop(context, true)`；重置（清除）后同样 pop。
class SemesterConfigPage extends StatefulWidget {
  const SemesterConfigPage({super.key});

  @override
  State<SemesterConfigPage> createState() => _SemesterConfigPageState();
}

class _SemesterConfigPageState extends State<SemesterConfigPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late DateTime _startDate;
  late int _totalWeeks;

  @override
  void initState() {
    super.initState();
    // read（不是 watch）：只在进入页面时取一次初值，之后以表单状态为准。
    final SemesterConfig? existing = context.read<SemesterProvider>().config;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    // 没配置过时默认"本周一"
    _startDate = existing == null
        ? mondayOfWeek(DateTime.now())
        : dateOnly(existing.startDate);
    // 滑杆范围是 kMinTotalWeeks–kMaxTotalWeeks，历史数据若超出范围会被收进区间
    _totalWeeks = (existing?.totalWeeks ?? 20)
        .clamp(kMinTotalWeeks, kMaxTotalWeeks)
        .toInt();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 当前表单对应的结束日期（派生，不单独存）。
  DateTime get _endDate =>
      _startDate.add(Duration(days: _totalWeeks * kDaysPerWeek - 1));

  /// 用表单当前值构造一个临时配置，供预览计算使用。
  SemesterConfig get _draftConfig => SemesterConfig(
        name: _nameController.text.trim(),
        startDate: _startDate,
        totalWeeks: _totalWeeks,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

  Future<void> _pickStartDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      // 过去 5 年 ~ 未来 5 年
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: '选择第 1 周的周一',
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = dateOnly(picked));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 在 await 之前取好依赖 context 的对象，避免跨异步间隙使用 context。
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final SemesterProvider provider = context.read<SemesterProvider>();

    await provider.save(_draftConfig);
    if (!mounted) return;

    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('学期配置已保存')));
  }

  Future<void> _reset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清除学期配置'),
        content: const Text('确定要清除学期配置吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final SemesterProvider provider = context.read<SemesterProvider>();
    await provider.clear();
    if (!mounted) return;
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final bool hasConfig = context.watch<SemesterProvider>().hasConfig;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('学期配置'),
        centerTitle: true,
        actions: <Widget>[
          if (hasConfig)
            TextButton(
              onPressed: _reset,
              child: Text(
                '重置',
                style: TextStyle(
                  fontSize: theme.bodySize,
                  color: theme.error,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(theme.cardPadding * 1.5),
          children: <Widget>[
            // —— 学期名称 ——
            TextFormField(
              controller: _nameController,
              maxLength: kMaxSemesterNameLength,
              decoration: InputDecoration(
                labelText: '学期名称',
                hintText: '如：2026-2027学年第一学期',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(fontSize: theme.bodySize),
              validator: (String? value) {
                final String text = (value ?? '').trim();
                if (text.isEmpty) return '请输入学期名称';
                if (text.length > kMaxSemesterNameLength) {
                  return '学期名称不能超过 $kMaxSemesterNameLength 个字';
                }
                return null;
              },
            ),
            SizedBox(height: theme.sectionGap),

            // —— 开始日期（点击选择）——
            _FieldLabel(theme: theme, text: '开始日期（第 1 周周一）'),
            _TapField(
              theme: theme,
              icon: Icons.calendar_month,
              text: formatChineseDateWithWeekday(_startDate),
              onTap: _pickStartDate,
            ),
            SizedBox(height: theme.sectionGap),

            // —— 总周数 ——
            _FieldLabel(theme: theme, text: '总周数'),
            Row(
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: _totalWeeks.toDouble(),
                    min: kMinTotalWeeks.toDouble(),
                    max: kMaxTotalWeeks.toDouble(),
                    divisions: kMaxTotalWeeks - kMinTotalWeeks,
                    label: '$_totalWeeks 周',
                    activeColor: theme.primary,
                    onChanged: (double value) =>
                        setState(() => _totalWeeks = value.round()),
                  ),
                ),
                SizedBox(
                  width: theme.timetableTimeColumnWidth + theme.cardPadding,
                  child: Text(
                    '$_totalWeeks 周',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: theme.bodySize,
                      color: theme.onBackground,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.sectionGap),

            // —— 结束日期（派生，只读）——
            _FieldLabel(theme: theme, text: '结束日期'),
            _TapField(
              theme: theme,
              icon: Icons.event_available,
              text: formatChineseDate(_endDate),
              onTap: null,
            ),
            SizedBox(height: theme.sectionGap),

            // —— 备注 ——
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '备注（可选）',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(fontSize: theme.bodySize),
            ),
            SizedBox(height: theme.sectionGap),

            // —— 预览 ——
            _PreviewCard(theme: theme, text: _previewText()),
            SizedBox(height: theme.sectionGap * 1.5),

            // —— 底部按钮 ——
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                SizedBox(width: theme.gridGap * 2),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: theme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 预览文案：尚未开始 / 当前第 N 周 / 学期已结束。
  String _previewText() {
    final SemesterConfig draft = _draftConfig;
    final DateTime today = dateOnly(DateTime.now());

    if (today.isBefore(dateOnly(draft.startDate))) {
      return '学期尚未开始（${formatChineseDate(draft.startDate)} 起）';
    }
    if (today.isAfter(dateOnly(draft.endDate))) {
      return '学期已结束';
    }
    final int week = TimetableLogic.currentWeek(draft, now: today);
    return '当前是第 $week 周';
  }
}

/// 字段上方的小标题。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          fontWeight: theme.titleFontWeight,
          color: theme.primary,
        ),
      ),
    );
  }
}

/// 只读/可点击的一行值（用于日期）。
class _TapField extends StatelessWidget {
  const _TapField({
    required this.theme,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final AppTheme theme;
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(theme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: theme.cardPadding,
            vertical: theme.cardPadding,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: theme.bodySize + 4, color: theme.primary),
              SizedBox(width: theme.gridGap * 2),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    color: theme.onBackground,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.edit_outlined,
                  size: theme.bodySize,
                  color: theme.onBackground.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 预览卡片。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.cardShadowColor,
            blurRadius: theme.cardShadowBlur,
            offset: Offset(0, theme.cardShadowOffsetY),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: theme.bodySize, color: theme.primary),
          SizedBox(width: theme.gridGap * 2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: theme.bodySize,
                color: theme.onBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
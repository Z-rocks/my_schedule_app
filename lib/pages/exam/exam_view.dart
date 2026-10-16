// 考试安排页（Phase 8：接入真实数据）。
//
// 数据来源：[ExamProvider.displayExams]（已过滤隐藏、按开考时间排序）。
// 抓取入口指向 [PluginEntitySyncPage]（与作业页共用同一个页面）。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../models/plugin_course_ref.dart';
import '../../providers/exam_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../services/plugin_entity_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../sync/plugin_entity_sync_page.dart';

/// 考试安排页。
class ExamView extends StatelessWidget {
  const ExamView({super.key});

  /// 打开"按课程勾选后抓取考试"的页面。
  ///
  /// 考试没有"正文"概念，所以不开 [PluginEntitySyncPage.showContentToggle]。
  static Future<void> openSyncPage(BuildContext context) async {
    final ExamProvider provider = context.read<ExamProvider>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PluginEntitySyncPage(
          capability: 'exam',
          title: '抓取考试',
          itemLabel: '考试',
          itemUnit: '场',
          run: ({
            required String pluginId,
            required PluginHandle? handle,
            required List<PluginCourseRef> refs,
            required bool withContent,
            void Function(String stage, String message)? onProgress,
          }) {
            return PluginEntitySyncService.sync<Exam>(
              pluginId: pluginId,
              handle: handle,
              spec: PluginEntitySyncService.examSpec(),
              store: provider,
              args: PluginEntitySyncService.buildCoursesArgs(refs),
              onProgress: onProgress,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final ExamProvider provider = context.watch<ExamProvider>();
    final List<Exam> exams = provider.displayExams;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('考试'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: '抓取考试',
            onPressed: () => openSyncPage(context),
          ),
        ],
      ),
      body: exams.isEmpty
          ? EmptyState(
              icon: Icons.assignment_outlined,
              title: '暂无考试安排',
              subtitle: '登录学习通后，按课程勾选即可抓取考试时间',
              actionLabel: '抓取考试',
              onAction: () => openSyncPage(context),
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: exams.length,
              itemBuilder: (BuildContext context, int index) =>
                  _ExamCard(exam: exams[index]),
            ),
    );
  }
}

/// 单张考试卡片。
class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final DateTime now = DateTime.now();
    final bool started = exam.hasStarted(now);
    final String note = exam.displayNote;

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context, exam),
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      exam.displayName,
                      style: TextStyle(
                        fontSize: theme.titleSize,
                        fontWeight: theme.titleFontWeight,
                        // 已开考的条目压暗：它不再需要用户的注意力。
                        color: started
                            ? theme.onBackground.withValues(alpha: 0.55)
                            : theme.onBackground,
                      ),
                    ),
                  ),
                  SizedBox(width: theme.gridGap),
                  _CountdownChip(exam: exam, now: now),
                ],
              ),
              if (exam.courseName.isNotEmpty) ...<Widget>[
                SizedBox(height: theme.gridGap / 2),
                Text(
                  exam.courseName,
                  style: TextStyle(
                    fontSize: theme.captionSize,
                    color: theme.onBackground.withValues(alpha: 0.65),
                  ),
                ),
              ],
              SizedBox(height: theme.gridGap),
              _metaRow(
                theme,
                Icons.schedule_outlined,
                _timeRangeText(exam),
              ),
              if (exam.displayLocation.isNotEmpty)
                _metaRow(theme, Icons.place_outlined, exam.displayLocation),
              if (note.isNotEmpty)
                _metaRow(
                  theme,
                  Icons.info_outline,
                  note,
                  color: theme.onBackground.withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Exam exam) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeExtension.of(context).surface,
      builder: (BuildContext _) => _ExamDetailSheet(examId: exam.id),
    );
  }
}

/// 倒计时徽章：`还有 12 天` / `今天` / `已开考`。
class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.exam, required this.now});

  final Exam exam;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final int days = exam.daysUntil(now);
    final bool started = exam.hasStarted(now);
    final bool urgent = !started && days <= 3;

    final String label = started
        ? '已开考'
        : (days == 0 ? '今天' : '还有 $days 天');
    final Color color = started
        ? theme.onBackground.withValues(alpha: 0.5)
        : (urgent ? theme.error : theme.examHighlight);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: theme.gridGap * 1.5,
        vertical: theme.gridGap / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(theme.chipRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: theme.captionSize,
          fontWeight: theme.titleFontWeight,
          color: color,
        ),
      ),
    );
  }
}

/// 考试详情弹层。通过 id 重新取数据，保证隐藏等操作后状态即时刷新。
class _ExamDetailSheet extends StatelessWidget {
  const _ExamDetailSheet({required this.examId});

  final String examId;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final ExamProvider provider = context.watch<ExamProvider>();
    final Exam? exam = provider.getById(examId);

    if (exam == null) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding * 2),
          child: Text(
            '该考试已不存在',
            style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
          ),
        ),
      );
    }

    final DateTime now = DateTime.now();
    final List<Widget> rows = <Widget>[
      if (exam.courseName.isNotEmpty)
        _detailRow(theme, '课程', exam.courseName),
      _detailRow(theme, '考试时间', _timeRangeText(exam)),
      _detailRow(theme, '倒计时',
          exam.hasStarted(now) ? '已开考' : '还有 ${exam.daysUntil(now)} 天'),
      if (exam.displayLocation.isNotEmpty)
        _detailRow(theme, '考场', exam.displayLocation),
      if (exam.seatNumber.isNotEmpty) _detailRow(theme, '座位', exam.seatNumber),
      if (exam.examType.isNotEmpty) _detailRow(theme, '形式', exam.examType),
      if (exam.durationMinutes > 0)
        _detailRow(theme, '时长', '${exam.durationMinutes} 分钟'),
      if (exam.displayNote.isNotEmpty) _detailRow(theme, '备注', exam.displayNote),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          theme.cardPadding,
          theme.gridGap * 2,
          theme.cardPadding,
          theme.cardPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: theme.cardPadding * 1.5,
                height: theme.gridGap / 1.5,
                decoration: BoxDecoration(
                  color: theme.onBackground.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(theme.chipRadius),
                ),
              ),
            ),
            SizedBox(height: theme.cardPadding),
            Text(
              exam.displayName,
              style: TextStyle(
                fontSize: theme.titleSize,
                fontWeight: theme.titleFontWeight,
                color: theme.onBackground,
              ),
            ),
            SizedBox(height: theme.sectionGap),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                ),
              ),
            ),
            SizedBox(height: theme.sectionGap),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.visibility_off_outlined,
                    size: theme.captionSize * 1.2),
                label: const Text('隐藏这场考试'),
                onPressed: () {
                  provider.setHidden(exam.id, true);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 小组件 / 文案工具 ─────────────────────────

/// 卡片上的一行"图标 + 文本"。
Widget _metaRow(AppTheme theme, IconData icon, String text, {Color? color}) {
  final Color effective = color ?? theme.onBackground.withValues(alpha: 0.8);
  return Padding(
    padding: EdgeInsets.only(top: theme.gridGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: theme.captionSize * 1.2, color: effective),
        SizedBox(width: theme.gridGap),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: theme.captionSize, color: effective),
          ),
        ),
      ],
    ),
  );
}

/// 详情弹层里的一行"标签 : 值"。
Widget _detailRow(AppTheme theme, String label, String value) {
  return Padding(
    padding: EdgeInsets.only(top: theme.gridGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: theme.captionSize * 4.5,
          child: Text(
            label,
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: theme.captionSize, color: theme.onBackground),
          ),
        ),
      ],
    ),
  );
}

/// 考试时间文案：`2026-09-18 09:00 ~ 2027-01-08 16:00`。
///
/// 结束时间缺失时只显示开始时间（`Exam.effectiveEndTime` 会拿时长兜底，
/// 但时长也未知时不该硬凑一个时间出来）。
String _timeRangeText(Exam exam) {
  final String start = _formatDateTime(exam.displayStartTime);
  final DateTime? end = exam.endTime;
  if (end == null) return start;
  return '$start ~ ${_formatDateTime(end)}';
}

/// `2026-09-18 09:00`。手写而不是用 `intl`：只此一处需要，
/// 且固定格式不依赖 locale 数据。
String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

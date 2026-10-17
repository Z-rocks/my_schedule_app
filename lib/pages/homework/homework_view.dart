// 作业页（Phase 8：接入真实数据）。
//
// 数据来源：[HomeworkProvider.displayHomeworks]（已过滤隐藏、按截止时间排序）。
// 抓取入口指向 [PluginEntitySyncPage]——"先列课程、勾选、再抓"，
// 原因是学习通有反爬，不能默认全量抓（详见该页文件头）。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/homework.dart';
import '../../models/plugin_course_ref.dart';
import '../../providers/homework_provider.dart';
import '../../runtime/plugin_handle.dart';
import '../../services/plugin_entity_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/empty_state.dart';
import '../sync/plugin_entity_sync_page.dart';
import 'hidden_homeworks_page.dart';

/// 作业页。
class HomeworkView extends StatelessWidget {
  const HomeworkView({super.key});

  /// 打开"按课程勾选后抓取作业"的页面。
  ///
  /// 这里把"作业"这一侧的所有差异（能力 ID、量词、正文开关、怎么落盘）
  /// 一次性交给通用选择页，页面本身不需要认识 `HomeworkProvider`。
  static Future<void> openSyncPage(BuildContext context) async {
    final HomeworkProvider provider = context.read<HomeworkProvider>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => PluginEntitySyncPage(
          capability: 'homework',
          title: '抓取作业',
          itemLabel: '作业',
          itemUnit: '份',
          showContentToggle: true,
          contentToggleLabel: '同时抓取作业正文（题目）',
          contentToggleHint: '学习通在打开作业正文时会留下"已开始作答"的记录。'
              '只关心截止时间的话可以关掉它。',
          run: ({
            required String pluginId,
            required PluginHandle? handle,
            required List<PluginCourseRef> refs,
            required bool withContent,
            void Function(String stage, String message)? onProgress,
          }) {
            return PluginEntitySyncService.sync<Homework>(
              pluginId: pluginId,
              handle: handle,
              spec: PluginEntitySyncService.homeworkSpec(),
              store: provider,
              args: PluginEntitySyncService.buildCoursesArgs(
                refs,
                withContent: withContent,
              ),
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
    final HomeworkProvider provider = context.watch<HomeworkProvider>();
    final List<Homework> homeworks = provider.displayHomeworks;
    final int hiddenCount = provider.hiddenCount;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('作业'),
        centerTitle: true,
        actions: <Widget>[
          // 隐藏作业的恢复入口。**只有存在隐藏项时才出现**：
          // 没有隐藏项时摆一个空入口是噪音；而一旦有隐藏项，它就是
          // 用户唯一的找回路径——缺了它，"隐藏"等于"删除"。
          if (hiddenCount > 0)
            IconButton(
              icon: const Icon(Icons.visibility_off_outlined),
              tooltip: '已隐藏 $hiddenCount 份作业',
              onPressed: () => _openHidden(context),
            ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: '抓取作业',
            onPressed: () => openSyncPage(context),
          ),
        ],
      ),
      // 空列表有两种截然不同的原因，不能都显示"暂无作业"：
      // 一种是真没有作业，另一种是**全被隐藏了**——后者必须给出恢复入口，
      // 否则用户会以为数据丢了。
      body: homeworks.isEmpty
          ? EmptyState(
              icon: hiddenCount > 0
                  ? Icons.visibility_off_outlined
                  : Icons.edit_note,
              title: hiddenCount > 0 ? '作业都已隐藏' : '暂无作业',
              subtitle: hiddenCount > 0
                  ? '共 $hiddenCount 份作业被隐藏，可以随时恢复'
                  : '登录学习通后，按课程勾选即可抓取作业与截止时间',
              actionLabel: hiddenCount > 0 ? '查看已隐藏' : '抓取作业',
              onAction: hiddenCount > 0
                  ? () => _openHidden(context)
                  : () => openSyncPage(context),
            )
          : ListView.builder(
              padding: EdgeInsets.all(theme.cardPadding),
              itemCount: homeworks.length,
              itemBuilder: (BuildContext context, int index) =>
                  _HomeworkCard(homework: homeworks[index]),
            ),
    );
  }

  /// 打开「已隐藏的作业」页。
  static void _openHidden(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const HiddenHomeworksPage(),
      ),
    );
  }
}

/// 单张作业卡片。
class _HomeworkCard extends StatelessWidget {
  const _HomeworkCard({required this.homework});

  final Homework homework;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final DateTime now = DateTime.now();
    final bool overdue = homework.isOverdue(now);
    final bool done = homework.isCompleted;
    final String preview = _firstLine(homework.description);

    return Card(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      color: theme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context, homework),
        child: Padding(
          padding: EdgeInsets.all(theme.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 完成勾选：状态写进覆盖层，插件重新同步不会把它冲掉。
              Checkbox(
                value: done,
                activeColor: theme.success,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (bool? value) => context
                    .read<HomeworkProvider>()
                    .setCompleted(homework.id, value ?? false),
              ),
              SizedBox(width: theme.gridGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      homework.displayTitle,
                      style: TextStyle(
                        fontSize: theme.titleSize,
                        fontWeight: theme.titleFontWeight,
                        color: theme.onBackground,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: theme.onBackground.withValues(alpha: 0.5),
                      ),
                    ),
                    if (homework.courseName.isNotEmpty) ...<Widget>[
                      SizedBox(height: theme.gridGap / 2),
                      Text(
                        homework.courseName,
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                    SizedBox(height: theme.gridGap),
                    _DeadlineRow(
                      deadline: homework.displayDeadline,
                      now: now,
                      overdue: overdue,
                      done: done,
                    ),
                    if (preview.isNotEmpty) ...<Widget>[
                      SizedBox(height: theme.gridGap),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: theme.captionSize,
                          color: theme.onBackground.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出作业详情（正文可能很长，所以是可滚动的弹层）。
  void _showDetail(BuildContext context, Homework homework) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeExtension.of(context).surface,
      builder: (BuildContext sheetContext) => _HomeworkDetailSheet(
        homeworkId: homework.id,
      ),
    );
  }
}

/// 截止时间行：图标 + 绝对时间 + 相对提示，逾期用警告色。
class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({
    required this.deadline,
    required this.now,
    required this.overdue,
    required this.done,
  });

  final DateTime? deadline;
  final DateTime now;
  final bool overdue;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final DateTime? due = deadline;
    final Color color = overdue
        ? theme.error
        : theme.onBackground.withValues(alpha: 0.8);

    return Row(
      children: <Widget>[
        Icon(Icons.schedule_outlined, size: theme.captionSize * 1.2, color: color),
        SizedBox(width: theme.gridGap),
        Expanded(
          child: Text(
            due == null ? '无截止时间' : _deadlineText(due, now, overdue, done),
            style: TextStyle(fontSize: theme.captionSize, color: color),
          ),
        ),
      ],
    );
  }
}

/// 作业详情弹层。
///
/// 通过 id 从 Provider 重新取数据（而不是持有 [Homework] 快照）：
/// 用户在这个弹层里勾选"完成"后，界面要立刻反映新状态。
class _HomeworkDetailSheet extends StatelessWidget {
  const _HomeworkDetailSheet({required this.homeworkId});

  final String homeworkId;

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final HomeworkProvider provider = context.watch<HomeworkProvider>();
    final Homework? homework = provider.getById(homeworkId);

    if (homework == null) {
      // 被删掉 / 卸载插件后的兜底。
      return _sheetShell(
        theme,
        title: '作业已不存在',
        child: const SizedBox.shrink(),
      );
    }

    final DateTime now = DateTime.now();
    final bool done = homework.isCompleted;

    return _sheetShell(
      theme,
      title: homework.displayTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (homework.courseName.isNotEmpty)
            _metaLine(theme, Icons.book_outlined, homework.courseName),
          _metaLine(
            theme,
            Icons.schedule_outlined,
            homework.displayDeadline == null
                ? '无截止时间'
                : _deadlineText(
                    homework.displayDeadline!,
                    now,
                    homework.isOverdue(now),
                    done,
                  ),
          ),
          if (homework.publishTime != null)
            _metaLine(theme, Icons.upload_outlined,
                '发布 ${_formatDateTime(homework.publishTime!)}'),
          if (homework.submitStatus.isNotEmpty)
            _metaLine(theme, Icons.assignment_turned_in_outlined,
                homework.submitStatus),
          SizedBox(height: theme.sectionGap),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(done ? Icons.undo : Icons.check, size: theme.captionSize * 1.2),
                  label: Text(done ? '取消完成' : '标记完成'),
                  onPressed: () => provider.setCompleted(homework.id, !done),
                ),
              ),
              SizedBox(width: theme.gridGap * 2),
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.visibility_off_outlined,
                      size: theme.captionSize * 1.2),
                  label: const Text('隐藏'),
                  onPressed: () {
                    // 先取 messenger：pop 之后本 context 对应的元素已失效，
                    // 但 messenger 属于上层 Scaffold，仍能正常弹提示。
                    final ScaffoldMessengerState messenger =
                        ScaffoldMessenger.of(context);
                    provider.setHidden(homework.id, true);
                    Navigator.of(context).pop();
                    // 隐藏是"看不见结果"的操作，必须告诉用户去哪找回，
                    // 否则在用户看来就等同于删除。
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('已隐藏，可在作业页右上角「已隐藏」里恢复'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),
          Text(
            '作业内容',
            style: TextStyle(
              fontSize: theme.bodySize,
              fontWeight: theme.titleFontWeight,
              color: theme.onBackground,
            ),
          ),
          SizedBox(height: theme.gridGap),
          if (homework.description.trim().isEmpty)
            Text(
              '（没有抓取到正文。可以在抓取时打开「同时抓取作业正文」，'
              '或该作业尚未开放作答。）',
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            )
          else
            Text(
              homework.description,
              style: TextStyle(
                fontSize: theme.captionSize,
                height: 1.6,
                color: theme.onBackground.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}

/// 详情弹层的统一外壳：拖动条 + 标题 + 可滚动内容。
Widget _sheetShell(AppTheme theme, {required String title, required Widget child}) {
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
            title,
            style: TextStyle(
              fontSize: theme.titleSize,
              fontWeight: theme.titleFontWeight,
              color: theme.onBackground,
            ),
          ),
          SizedBox(height: theme.gridGap),
          // 正文可能很长：限制最大高度并允许滚动，避免弹层顶到屏幕外。
          Flexible(
            child: SingleChildScrollView(child: child),
          ),
        ],
      ),
    ),
  );
}

/// 详情弹层里的一行"图标 + 文本"。
Widget _metaLine(AppTheme theme, IconData icon, String text) {
  return Padding(
    padding: EdgeInsets.only(top: theme.gridGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: theme.captionSize * 1.2,
            color: theme.onBackground.withValues(alpha: 0.6)),
        SizedBox(width: theme.gridGap),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: theme.captionSize,
              color: theme.onBackground.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────── 文案工具 ─────────────────────────

/// 截止时间文案：`2026-10-18 23:29 · 还剩 2 天`。
///
/// 相对提示只给"天数"不给时分：作业的紧迫感是天级的，
/// 精确到分钟反而让人频繁刷新（且本地时间与服务器可能差几分钟）。
String _deadlineText(DateTime due, DateTime now, bool overdue, bool done) {
  final String absolute = _formatDateTime(due);
  if (done) return '截止 $absolute';
  if (overdue) {
    final int days = _wholeDaysBetween(due, now);
    return '截止 $absolute · 已逾期${days > 0 ? ' $days 天' : ''}';
  }
  final int days = _wholeDaysBetween(now, due);
  if (days == 0) return '截止 $absolute · 今天';
  return '截止 $absolute · 还剩 $days 天';
}

/// `2026-10-18 23:29`。手写而不是用 `intl`：只此一处需要，
/// 且固定格式不依赖 locale 数据。
String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// 两个时间之间相差的"整天数"（向下取整，忽略时分）。
int _wholeDaysBetween(DateTime from, DateTime to) {
  final DateTime a = DateTime(from.year, from.month, from.day);
  final DateTime b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays.abs();
}

/// 取第一行非空文本（卡片上的正文预览）。
String _firstLine(String text) {
  for (final String line in text.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

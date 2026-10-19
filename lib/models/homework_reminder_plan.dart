// 作业提醒排期：一条 = "某份作业在某个时刻提醒一次"。
//
// 这份结构是 **Dart ↔ Kotlin 的契约**：Dart 算好全部触发点，Kotlin 只负责
// 按时叫醒 + 发通知（哑执行），因此 Kotlin 侧不需要认识作业 / 插件 / 截止时间
// 这些概念。字段改名时两边必须同改（Kotlin 侧 `ReminderContract.PLAN_VERSION`）。
//
// 为什么要一次算全量而不是"到点再算"：
// 到点时 App 可能已经死了，只有原生闹钟能保证准时；而原生不该会算业务逻辑。
import 'dart:convert';

import 'homework.dart';
import 'homework_reminder_settings.dart';
import 'plugin_course_ref.dart';

/// 排期 schema 版本。字段含义变化时递增，Kotlin 侧同步修改。
const int kHomeworkReminderPlanVersion = 1;

/// 一条提醒排期。
class HomeworkReminderItem {
  const HomeworkReminderItem({
    required this.homeworkId,
    required this.pluginId,
    required this.title,
    required this.courseName,
    required this.deadline,
    required this.fireAt,
    required this.offsetMinutes,
    required this.slot,
    required this.totalSlots,
    this.courseId = '',
    this.courseRef,
    this.notifyWhenCheckFails = true,
  });

  /// 作业 ID（`homeworks` Box 的 key），后台校验靠它定位。
  final String homeworkId;

  /// 来源插件 ID；用户自建作业为 `'user'`（无插件可查，直接提醒）。
  final String pluginId;

  /// 展示用作业标题。
  final String title;

  /// 课程名，可为空。
  final String courseName;

  /// 截止时间。
  final DateTime deadline;

  /// 本次提醒的触发时刻。
  final DateTime fireAt;

  /// 提前分钟数（与 [fireAt] 冗余，用于通知文案"还有 X 分钟"）。
  final int offsetMinutes;

  /// 第几档（1 起），与 [totalSlots] 一起构成"第 1/3 次提醒"。
  final int slot;

  /// 总档数。
  final int totalSlots;

  /// 作业关联的课程 ID（带插件前缀，如 `chaoxing:12345`）。
  final String courseId;

  /// 该作业所属课程的插件原始 ref（`fetchHomeworks` 的入参）。
  ///
  /// 后台校验时直接用它调插件，省掉一次 `fetchCourseList` 请求
  /// （学习通有风控，能少一次就少一次）。`null` 表示排期时没拿到 ref，
  /// 校验时退回"先拉课程列表再匹配"。
  final Map<String, dynamic>? courseRef;

  /// 校验失败时是否仍提醒（用户偏好，排期时快照进来）。
  final bool notifyWhenCheckFails;

  /// 距截止还有多久（用于通知文案）。
  String get remainingText {
    if (offsetMinutes >= 60 && offsetMinutes % 60 == 0) {
      final int hours = offsetMinutes ~/ 60;
      if (hours >= 24 && hours % 24 == 0) return '${hours ~/ 24} 天';
      return '$hours 小时';
    }
    return '$offsetMinutes 分钟';
  }

  /// 通知标题：优先课程名，没有就用通用标题。
  String get notificationTitle =>
      courseName.isEmpty ? '作业快截止了' : '作业提醒 · $courseName';

  /// 通知正文。
  String get notificationBody => '「$title」还有 $remainingText截止'
      '（共 $totalSlots 次提醒的第 $slot 次）';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'homeworkId': homeworkId,
        'pluginId': pluginId,
        'title': title,
        'courseName': courseName,
        'deadlineMillis': deadline.millisecondsSinceEpoch,
        'fireAtMillis': fireAt.millisecondsSinceEpoch,
        'offsetMinutes': offsetMinutes,
        'slot': slot,
        'totalSlots': totalSlots,
        'courseId': courseId,
        'courseRef': courseRef,
        'notifyWhenCheckFails': notifyWhenCheckFails,
      };

  factory HomeworkReminderItem.fromJson(Map<String, dynamic> json) {
    return HomeworkReminderItem(
      homeworkId: '${json['homeworkId'] ?? ''}',
      pluginId: '${json['pluginId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      courseName: '${json['courseName'] ?? ''}',
      deadline: _asDate(json['deadlineMillis']) ?? DateTime.now(),
      fireAt: _asDate(json['fireAtMillis']) ?? DateTime.now(),
      offsetMinutes: _asInt(json['offsetMinutes']),
      slot: _asInt(json['slot']),
      totalSlots: _asInt(json['totalSlots']),
      courseId: '${json['courseId'] ?? ''}',
      courseRef: json['courseRef'] is Map
          ? _asStringKeyed(json['courseRef'] as Map)
          : null,
      notifyWhenCheckFails: json['notifyWhenCheckFails'] != false,
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final int? ms = int.tryParse(value);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static Map<String, dynamic> _asStringKeyed(Map<dynamic, dynamic> raw) {
    final Map<String, dynamic> result = <String, dynamic>{};
    raw.forEach((dynamic key, dynamic value) {
      if (key != null) result['$key'] = value;
    });
    return result;
  }
}

/// 一份完整排期（下发给 Kotlin）。
class HomeworkReminderPlan {
  const HomeworkReminderPlan(this.items);

  final List<HomeworkReminderItem> items;

  int get length => items.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': kHomeworkReminderPlanVersion,
        'items': items.map((HomeworkReminderItem i) => i.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());
}

/// 排期构建：纯函数，便于单测（不碰网络、不碰存储）。
///
/// 规则：
/// 1. 只要**未完成、未隐藏、有截止时间**的作业（已完成的沉底不打扰）；
/// 2. 每个档位生成一条，**触发时刻必须还在未来**（[minLead] 之内到点的算过期，
///    避免"刚排好就立刻响"的诡异体验）；
/// 3. 按触发时刻升序，最多 [maxItems] 条（防止一次性塞几百个闹钟）。
///
/// [refsByPlugin] 是"上次同步时用过的课程 ref"，用于给每条排期挂上
/// 后台校验所需的插件入参；缺失时留 `null`，由校验端自己补拉。
List<HomeworkReminderItem> buildHomeworkReminderPlan({
  required Iterable<Homework> homeworks,
  required HomeworkReminderSettings settings,
  required DateTime now,
  Map<String, List<PluginCourseRef>> refsByPlugin = const {},
  Duration minLead = const Duration(seconds: 45),
  int maxItems = 200,
}) {
  if (!settings.isEffective) return const <HomeworkReminderItem>[];

  final DateTime earliest = now.add(minLead);
  final List<HomeworkReminderItem> items = <HomeworkReminderItem>[];

  for (final Homework homework in homeworks) {
    if (homework.isCompleted || homework.isHidden) continue;
    final DateTime? deadline = homework.displayDeadline;
    if (deadline == null) continue;
    // 已逾期的不再排（提醒"还有 0 分钟"没有意义）。
    if (!deadline.isAfter(now)) continue;

    final List<PluginCourseRef> refs =
        refsByPlugin[homework.sourcePluginId] ?? const <PluginCourseRef>[];
    final PluginCourseRef? ref = _matchCourseRef(homework, refs);
    final int totalSlots = settings.offsetsMinutes.length;

    for (int index = 0; index < totalSlots; index++) {
      final int offset = settings.offsetsMinutes[index];
      final DateTime fireAt = deadline.subtract(Duration(minutes: offset));
      if (!fireAt.isAfter(earliest)) continue;
      items.add(
        HomeworkReminderItem(
          homeworkId: homework.id,
          pluginId: homework.sourcePluginId,
          title: homework.displayTitle,
          courseName: homework.courseName,
          deadline: deadline,
          fireAt: fireAt,
          offsetMinutes: offset,
          slot: index + 1,
          totalSlots: totalSlots,
          courseId: homework.courseId,
          courseRef: ref?.toJson(),
          notifyWhenCheckFails: settings.notifyWhenCheckFails,
        ),
      );
    }
  }

  items.sort((HomeworkReminderItem a, HomeworkReminderItem b) {
    final int byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.homeworkId.compareTo(b.homeworkId);
  });

  if (items.length > maxItems) {
    return List<HomeworkReminderItem>.unmodifiable(items.sublist(0, maxItems));
  }
  return List<HomeworkReminderItem>.unmodifiable(items);
}

/// 在课程 ref 里找与作业匹配的那一条。
///
/// 两种匹配（先精确后宽松）：
/// 1. `ref.courseId == 作业 courseId 去掉插件前缀`（插件约定：作业带 `chaoxing:` 前缀）；
/// 2. `ref.id == 作业 courseId`（少数插件直接用 ref.id 当作业的 courseId）。
PluginCourseRef? _matchCourseRef(
  Homework homework,
  List<PluginCourseRef> refs,
) {
  if (refs.isEmpty || homework.courseId.isEmpty) return null;
  final String rawCourseId = _stripPluginPrefix(
    homework.courseId,
    homework.sourcePluginId,
  );
  for (final PluginCourseRef ref in refs) {
    // ref 是不透明容器，`courseId` 只是插件约定字段，缺失时为 null。
    if ('${ref.raw['courseId'] ?? ''}' == rawCourseId) return ref;
  }
  for (final PluginCourseRef ref in refs) {
    if (ref.id == homework.courseId || ref.id == rawCourseId) return ref;
  }
  return null;
}

/// 去掉 `"<pluginId>:"` 前缀；没有该前缀时原样返回。
String _stripPluginPrefix(String courseId, String pluginId) {
  final String prefix = '$pluginId:';
  if (pluginId.isNotEmpty && courseId.startsWith(prefix)) {
    return courseId.substring(prefix.length);
  }
  return courseId;
}

/// 供后台校验复用：按作业的 courseId 在 ref 列表里挑匹配项。
PluginCourseRef? matchCourseRefForCheck({
  required String courseId,
  required String pluginId,
  required List<PluginCourseRef> refs,
}) {
  return _matchCourseRef(
    Homework(
      id: '',
      title: '',
      courseId: courseId,
      sourcePluginId: pluginId,
    ),
    refs,
  );
}

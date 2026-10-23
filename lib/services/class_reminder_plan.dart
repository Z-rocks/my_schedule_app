// 上课提醒的排期计算：纯函数，不碰存储也不碰平台通道。
//
// ## 为什么只排未来 7 天
//
// 一学期的课有几百条提醒。全排进去会撞上两个现实限制：
// 1. Android 的 `AlarmManager` 单应用可排闹钟数有上限（各家 ROM 收紧得更狠，
//    MIUI 尤其明显），排几百个会静默丢掉一部分；
// 2. 课表会变（同步、用户改课、调课），排得越远、作废的闹钟越多。
//
// 7 天覆盖"下周要上的课"，配合"App 每次回前台重排"就足够——
// 用户只要一周内打开过一次 App，提醒就不会断。
//
// ## 为什么不做后台校验
//
// 作业提醒要到点回查"是否已提交"（数据在服务器上，会变）。上课提醒的数据
// 全在本地 Hive 里，排期时的快照就是事实，到点直接响即可——
// 因此不需要起 Flutter 引擎，也不需要前台服务。
import '../models/class_reminder_settings.dart';
import '../models/course.dart';
import '../models/semester_config.dart';
import '../models/time_place.dart';
import 'timetable_logic.dart';

/// 排期窗口（天）。
const int kClassReminderHorizonDays = 7;

/// 排期 schema 版本。
///
/// **必须与 Kotlin 侧 `ClassReminderContract.PLAN_VERSION` 一致**：
/// 原生解析时版本不符会整份忽略（不崩，只是不提醒），所以改结构必须两边同改。
const int kClassReminderPlanVersion = 1;

/// 一条上课提醒。
class ClassReminderItem {
  const ClassReminderItem({
    required this.requestCode,
    required this.courseId,
    required this.courseName,
    required this.room,
    required this.startSession,
    required this.endSession,
    required this.fireAt,
    required this.offsetMinutes,
    required this.classStart,
  });

  /// 闹钟的 requestCode（同一档位始终相同 → 重复排期只覆盖、不重复响）。
  final int requestCode;

  final String courseId;
  final String courseName;
  final String room;
  final int startSession;
  final int endSession;

  /// 提醒触发时刻。
  final DateTime fireAt;

  /// 提前量（分钟）。
  final int offsetMinutes;

  /// 上课时刻（通知正文里显示）。
  final DateTime classStart;

  /// 通知标题：课程名。
  String get title => courseName.isEmpty ? '上课提醒' : courseName;

  /// 通知正文：`15 分钟后 · 第3-4节 · HE-405 · 10:25 上课`。
  String get body {
    final List<String> parts = <String>[
      '${_offsetText(offsetMinutes)}后上课',
      startSession == endSession
          ? '第 $startSession 节'
          : '第 $startSession-$endSession 节',
      if (room.isNotEmpty) room,
      _hhmm(classStart),
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'requestCode': requestCode,
        'courseId': courseId,
        'courseName': courseName,
        'room': room,
        'startSession': startSession,
        'endSession': endSession,
        'fireAtMillis': fireAt.millisecondsSinceEpoch,
        'offsetMinutes': offsetMinutes,
        'title': title,
        'body': body,
      };
}

/// 计算 [date] 落在学期第几周。
///
/// 与 [TimetableLogic.currentWeek] 的区别：**不做 clamp**。
/// 排期要能判断"这天在学期之外"（开学前 / 学期结束后），clamp 过就分不清
/// "第 1 周" 和 "开学前"。返回 `0` 或负数表示在学期开始之前。
int weekOfDate(SemesterConfig config, DateTime date) {
  final DateTime start = DateTime(
    config.startDate.year,
    config.startDate.month,
    config.startDate.day,
  );
  final DateTime day = DateTime(date.year, date.month, date.day);
  final int diff = day.difference(start).inDays;
  // 注意 Dart 的 `~/` 是**向零截断**（不是向下取整）：开学前一天 diff = -1，
  // `-1 ~/ 7` 得 0 而不是 -1。反正"0 与负数都表示学期之前"，判定只看 `< 1`，
  // 所以不影响正确性——但别指望靠它区分"开学前一天"和"开学当天"。
  if (diff < 0) return diff ~/ 7;
  return diff ~/ 7 + 1;
}

/// 从作息字符串（`08:30-09:15`）里取出上课时刻。
///
/// 解析不出来返回 `null`——调用方跳过这门课，而不是用默认值猜一个时间
/// （猜错等于在错误的时间提醒，比不提醒更糟）。
DateTime? sessionStartTime(DateTime day, String? range) {
  if (range == null || range.trim().isEmpty) return null;
  final RegExpMatch? match =
      RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})').firstMatch(range);
  if (match == null) return null;
  final int? hour = int.tryParse(match.group(1)!);
  final int? minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// 生成排期。
///
/// [sectionTimes] 是"节次 → 时间段"（`{3: '10:25-11:10'}`），
/// 来自插件同步下来的真实作息；缺某节就跳过那节课。
/// [now] 用于过滤已经过去的时刻（含 2 秒内即将过去的，避免"刚排好就响"）。
List<ClassReminderItem> buildClassReminderPlan({
  required List<Course> courses,
  required SemesterConfig config,
  required Map<int, String> sectionTimes,
  required ClassReminderSettings settings,
  required DateTime now,
  int horizonDays = kClassReminderHorizonDays,
}) {
  if (!settings.isEffective) return const <ClassReminderItem>[];
  final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime earliest = now.add(const Duration(seconds: 2));

  final List<ClassReminderItem> items = <ClassReminderItem>[];
  // 同一门课同一节次在重叠的 TimePlace 里可能出现多次（合班课、跨周分段），
  // 去重避免一次课响两遍。
  final Set<String> seen = <String>{};

  for (int i = 0; i < horizonDays; i++) {
    final DateTime day = today.add(Duration(days: i));
    final int week = weekOfDate(config, day);
    if (week < 1 || week > totalWeeks) continue;

    for (final Course course in courses) {
      for (final TimePlace place in course.displayTimePlaces) {
        if (place.day != day.weekday) continue;
        if (!TimetableLogic.hasClassInWeek(place, week)) continue;

        final DateTime? start =
            sessionStartTime(day, sectionTimes[place.startSession]);
        if (start == null) continue;

        final DateTime fireAt =
            start.subtract(Duration(minutes: settings.offsetMinutes));
        if (!fireAt.isAfter(earliest)) continue;

        final String key = '${course.id}|${place.startSession}|$day';
        if (!seen.add(key)) continue;

        items.add(
          ClassReminderItem(
            requestCode: classReminderRequestCode(
              courseId: course.id,
              day: day,
              startSession: place.startSession,
              offsetMinutes: settings.offsetMinutes,
            ),
            courseId: course.id,
            courseName: course.displayName,
            room: place.room,
            startSession: place.startSession,
            endSession: place.endSession,
            fireAt: fireAt,
            offsetMinutes: settings.offsetMinutes,
            classStart: start,
          ),
        );
      }
    }
  }

  items.sort((ClassReminderItem a, ClassReminderItem b) =>
      a.fireAt.compareTo(b.fireAt));
  return items;
}

/// 生成稳定的 requestCode。
///
/// 稳定性很重要：同一个 `(课程, 日期, 节次, 提前量)` 必须每次都算出同一个值，
/// 否则重排时旧闹钟取消不掉、新闹钟又排一个，最终同一节课响好几次。
///
/// 用 FNV-1a 自己算而不用 `Object.hash` / `String.hashCode`：
/// 后两者不保证跨进程稳定（Dart 文档明确说 `Object.hash` 可能在两次运行间变化），
/// 而闹钟的 PendingIntent 是**跨进程持久**的。
int classReminderRequestCode({
  required String courseId,
  required DateTime day,
  required int startSession,
  required int offsetMinutes,
}) {
  int hash = 0x811C9DC5;
  void mix(int value) {
    hash = ((hash ^ (value & 0xFF)) * 0x01000193) & 0xFFFFFFFF;
  }

  for (final int unit in courseId.codeUnits) {
    mix(unit);
  }
  // 日期只取"年月日"三个数，同一天永远得到同一个值。
  mix(day.year & 0xFF);
  mix((day.year >> 8) & 0xFF);
  mix(day.month);
  mix(day.day);
  mix(startSession);
  mix(offsetMinutes);

  // 收窄到 30 位：保证是正的 32 位 int（PendingIntent 的 requestCode 是 Int）。
  return hash & 0x3FFFFFFF;
}

/// `15` → `15 分钟`；`60` → `1 小时`。
String _offsetText(int minutes) {
  if (minutes < 60) return '$minutes 分钟';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

String _hhmm(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

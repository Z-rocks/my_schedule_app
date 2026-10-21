// 小组件快照服务（Phase W1）：把课表 / 作业 / 考试数据压成一份小 JSON，
// 供 Kotlin 侧小组件（RemoteViews）直接渲染。
//
// 设计要点（对应 docs/widget_task_breakdown.md P1）：
// - **业务逻辑仍然只有一份**：周次、单双周过滤、展示排序全部复用
//   `TimetableLogic` 与各 Provider 的 `displayXxx`，本服务只做"压缩成快照"。
// - **纯函数**：不读 Hive、不持有 Provider、不碰 MethodChannel。
//   调用方（`WidgetRefreshController`）负责取数与发送，便于单测。
// - **Kotlin 侧是"哑渲染"**：颜色、倒计时文案、时间文本全部在这里算好，
//   小组件进程只负责往布局里填字符串和色值。
// - **schema 带版本号**：`version` 升级必须递增；Kotlin 解析器遇到
//   不认识的版本走空态（"请打开 App 更新"），绝不能崩。
import '../models/course.dart';
import '../models/exam.dart';
import '../models/homework.dart';
import '../models/semester_config.dart';
import '../models/time_place.dart';
import '../services/section_time_service.dart';
import '../services/timetable_logic.dart';

/// 快照 schema 版本。字段含义变化时递增，Kotlin 端 [WidgetSnapshotParser]
/// 以它为准选择解析路径。
///
/// v2（2026-10-17）：新增 `schedule.nextSession`（当前/下一节课）。
/// 卡片从"今天全部课程"改成"下一节课 + 今日课程列表"，两处都依赖它。
///
/// v3（2026-10-21）：教室从"每门课一个"改成"每一段课一个"。
/// `courseTable[].room` 删除，改由 `todaySessions[].room` / `nextSession.room`
/// 承载——同一门课在不同星期 / 不同节次可能换教室，按课程存必然张冠李戴。
/// **两端必须同改**：`WidgetSnapshotContract.VERSION`（Kotlin）。
const int kWidgetSnapshotVersion = 3;

/// 作业卡片最多带几条（RemoteViews 静态渲染的舒适上限，拆解文档 D5）。
const int kWidgetHomeworkItems = 5;

/// 考试卡片最多带几条。
const int kWidgetExamItems = 3;

/// 课名 / 作业标题在小组件里的最大字符数。
///
/// RemoteViews 的 TextView 只有 `ellipsize=end`，遇到超长英文单词
/// （如 `"DataStructureAndAlgorithm..."`）仍会难看，所以在 Dart 侧预截断。
const int kWidgetNameMaxChars = 20;

/// 一周中文天名（下标 0 对应周一，即 `TimePlace.day == 1`）。
const List<String> _weekdayLabels = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// 兜底色板：主题色板不可用（极端情况）时按课程名哈希取色。
///
/// 取一组中性偏亮的 ARGB，深色桌面（values-night 配深字）下都压得住。
const List<int> kWidgetFallbackPalette = <int>[
  0xFF90CAF9, // 蓝
  0xFFF48FB1, // 粉
  0xFFA5D6A7, // 绿
  0xFFFFCC80, // 橙
  0xFFCE93D8, // 紫
  0xFF80DEEA, // 青
  0xFFE6EE9C, // 黄绿
  0xFFEF9A9A, // 红
];

/// 小组件快照：一份自包含的 JSON 数据（课表今天/本周 + 作业 + 考试）。
///
/// 只提供 [toJson]；编码（`jsonEncode`）与发送由 `WidgetBridge` 负责。
class WidgetSnapshot {
  const WidgetSnapshot(this._json);

  final Map<String, dynamic> _json;

  /// 序列化为给 Kotlin 的 Map（`WidgetBridge` 会再 `jsonEncode`）。
  Map<String, dynamic> toJson() => _json;
}

/// 快照构造入口（纯静态，同 [TimetableLogic] 风格，禁止实例化）。
class WidgetSnapshotService {
  WidgetSnapshotService._();

  /// 构造快照。
  ///
  /// - [courses]：**可见**课程（`CourseProvider.visibleCourses`，已过滤隐藏）；
  /// - [semester]：当前学期配置，`null` 表示未设置；
  /// - [homeworks] / [exams]：直接用 `displayHomeworks` / `displayExams`
  ///   （已过滤隐藏、已按展示规则排序），本方法只截断不再排序；
  /// - [sectionTimes]：插件提供的节次时间，`null` 时省略时间文本；
  /// - [palette]：主题课程卡色板（ARGB），空则用 [kWidgetFallbackPalette]；
  /// - [now]：注入"现在"，测试用；省缺取系统当前时间。
  static WidgetSnapshot build({
    required List<Course> courses,
    required SemesterConfig? semester,
    required List<Homework> homeworks,
    required List<Exam> exams,
    SectionTimes? sectionTimes,
    List<int> palette = const <int>[],
    DateTime? now,
  }) {
    final DateTime nowTime = now ?? DateTime.now();
    final List<int> colors = palette.isEmpty ? kWidgetFallbackPalette : palette;

    final int week = semester == null
        ? 1
        : TimetableLogic.currentWeek(semester, now: nowTime);
    final int today = nowTime.weekday; // DateTime.weekday: 周一=1 … 周日=7
    // 两个空态标志分开（2026-10-17 修正）："本学期一门课都没有"与
    // "本周没课（如单双周课的淡周）"是不同文案，混成一个会让后者
    // 显示"课表还是空的"，误导用户以为同步失败。
    final bool scheduleEmpty = courses.isEmpty;
    final bool weekHasClass = TimetableLogic.hasAnyClassInWeek(courses, week);

    return WidgetSnapshot(<String, dynamic>{
      'version': kWidgetSnapshotVersion,
      'generatedAt': nowTime.toIso8601String(),
      'updatedLabel': '更新于 ${_hhmm(nowTime)}',
      'hasSemester': semester != null,
      'semesterName': semester?.name ?? '',
      'week': week,
      'today': today,
      'todayLabel': _weekdayLabels[today - 1],
      'scheduleEmpty': scheduleEmpty,
      'weekHasClass': weekHasClass,
      'schedule': _scheduleJson(
        courses: courses,
        semester: semester,
        week: week,
        today: today,
        sectionTimes: sectionTimes,
        colors: colors,
        now: nowTime,
      ),
      'sectionTimes': sectionTimes == null
          ? const <String, dynamic>{}
          : <String, dynamic>{
              for (final MapEntry<int, String> e in sectionTimes.times.entries)
                '${e.key}': e.value,
            },
      'homework': _homeworkJson(homeworks, nowTime),
      'exam': _examJson(exams, nowTime),
    });
  }

  // ——————————————————————— 课表 ———————————————————————

  static Map<String, dynamic> _scheduleJson({
    required List<Course> courses,
    required SemesterConfig? semester,
    required int week,
    required int today,
    required SectionTimes? sectionTimes,
    required List<int> colors,
    required DateTime now,
  }) {
    final List<List<Course?>> grid = TimetableLogic.buildGrid(courses, week);
    // 与 grid 同形的时间地点网格：教室必须按"哪一天、第几节"取，
    // 不能按课程取（v3 修正）。两套网格的填充规则完全一致（都是先到先得），
    // 因此 `placeGrid[day][session]` 一定是 `grid[day][session]` 那门课的安排。
    final List<List<TimePlace?>> placeGrid = _buildPlaceGrid(courses, week);

    // 课程索引表：按 grid 出现顺序编号，weekGrid 只存索引，避免重复存课程名。
    // 教室不在这里——它是"这一段课"的属性，跟着 todaySessions 走。
    final Map<String, int> courseIndex = <String, int>{};
    final List<Map<String, dynamic>> courseTable = <Map<String, dynamic>>[];
    int indexOfCourse(Course c) {
      return courseIndex.putIfAbsent(c.id, () {
        final int index = courseTable.length;
        courseTable.add(<String, dynamic>{
          'name': _truncate(c.displayName, kWidgetNameMaxChars),
          'color': _colorOf(c, colors),
        });
        return index;
      });
    }

    // 本周网格：cells[i][j]，i = day-1，j = session-1，值为课程索引或 -1。
    final List<List<int>> cells = <List<int>>[];
    int maxSession = 0;
    for (int day = 1; day <= kDaysPerWeek; day++) {
      final List<int> row = <int>[];
      for (int session = 1; session <= kMaxSessions; session++) {
        final Course? course = grid[day][session];
        if (course == null) {
          row.add(-1);
        } else {
          row.add(indexOfCourse(course));
          if (session > maxSession) maxSession = session;
        }
      }
      cells.add(row);
    }

    // 今天的课程序列：把当天列里连续的同一门课合并成一个块（跨节显示成一段）。
    final List<Map<String, dynamic>> todaySessions = <Map<String, dynamic>>[];
    // 与 todaySessions 一一对应的起止分钟数（作息缺失时为 null）。
    // 只用于算"当前/下一节"，不写进 JSON——小组件是哑渲染，不解析时间。
    final List<(int?, int?)> spans = <(int?, int?)>[];
    for (int session = 1; session <= kMaxSessions; session++) {
      final Course? course = grid[today][session];
      if (course == null) continue;
      final int length = _mergedLength(grid, placeGrid, today, session);
      final int index = indexOfCourse(course);
      todaySessions.add(<String, dynamic>{
        'courseIdx': index,
        'session': session,
        'length': length,
        'sectionText': _sectionText(session, length, sectionTimes),
        'room': _roomOfPlace(placeGrid[today][session]),
      });
      spans.add(_spanOf(session, length, sectionTimes));
      session += length - 1; // 跳过已合并的格子
    }

    return <String, dynamic>{
      'week': week,
      'semesterName': semester?.name ?? '',
      'today': today,
      'maxSession': maxSession,
      'courseTable': courseTable,
      'cells': cells,
      'todaySessions': todaySessions,
      'nextSession': _nextSessionJson(todaySessions, spans, now),
    };
  }

  /// 当前正在上 / 接下来要上的那节课（v2 新增）。
  ///
  /// 判定完全基于**节次时间**（`SectionTimes`）：先看现在落在哪一段里
  /// （ongoing），否则看第一段还没开始的（upcoming），都过了就是 finished。
  ///
  /// 插件没给作息时无法判断"现在上到哪"，退化为今天第一节并标 `unknown`
  /// ——总比空着好，至少告诉用户"今天还有课"。
  static Map<String, dynamic>? _nextSessionJson(
    List<Map<String, dynamic>> todaySessions,
    List<(int?, int?)> spans,
    DateTime now,
  ) {
    if (todaySessions.isEmpty) return null;

    final bool hasAnySpan =
        spans.any((s) => s.$1 != null && s.$2 != null);
    if (!hasAnySpan) {
      return _sessionJson(todaySessions.first, state: 'unknown', label: '');
    }

    final int nowMinutes = now.hour * 60 + now.minute;
    for (int i = 0; i < todaySessions.length; i++) {
      final (int?, int?) span = spans[i];
      final int? start = span.$1;
      final int? end = span.$2;
      if (start == null || end == null) continue;
      if (nowMinutes < start) {
        return _sessionJson(
          todaySessions[i],
          state: 'upcoming',
          label: '${_hhmmFromMinutes(start)} 上课',
        );
      }
      if (nowMinutes < end) {
        return _sessionJson(
          todaySessions[i],
          state: 'ongoing',
          label: '进行中',
        );
      }
    }

    // 今天的课都上完了：仍返回最后一节，让卡片能显示"已结束 + 最后一门课"。
    return _sessionJson(todaySessions.last, state: 'finished', label: '已结束');
  }

  static Map<String, dynamic> _sessionJson(
    Map<String, dynamic> session, {
    required String state,
    required String label,
  }) {
    return <String, dynamic>{
      'courseIdx': session['courseIdx'],
      'sectionText': session['sectionText'],
      // 教室跟着"这一段课"走，不是跟着课程走（v3）：下一节课在别的教室时，
      // 卡片不能拿这门课别的时段的教室顶上。
      'room': session['room'] ?? '',
      'state': state,
      'label': label,
    };
  }

  /// 某一段课（可能跨多节）的起止分钟数；作息缺失或格式异常返回 `(null, null)`。
  static (int?, int?) _spanOf(
    int session,
    int length,
    SectionTimes? sectionTimes,
  ) {
    if (sectionTimes == null || sectionTimes.times.isEmpty) {
      return (null, null);
    }
    // 插件作息形如 "10:25-11:10"：第一段的 start 取首节开头，
    // 最后一段的 end 取末节结尾。
    final int? start = _minutesOf(sectionTimes.times[session], first: true);
    final int? end =
        _minutesOf(sectionTimes.times[session + length - 1], first: false);
    return (start, end);
  }

  /// `"10:25-11:10"` → 起（或止）的分钟数；解析不出返回 `null`。
  static int? _minutesOf(String? raw, {required bool first}) {
    if (raw == null) return null;
    final List<String> range = raw.split('-');
    if (range.length < 2) return null;
    final String text = (first ? range.first : range.last).trim();
    final List<String> hm = text.split(':');
    if (hm.length < 2) return null;
    final int? hour = int.tryParse(hm[0]);
    final int? minute = int.tryParse(hm[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// 分钟数 → `"10:25"`。
  static String _hhmmFromMinutes(int minutes) {
    final String h = (minutes ~/ 60).toString().padLeft(2, '0');
    final String m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 当天列里从 [session] 开始、同一门课**同一段安排**连续占用的节数（至少 1）。
  ///
  /// 除了比课程实例，还要比 [TimePlace] 实例：同一门课同一天可能拆成两段
  /// （如 3-4 节在 A 楼、5-6 节在 B 楼），按课程合并会把两段并成一段，
  /// 节次和教室都会错。`buildGrid` 对每段安排填的是同一个 [Course] 实例，
  /// 所以只能靠 [placeGrid] 区分。
  static int _mergedLength(
    List<List<Course?>> grid,
    List<List<TimePlace?>> placeGrid,
    int day,
    int session,
  ) {
    final Course course = grid[day][session]!;
    final TimePlace? place = placeGrid[day][session];
    int length = 1;
    while (session + length <= kMaxSessions &&
        identical(grid[day][session + length], course) &&
        identical(placeGrid[day][session + length], place)) {
      length++;
    }
    return length;
  }

  /// 节次文本：`"3-4节 10:25-11:10"`；插件没给作息时只有 `"3-4节"`。
  static String _sectionText(
    int session,
    int length,
    SectionTimes? sectionTimes,
  ) {
    final String range =
        length > 1 ? '$session-${session + length - 1}节' : '$session节';
    if (sectionTimes == null || sectionTimes.times.isEmpty) return range;
    final String? start = sectionTimes.times[session];
    final String? end = sectionTimes.times[session + length - 1];
    if (start == null || end == null) return range;
    // 插件作息形如 "10:25-11:10"，取两端拼出本节课的时间段。
    final String startTime = start.split('-').first.trim();
    final String endTime = end.split('-').last.trim();
    if (startTime.isEmpty || endTime.isEmpty) return range;
    return '$range $startTime-$endTime';
  }

  /// "本周每格对应哪一段安排"的网格，直接复用 [TimetableLogic.buildPlaceGrid]。
  ///
  /// 不在这里自己再写一份：两份实现一旦有一处规则漂移（比如某天忘了过滤
  /// 单双周），教室就会和课程对不上——那正是 v3 要修的 bug。
  static List<List<TimePlace?>> _buildPlaceGrid(
    List<Course> courses,
    int week,
  ) =>
      TimetableLogic.buildPlaceGrid(courses, week);

  /// 某一段安排的展示教室；没有安排或没填教室时返回空串。
  ///
  /// 用 [TimePlace.displayRoom] 而不是裸 `room`：`room` 常是
  /// `"曹妃甸校区 HE-405"` 这种"校区 + 教室"拼接，课表卡片只显示教室部分，
  /// 小组件也必须一致——否则同一节课在两处显示的教室不一样。
  ///
  /// **不要**退回到"这门课别的时段的教室"：那正是旧实现的错——
  /// 用户看到的教室必须就是这节课的教室，没有就不显示。
  static String _roomOfPlace(TimePlace? place) => place?.displayRoom ?? '';

  // ——————————————————————— 作业 ———————————————————————

  static Map<String, dynamic> _homeworkJson(
    List<Homework> homeworks,
    DateTime now,
  ) {
    final List<Homework> pending = homeworks
        .where((Homework h) => !h.isCompleted)
        .toList(growable: false);
    final int overdue = pending.where((Homework h) => h.isOverdue(now)).length;

    return <String, dynamic>{
      'pendingCount': pending.length,
      'overdueCount': overdue,
      'items': pending
          .take(kWidgetHomeworkItems)
          .map(
            (Homework h) => <String, dynamic>{
              'title': _truncate(h.displayTitle, kWidgetNameMaxChars),
              'course': _truncate(h.courseName, 10),
              'dueText': _formatDateTime(h.displayDeadline),
              'daysLeftText': _homeworkDaysLeftText(h, now),
              'overdue': h.isOverdue(now),
            },
          )
          .toList(growable: false),
    };
  }

  static String _homeworkDaysLeftText(Homework h, DateTime now) {
    if (h.isOverdue(now)) return '已逾期';
    final DateTime? due = h.displayDeadline;
    if (due == null) return '无截止';
    // 截止时间就是今天（自然日）→ "今天截止"比"剩1天"更直白。
    if (due.year == now.year && due.month == now.month && due.day == now.day) {
      return '今天截止';
    }
    return '剩${h.daysUntilDeadline(now)}天';
  }

  // ——————————————————————— 考试 ———————————————————————

  static Map<String, dynamic> _examJson(List<Exam> exams, DateTime now) {
    final List<Exam> upcoming =
        exams.where((Exam e) => !e.hasStarted(now)).toList(growable: false);

    return <String, dynamic>{
      'upcomingCount': upcoming.length,
      'items': upcoming
          .take(kWidgetExamItems)
          .map(
            (Exam e) => <String, dynamic>{
              'name': _truncate(e.displayName, kWidgetNameMaxChars),
              'location': _truncate(e.displayLocation, 14),
              'startText': _formatDateTime(e.displayStartTime),
              'daysLeftText': _examDaysLeftText(e, now),
            },
          )
          .toList(growable: false),
    };
  }

  static String _examDaysLeftText(Exam e, DateTime now) {
    if (e.daysUntil(now) <= 0) return '今天';
    return '${e.daysUntil(now)}天后';
  }

  // ——————————————————————— 公共 ———————————————————————

  /// 课程展示色（ARGB）：优先用户自定义色，否则按课程 ID 哈希取色板。
  ///
  /// 与 `timetable_grid.dart` 的 `_colorForCourse` 同一规则——保证小组件
  /// 色块和课表页面里同一门课颜色一致。
  static int _colorOf(Course course, List<int> palette) {
    final int? custom = course.displayColor;
    if (custom != null) return custom;
    if (palette.isEmpty) return 0xFFB0BEC5;
    final int index = course.id.hashCode.abs() % palette.length;
    return palette[index];
  }

  /// 超长截断 + 省略号。RemoteViews 的 TextView 截断策略很弱，预截断兜底。
  static String _truncate(String text, int maxChars) {
    final String trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}…';
  }

  /// "MM-dd HH:mm"；`null` → 空串。
  static String _formatDateTime(DateTime? time) {
    if (time == null) return '';
    final String mm = time.minute.toString().padLeft(2, '0');
    return '${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:$mm';
  }

  /// "HH:mm"，给小组件角落的"更新于 hh:mm"用。
  static String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

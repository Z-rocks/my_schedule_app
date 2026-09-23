// 课表逻辑：周次文本解析、当前周计算与网格构建（纯函数，无状态）
import '../models/course.dart';
import '../models/semester_config.dart';
import '../models/time_place.dart';

/// 一周的天数（周一至周日）。
const int kDaysPerWeek = 7;

/// 一天的最大节次（网格列数）。
const int kMaxSessions = 12;

/// 单个周次区间允许展开的最大周数，防止 `"1-999999"` 之类的输入撑爆内存。
const int kMaxWeekNumber = 60;

/// 课表相关的纯函数工具。
///
/// 全部为 `static`，**无状态、不依赖 Hive / Provider**，因此可以独立测试，
/// 也可以在插件运行时（Phase 3）里复用。
class TimetableLogic {
  /// 纯静态工具类，禁止实例化。
  TimetableLogic._();

  /// 把周次文本解析为**基础周次列表**（升序、去重）。
  ///
  /// 支持的格式：
  /// - `"4,6-14周"` → `[4, 6, 7, 8, 9, 10, 11, 12, 13, 14]`
  /// - `"第9周"` → `[9]`
  /// - `"1-16周"` → `[1, ..., 16]`
  /// - `"4,6-14周(单)"` → `[4, 6, ..., 14]`（**不**过滤单双周，
  ///   单双周由 [parseWeekType] 记录、由 [hasClassInWeek] 过滤）
  /// - `""` / 乱码 → `[]`
  ///
  /// 容错：逐片段解析，无法识别的片段直接跳过；区间起始大于结束、超出
  /// [kMaxWeekNumber] 的部分都会被丢弃。任何输入都不会抛异常。
  static List<int> parseWeeks(String rawText) {
    if (rawText.isEmpty) return const <int>[];

    // 去掉中文标点与"周/第"等修饰，只留下数字、逗号和连字符。
    final String cleaned = rawText
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('，', ',')
        .replaceAll('、', ',')
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        .replaceAll('~', '-')
        .replaceAll('第', '')
        .replaceAll('周', '')
        .replaceAll('星期', '')
        .replaceAll(RegExp(r'\([^)]*\)'), '') // 去掉 "(单)" / "(双)" 等括号内容
        .trim();
    if (cleaned.isEmpty) return const <int>[];

    final Set<int> weeks = <int>{};
    for (final String fragment in cleaned.split(',')) {
      final String part = fragment.trim();
      if (part.isEmpty) continue;

      final int? single = int.tryParse(part);
      if (single != null) {
        _addWeek(weeks, single);
        continue;
      }

      final List<String> bounds = part.split('-');
      if (bounds.length != 2) continue; // 多段连字符（如 "1-2-3"）视为无效
      final int? start = int.tryParse(bounds[0].trim());
      final int? end = int.tryParse(bounds[1].trim());
      if (start == null || end == null) continue;
      if (start > end) continue; // 反向区间视为无效

      final int last = end > kMaxWeekNumber ? kMaxWeekNumber : end;
      for (int week = start; week <= last; week++) {
        _addWeek(weeks, week);
      }
    }

    final List<int> result = weeks.toList()..sort();
    return result;
  }

  /// 从原始文本识别单双周。
  ///
  /// 用**关键词**而不是正则：教务系统的写法（`(单)` / `单周` / `双周`）
  /// 变体多且带全半角括号，关键词匹配更稳。
  ///
  /// 规则：
  /// - 同时出现"单"和"双"（如"单双周"）→ [WeekType.all]（等于每周都上）
  /// - 只出现"单" → [WeekType.odd]
  /// - 只出现"双" → [WeekType.even]
  /// - 都没有 → [WeekType.all]
  static WeekType parseWeekType(String rawText) {
    if (rawText.isEmpty) return WeekType.all;
    final bool hasOdd = rawText.contains('单');
    final bool hasEven = rawText.contains('双');
    if (hasOdd && hasEven) return WeekType.all;
    if (hasOdd) return WeekType.odd;
    if (hasEven) return WeekType.even;
    return WeekType.all;
  }

  /// 计算 [now]（默认当前时间）落在学期第几周。
  ///
  /// 边界处理（都只用到年月日，避免时分秒造成 off-by-one）：
  /// - `now` 早于 [SemesterConfig.startDate] → 返回 `1`
  /// - `now` 超出 [SemesterConfig.totalWeeks] → 返回 `totalWeeks`
  /// - 其他 → `(now - startDate).inDays ~/ 7 + 1`
  static int currentWeek(SemesterConfig config, {DateTime? now}) {
    final int totalWeeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final DateTime reference = now ?? DateTime.now();

    final DateTime start = DateTime(
      config.startDate.year,
      config.startDate.month,
      config.startDate.day,
    );
    final DateTime today =
        DateTime(reference.year, reference.month, reference.day);

    final int days = today.difference(start).inDays;
    if (days < 0) return 1; // 还没开学

    final int week = days ~/ 7 + 1;
    return week > totalWeeks ? totalWeeks : week;
  }

  /// 判断 [tp] 在第 [week] 周是否有课。
  ///
  /// - [week] 不在 [TimePlace.weeks] 里 → `false`
  /// - [TimePlace.weekType] 为 [WeekType.odd] 且 [week] 是偶数 → `false`
  /// - [TimePlace.weekType] 为 [WeekType.even] 且 [week] 是奇数 → `false`
  /// - 其他 → `true`
  static bool hasClassInWeek(TimePlace tp, int week) {
    if (!tp.weeks.contains(week)) return false;
    switch (tp.weekType) {
      case WeekType.odd:
        return week.isOdd;
      case WeekType.even:
        return week.isEven;
      case WeekType.all:
        return true;
    }
  }

  /// 构建课表网格：`grid[day][session] = Course?`。
  ///
  /// - 索引范围：`day` 1-7、`session` 1-12 有效；`[0]` 恒为 `null` 占位，
  ///   这样调用方可以直接用"星期几 / 第几节"当下标，不必减 1。
  /// - 跨节课程：`startSession + length - 1` 之间的每一格都会填上同一门课。
  /// - 只填本周有课的安排（用 [hasClassInWeek] 过滤，因此单双周在这里生效）。
  /// - 取 [Course.displayTimePlaces] 而不是 `timePlaces`，
  ///   用户改过时间地点时以覆盖层为准（CONTEXT 3.3）。
  /// - **跳过** `userOverride.hidden == true` 的课程（网格用于展示）。
  /// - 同一格被多门课占用时保留**先出现**的那门（按 `courses` 顺序），
  ///   后出现的只填它自己还没被占用的格子。
  ///
  /// 注意：本方法会跳过 `userOverride.hidden == true` 的课程。
  /// 若调用方已传入 `visibleCourses`（已过滤），此过滤是冗余但无害的。
  /// 保留它是为了防御"误传全部 `courses`"的常见错误。
  static List<List<Course?>> buildGrid(List<Course> courses, int week) {
    final List<List<Course?>> grid = List<List<Course?>>.generate(
      kDaysPerWeek + 1,
      (int _) => List<Course?>.filled(kMaxSessions + 1, null),
    );

    for (final Course course in courses) {
      if (course.isHidden) continue;

      for (final TimePlace tp in course.displayTimePlaces) {
        if (tp.day < 1 || tp.day > kDaysPerWeek) continue;
        if (!hasClassInWeek(tp, week)) continue;

        for (int offset = 0; offset < tp.length; offset++) {
          final int session = tp.startSession + offset;
          if (session < 1 || session > kMaxSessions) continue;
          grid[tp.day][session] ??= course; // 已有课则不覆盖
        }
      }
    }

    return grid;
  }

  /// 网格中某天某节的课程；索引越界返回 `null`（不抛异常）。
  static Course? courseAt(List<List<Course?>> grid, int day, int session) {
    if (day < 0 || day >= grid.length) return null;
    final List<Course?> column = grid[day];
    if (session < 0 || session >= column.length) return null;
    return column[session];
  }

  /// 网格中本周有课的格子数量（用于判断"课表是否为空"）。
  static int filledCellCount(List<List<Course?>> grid) {
    int count = 0;
    for (final List<Course?> column in grid) {
      for (final Course? course in column) {
        if (course != null) count++;
      }
    }
    return count;
  }

  /// 把周次列表压成便于展示的文本，如 `[1,2,3,5]` → `"1-3,5"`。
  static String formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final List<int> sorted = List<int>.of(weeks)..sort();
    final List<String> parts = <String>[];
    int start = sorted.first;
    int previous = start;
    for (int i = 1; i < sorted.length; i++) {
      final int current = sorted[i];
      if (current == previous + 1) {
        previous = current;
        continue;
      }
      parts.add(start == previous ? '$start' : '$start-$previous');
      start = current;
      previous = current;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    return parts.join(',');
  }

  /// 只在 1..[kMaxWeekNumber] 范围内的周次才会被收进集合。
  static void _addWeek(Set<int> weeks, int week) {
    if (week < 1 || week > kMaxWeekNumber) return;
    weeks.add(week);
  }
}
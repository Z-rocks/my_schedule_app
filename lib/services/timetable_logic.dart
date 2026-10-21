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
  /// - `"四,六至十四周"` / `"１－１６周"`（中文数字 / 全角数字）→ 同 `"4,6-14周"`
  /// - `""` / 乱码 → `[]`
  ///
  /// 容错：逐片段解析，无法识别的片段直接跳过；区间起始大于结束、超出
  /// [kMaxWeekNumber] 的部分都会被丢弃。任何输入都不会抛异常。
  static List<int> parseWeeks(String rawText) {
    if (rawText.isEmpty) return const <int>[];

    // 归一化（含全角数字与中文数字）在 [normalizeWeekText] 里做，
    // 这样 JS 侧的复刻只需要照抄一份同样的归一化顺序。
    final String cleaned = normalizeWeekText(rawText)
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

  /// 构建"每一格对应哪一段安排"的网格：`placeGrid[day][session] = TimePlace?`。
  ///
  /// 形状与填充规则和 [buildGrid] **逐条一致**（同样的单双周过滤、同样的
  /// 跨节填充、同样的"先到先得不覆盖"），因此
  /// `placeGrid[day][session]` 一定是 `buildGrid(courses, week)[day][session]`
  /// 那门课对应的安排。
  ///
  /// 为什么需要它：`buildGrid` 只返回 [Course]，把"教室 / 起止节次"这些
  /// **属于某一段安排**的信息丢了。课表卡片和小组件都要按"哪一天、第几节"
  /// 取教室——按课程取第一个教室，遇到同一门课换教室就必然显示错。
  static List<List<TimePlace?>> buildPlaceGrid(
    List<Course> courses,
    int week,
  ) {
    final List<List<TimePlace?>> grid = List<List<TimePlace?>>.generate(
      kDaysPerWeek + 1,
      (int _) => List<TimePlace?>.filled(kMaxSessions + 1, null),
    );

    for (final Course course in courses) {
      if (course.isHidden) continue;

      for (final TimePlace tp in course.displayTimePlaces) {
        if (tp.day < 1 || tp.day > kDaysPerWeek) continue;
        if (!hasClassInWeek(tp, week)) continue;

        for (int offset = 0; offset < tp.length; offset++) {
          final int session = tp.startSession + offset;
          if (session < 1 || session > kMaxSessions) continue;
          grid[tp.day][session] ??= tp; // 与 buildGrid 同为"先到先得"
        }
      }
    }

    return grid;
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

  // ——————————————— "哪些周有课"（Phase 5.1 新增） ———————————————
  //
  // 为什么需要：课表只画"当前周"，于是"有课程但本周恰好没课"长得和
  // "一门课都没有"一模一样——用户会以为同步失败。
  // 下面几个方法让 UI 能说清"本周没课（课程在第 4、6-14 周）"，
  // 而不是甩给用户一个空白网格。

  /// 某一周是否至少有一门课（按 [hasClassInWeek] 的真值口径判断）。
  ///
  /// 会跳过 `userOverride.hidden == true` 的课程——与 [buildGrid] 保持一致，
  /// 否则"提示有课的周"里会包含用户已经隐藏掉的课。
  static bool hasAnyClassInWeek(List<Course> courses, int week) {
    for (final Course course in courses) {
      if (course.isHidden) continue;
      for (final TimePlace tp in course.displayTimePlaces) {
        if (hasClassInWeek(tp, week)) return true;
      }
    }
    return false;
  }

  /// 全部"有课"的周次（升序去重），限制在 `1..totalWeeks` 内。
  ///
  /// [totalWeeks] 用来裁掉超出学期的周次（教务数据可能带 16 周而学期只配了 12 周）。
  static List<int> weeksWithClass(
    List<Course> courses, {
    required int totalWeeks,
  }) {
    final int limit = totalWeeks < 1 ? 1 : totalWeeks;
    final Set<int> found = <int>{};
    for (final Course course in courses) {
      if (course.isHidden) continue;
      for (final TimePlace tp in course.displayTimePlaces) {
        for (final int week in tp.weeks) {
          if (week >= 1 && week <= limit) found.add(week);
        }
      }
    }
    final List<int> sorted = found.toList()..sort();
    return sorted;
  }

  /// 距离 [week] **最近**的有课周次；没有任何有课周时返回 `null`。
  ///
  /// 平局（前后一样远）取**更早**的那一周：用户更可能是想回看而不是跳未来。
  static int? nearestWeekWithClass(
    List<Course> courses, {
    required int week,
    required int totalWeeks,
  }) {
    final List<int> weeks = weeksWithClass(courses, totalWeeks: totalWeeks);
    if (weeks.isEmpty) return null;
    int? best;
    int bestDistance = 1 << 30;
    for (final int candidate in weeks) {
      final int distance = (candidate - week).abs();
      // 严格小于 → 平局时保留先遇到的（即更早的周，因为 weeks 升序）
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  /// 只在 1..[kMaxWeekNumber] 范围内的周次才会被收进集合。
  static void _addWeek(Set<int> weeks, int week) {
    if (week < 1 || week > kMaxWeekNumber) return;
    weeks.add(week);
  }
}

// ————————————————— 周次文本归一化（Phase 5.1） —————————————————
//
// 为什么单独抽出来：教务系统的周次文本框是自由文本，各校写法差异很大。
// 归一化把"各种写法"压成 `"4,6-14"` 这种统一形式，后面的解析只面对一种形状。
//
// ⚠️ `assets/plugins/ncst-jwxt.js` 的 `__ncst_parseWeeks` 是本文件的 **JS 复刻**
// （沙箱里调不到 Dart）。改这里的任何规则都必须同步改那边，否则同一门课在
// "插件解析出的周次"与"内核再解析一次"两条路径上结果会不一致。

/// 把周次文本归一化成 `"4,6-14"` 形式。
///
/// 归一化顺序（顺序本身是契约，JS 侧必须一致）：
/// 1. 中文数字 → 阿拉伯数字（含十位组合，见 [chineseToArabic]）；
/// 2. 全角数字 → 半角（`"１－１６周"`，移动端中文输入法常见）；
/// 3. 中文标点 → 半角（逗号类 → `,`；连字符类 → `-`）；
/// 4. `至` / `到` → `-`（`"四至十六周"`、`"4到16周"` 都是常见写法）；
/// 5. 去掉 `第` / `周` / `星期` 等修饰字。
///
/// ⚠️ 中文数字**不能逐字替换**：`"十六"` 会变成 `"1"+"10"+"6"` = `"106"`，
/// 直接冲出 [kMaxWeekNumber] 变成空结果。所以先走 [chineseToArabic]。
String normalizeWeekText(String rawText) {
  if (rawText.isEmpty) return '';
  final String converted = _replaceFullWidthDigits(chineseToArabic(rawText));
  final StringBuffer out = StringBuffer();

  for (final int rune in converted.runes) {
    final String ch = String.fromCharCode(rune);
    if (ch == '，' || ch == '、' || ch == '；' || ch == ';') {
      out.write(',');
    } else if (ch == '－' ||
        ch == '—' ||
        ch == '–' ||
        ch == '~' ||
        ch == '～' ||
        ch == 'ー' ||
        ch == '至' ||
        ch == '到') {
      out.write('-');
    } else if (ch == '第' || ch == '周' || ch == '星期') {
      // 丢弃：修饰字，不承载信息
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// 全角数字 → 半角数字。
String _replaceFullWidthDigits(String text) {
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    if (rune >= _kFullWidthZero && rune <= _kFullWidthZero + 9) {
      out.writeCharCode(0x30 + (rune - _kFullWidthZero));
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// 把十位组合的中文数字转成阿拉伯数字。
///
/// 覆盖：`"四"`→`4`、`"十六"`→`16`、`"二十"`→`20`、`"二十五"`→`25`、`"十"`→`10`。
///
/// **必须整体处理而不是逐字替换**：`"十"` 在中文里是位权而不是"10"这个值，
/// 逐字替换会让 `"十六"` 变成 `"1"+"10"+"6"` = `"106"`。
///
/// 实现是**逐字符扫描**而不是正则：扫描点永远落在"可能是一个数字的开头"，
/// 于是 `"第十六周"` 里的 `'第'` 会被原样跳过，随后从 `'十'` 正确识别出 16。
/// （用正则找"数字开头"会把 `'第'` 之前的上下文搅进来，反而更容易出错。）
///
/// 只支持 1–99：周次不可能超过 [kMaxWeekNumber]（60），
/// 「百 / 千」不值得为此实现——需要时在这里加一个 '百' 分支即可。
String chineseToArabic(String text) {
  final int length = text.length;
  final StringBuffer out = StringBuffer();
  int i = 0;

  while (i < length) {
    final int? current = _kChineseDigitValue[text[i]];

    // ── 情形 1：当前字是 "十" —— 它是位权 ──
    if (text[i] == '十') {
      final int? tail =
          (i + 1 < length) ? _kChineseDigitValue[text[i + 1]] : null;
      if (tail != null) {
        out.write('${10 + tail}'); // "十六" → 16
        i += 2;
      } else {
        out.write('10'); // "十周" → 10
        i += 1;
      }
      continue;
    }

    // ── 情形 2：当前字是个位数字（一/二/…/九）──
    if (current != null) {
      if (i + 1 < length && text[i + 1] == '十') {
        final int base = current * 10;
        final int? tail =
            (i + 2 < length) ? _kChineseDigitValue[text[i + 2]] : null;
        if (tail != null) {
          out.write('${base + tail}'); // "二十五" → 25
          i += 3;
        } else {
          out.write('$base'); // "二十" → 20
          i += 2;
        }
        continue;
      }
      out.write('$current'); // "四" → 4
      i += 1;
      continue;
    }

    // ── 情形 3：不是中文数字，原样保留（'第' / '至' / '4' / ',' … 由调用方处理）──
    out.write(text[i]);
    i += 1;
  }
  return out.toString();
}

/// 中文数字 `'０'` 的码位（`'１'` 是 0xFF11，依此类推）。
const int _kFullWidthZero = 0xFF10;

/// 中文数字字符 → 数值。
///
/// `十` **也**在这里映射成 10：它既是位权（`"十六"` 里的十位），
/// 也可以是独立的值（`"第十周"` 就是第 10 周）。
/// [chineseToArabic] 会先特判 `'十'` 作为位权的两种情形，所以这张表里的 10
/// 只在"没有个位可结合"时才被用到。
const Map<String, int> _kChineseDigitValue = <String, int>{
  '〇': 0,
  '零': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
};

// 时间地点模型：描述一次课程安排的上课时间、地点与生效周次

/// 单双周类型。
///
/// 与 [TimePlace.weeks] 配合使用：[weeks] 是**基础周次**（不做单双过滤），
/// 单双周的过滤由 `TimetableLogic.hasClassInWeek` 负责，
/// 这样同一个 [TimePlace] 只保存一份周次数据。
enum WeekType {
  /// 每周都上。
  all,

  /// 单周（奇数周）。
  odd,

  /// 双周（偶数周）。
  even;

  /// 从 JSON 中的字符串安全解析，无法识别时返回 [WeekType.all]。
  static WeekType fromName(Object? value) {
    if (value is WeekType) return value;
    if (value is! String) return WeekType.all;
    final String key = value.trim().toLowerCase();
    for (final WeekType type in WeekType.values) {
      if (type.name == key) return type;
    }
    return WeekType.all;
  }

  /// 中文展示标签。
  String get label {
    switch (this) {
      case WeekType.all:
        return '每周';
      case WeekType.odd:
        return '单周';
      case WeekType.even:
        return '双周';
    }
  }
}

/// 一次课程安排的时间与地点。
///
/// 一节课可能有多个 [TimePlace]（例如单双周在不同教室、
/// 或一周内安排多次），因此 [Course.timePlaces] 是列表。
class TimePlace {
  /// 星期几，1-7 表示周一到周日。
  final int day;

  /// 起始节次，1-12。
  final int startSession;

  /// 持续节数，至少为 1。
  final int length;

  /// 上课地点（教室），可能为空字符串。
  final String room;

  /// 基础周次列表（未按单双周过滤），例如 `[4, 6, 7, 8]`。
  final List<int> weeks;

  /// 原始周次文本，如 `"4,6-14周"`，用于展示与二次解析。
  final String rawWeeksText;

  /// 单双周类型，默认 [WeekType.all]（每周）。
  final WeekType weekType;

  const TimePlace({
    required this.day,
    required this.startSession,
    required this.length,
    required this.room,
    required this.weeks,
    required this.rawWeeksText,
    this.weekType = WeekType.all,
  });

  /// 结束节次（含）。
  int get endSession => startSession + length - 1;

  /// 该安排是否在 [week] 周生效。
  ///
  /// **只看基础周次，不考虑单双周**——需要完整判断请用
  /// `TimetableLogic.hasClassInWeek`。
  bool isActiveInWeek(int week) => weeks.contains(week);

  /// 该安排是否与另一个安排在同一周、同一天且节次重叠。
  bool conflictsWith(TimePlace other) =>
      day == other.day &&
      startSession <= other.endSession &&
      other.startSession <= endSession;

  /// 从 JSON 构造，缺失或类型异常的字段使用安全默认值，不抛异常。
  factory TimePlace.fromJson(Map<String, dynamic> json) {
    return TimePlace(
      day: _asInt(json['day'], fallback: 1),
      startSession: _asInt(json['startSession'], fallback: 1),
      length: _asInt(json['length'], fallback: 1),
      room: _asString(json['room']),
      weeks: _asIntList(json['weeks']),
      rawWeeksText: _asString(json['rawWeeksText']),
      weekType: WeekType.fromName(json['weekType']),
    );
  }

  /// 序列化为可写入 Hive / JSON 的 Map。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'day': day,
      'startSession': startSession,
      'length': length,
      'room': room,
      'weeks': weeks,
      'rawWeeksText': rawWeeksText,
      'weekType': weekType.name,
    };
  }

  TimePlace copyWith({
    int? day,
    int? startSession,
    int? length,
    String? room,
    List<int>? weeks,
    String? rawWeeksText,
    WeekType? weekType,
  }) {
    return TimePlace(
      day: day ?? this.day,
      startSession: startSession ?? this.startSession,
      length: length ?? this.length,
      room: room ?? this.room,
      weeks: weeks ?? this.weeks,
      rawWeeksText: rawWeeksText ?? this.rawWeeksText,
      weekType: weekType ?? this.weekType,
    );
  }

  @override
  String toString() =>
      'TimePlace(day: $day, startSession: $startSession, length: $length, '
      'room: $room, weeks: $weeks, rawWeeksText: $rawWeeksText, '
      'weekType: ${weekType.name})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimePlace &&
        other.day == day &&
        other.startSession == startSession &&
        other.length == length &&
        other.room == room &&
        _listEquals(other.weeks, weeks) &&
        other.rawWeeksText == rawWeeksText &&
        other.weekType == weekType;
  }

  @override
  int get hashCode => Object.hash(
        day,
        startSession,
        length,
        room,
        Object.hashAll(weeks),
        rawWeeksText,
        weekType,
      );
}

/// 安全地把任意值转成 int。
int _asInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

/// 安全地把任意值转成 String。
String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// 安全地把任意值转成 `List<int>`，忽略无法转换的元素。
List<int> _asIntList(Object? value) {
  if (value is! List) return const <int>[];
  final List<int> result = <int>[];
  for (final Object? item in value) {
    if (item is int) {
      result.add(item);
    } else if (item is num) {
      result.add(item.toInt());
    } else if (item is String) {
      final int? parsed = int.tryParse(item.trim());
      if (parsed != null) result.add(parsed);
    }
  }
  return result;
}

/// 列表逐元素比较。
bool _listEquals(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
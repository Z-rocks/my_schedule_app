// 上课提醒：设置解析 + 排期计算（纯逻辑，不碰存储 / 平台通道）。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/class_reminder_settings.dart';
import 'package:my_schedule_app/models/course.dart';
import 'package:my_schedule_app/models/semester_config.dart';
import 'package:my_schedule_app/models/time_place.dart';
import 'package:my_schedule_app/services/class_reminder_plan.dart';

/// 2026-03-02 是周一 —— 固定成常量，测试不依赖"今天是星期几"。
final DateTime kSemesterStart = DateTime(2026, 3, 2);

/// 第 1 周周一 07:00（还没到上课时间）。
final DateTime kMondayMorning = DateTime(2026, 3, 2, 7, 0);

/// 造一个学期：20 周。
SemesterConfig _config({int totalWeeks = 20}) => SemesterConfig(
      name: '2026 春季',
      startDate: kSemesterStart,
      totalWeeks: totalWeeks,
    );

/// 造一门课。默认：周一第 1-2 节，HE-405，全学期每周。
Course _course({
  String id = 'ncst:1',
  String name = '高等数学',
  int day = 1,
  int startSession = 1,
  int length = 2,
  String room = 'HE-405',
  List<int>? weeks,
  WeekType weekType = WeekType.all,
  List<TimePlace>? extraPlaces,
}) {
  final List<TimePlace> places = <TimePlace>[
    TimePlace(
      day: day,
      startSession: startSession,
      length: length,
      room: room,
      weeks: weeks ?? List<int>.generate(20, (int i) => i + 1),
      rawWeeksText: '1-20周',
      weekType: weekType,
    ),
    ...?extraPlaces,
  ];
  return Course(
    id: id,
    name: name,
    teacher: '张老师',
    unit: 4,
    category: '必修',
    timePlaces: places,
    sourcePluginId: 'ncst',
  );
}

/// 内置默认作息（测试只用第 1 / 3 / 5 节）。
const Map<int, String> _sectionTimes = <int, String>{
  1: '08:30-09:15',
  2: '09:20-10:05',
  3: '10:25-11:10',
  5: '14:00-14:45',
};

ClassReminderSettings _on({int offsetMinutes = 15}) =>
    ClassReminderSettings(enabled: true, offsetMinutes: offsetMinutes);

void main() {
  group('ClassReminderSettings', () {
    test('默认：关闭、提前 15 分钟、不生效', () {
      const ClassReminderSettings s = ClassReminderSettings();
      expect(s.enabled, isFalse);
      expect(s.offsetMinutes, kDefaultClassReminderOffset);
      expect(s.isEffective, isFalse);
    });

    test('开关打开且提前量合法才生效', () {
      expect(_on().isEffective, isTrue);
      expect(
        const ClassReminderSettings(enabled: true, offsetMinutes: 0).isEffective,
        isFalse,
      );
    });

    test('JSON 往返一致', () {
      final ClassReminderSettings s = ClassReminderSettings.tryDecode(
        _on(offsetMinutes: 30).encode(),
      );
      expect(s.enabled, isTrue);
      expect(s.offsetMinutes, 30);
    });

    test('坏数据回落默认值（不抛异常）', () {
      expect(ClassReminderSettings.tryDecode(null).enabled, isFalse);
      expect(ClassReminderSettings.tryDecode('').enabled, isFalse);
      expect(ClassReminderSettings.tryDecode('不是 JSON').enabled, isFalse);
      // 是合法 JSON 但不是对象
      expect(ClassReminderSettings.tryDecode('[1,2]').enabled, isFalse);
    });

    test('字段类型不对：开关按关闭、提前量回落默认', () {
      final ClassReminderSettings s =
          ClassReminderSettings.tryDecode('{"enabled":"yes","offsetMinutes":"15"}');
      expect(s.enabled, isFalse);
      expect(s.offsetMinutes, kDefaultClassReminderOffset);
    });

    test('提前量越界回落默认（0 与超过一天都算坏值）', () {
      expect(
        ClassReminderSettings.tryDecode('{"enabled":true,"offsetMinutes":0}')
            .offsetMinutes,
        kDefaultClassReminderOffset,
      );
      expect(
        ClassReminderSettings.tryDecode('{"enabled":true,"offsetMinutes":2000}')
            .offsetMinutes,
        kDefaultClassReminderOffset,
      );
    });
  });

  group('weekOfDate', () {
    test('开学当天是第 1 周', () {
      expect(weekOfDate(_config(), kSemesterStart), 1);
    });

    test('第 7 天仍是第 1 周，第 8 天是第 2 周', () {
      expect(weekOfDate(_config(), DateTime(2026, 3, 8)), 1);
      expect(weekOfDate(_config(), DateTime(2026, 3, 9)), 2);
    });

    test('学期之前返回 < 1（不做 clamp）', () {
      expect(weekOfDate(_config(), DateTime(2026, 3, 1)), lessThan(1));
      expect(weekOfDate(_config(), DateTime(2026, 2, 1)), lessThan(1));
    });

    test('学期之后照常算，超出总周数由调用方过滤', () {
      // 第 21 周（20 周的学期已结束）
      expect(weekOfDate(_config(), DateTime(2026, 7, 20)), greaterThan(20));
    });

    test('忽略时分秒：同一天的任意时刻周次相同', () {
      expect(
        weekOfDate(_config(), DateTime(2026, 3, 9, 23, 59)),
        weekOfDate(_config(), DateTime(2026, 3, 9, 0, 0)),
      );
    });
  });

  group('sessionStartTime', () {
    test('解析标准作息串，取开始时刻', () {
      expect(
        sessionStartTime(kSemesterStart, '08:30-09:15'),
        DateTime(2026, 3, 2, 8, 30),
      );
    });

    test('兼容全角冒号与单位数小时', () {
      expect(
        sessionStartTime(kSemesterStart, '8：30-9：15'),
        DateTime(2026, 3, 2, 8, 30),
      );
    });

    test('解析不出来返回 null（不猜默认值）', () {
      expect(sessionStartTime(kSemesterStart, null), isNull);
      expect(sessionStartTime(kSemesterStart, ''), isNull);
      expect(sessionStartTime(kSemesterStart, '上午'), isNull);
    });

    test('越界时刻返回 null', () {
      expect(sessionStartTime(kSemesterStart, '25:00-26:00'), isNull);
      expect(sessionStartTime(kSemesterStart, '08:75-09:15'), isNull);
    });
  });

  group('buildClassReminderPlan', () {
    test('关闭时返回空排期', () {
      expect(
        buildClassReminderPlan(
          courses: <Course>[_course()],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: const ClassReminderSettings(),
          now: kMondayMorning,
        ),
        isEmpty,
      );
    });

    test('基本排期：课前 15 分钟', () {
      final List<ClassReminderItem> items = buildClassReminderPlan(
        courses: <Course>[_course()],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      );
      expect(items, hasLength(1));
      expect(items.single.fireAt, DateTime(2026, 3, 2, 8, 15));
      expect(items.single.classStart, DateTime(2026, 3, 2, 8, 30));
      expect(items.single.startSession, 1);
      expect(items.single.endSession, 2);
      expect(items.single.courseName, '高等数学');
      expect(items.single.room, 'HE-405');
      expect(items.single.offsetMinutes, 15);
    });

    test('通知文案：分钟 / 小时两种表述', () {
      final ClassReminderItem item = buildClassReminderPlan(
        courses: <Course>[_course()],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      ).single;
      expect(item.title, '高等数学');
      expect(item.body, '15 分钟后上课 · 第 1-2 节 · HE-405 · 08:30');

      final ClassReminderItem hourly = buildClassReminderPlan(
        courses: <Course>[_course()],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(offsetMinutes: 60),
        now: kMondayMorning,
        horizonDays: 1,
      ).single;
      expect(hourly.body, startsWith('1 小时后上课'));
    });

    test('教室为空时正文不出现多余分隔符', () {
      final ClassReminderItem item = buildClassReminderPlan(
        courses: <Course>[_course(room: '')],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      ).single;
      expect(item.body, '15 分钟后上课 · 第 1-2 节 · 08:30');
      expect(item.body, isNot(contains('· ·')));
    });

    test('已经过去的课不排（含 2 秒内的临界限）', () {
      // 08:15 触发，now 已 09:00
      expect(
        buildClassReminderPlan(
          courses: <Course>[_course()],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: DateTime(2026, 3, 2, 9, 0),
          horizonDays: 1,
        ),
        isEmpty,
      );
    });

    test('只排未来 horizonDays 天', () {
      // 周一第 1 节 + 周三第 3 节；horizon 2 天只应看到周一那条
      final Course course = _course(
        extraPlaces: <TimePlace>[
          TimePlace(
            day: 3,
            startSession: 3,
            length: 2,
            room: 'HE-406',
            weeks: List<int>.generate(20, (int i) => i + 1),
            rawWeeksText: '1-20周',
          ),
        ],
      );
      final List<ClassReminderItem> twoDays = buildClassReminderPlan(
        courses: <Course>[course],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 2,
      );
      expect(twoDays, hasLength(1));
      expect(twoDays.single.fireAt, DateTime(2026, 3, 2, 8, 15));

      final List<ClassReminderItem> fullWeek = buildClassReminderPlan(
        courses: <Course>[course],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 7,
      );
      expect(fullWeek, hasLength(2));
      expect(fullWeek.last.fireAt, DateTime(2026, 3, 4, 10, 10));
    });

    test('按触发时刻升序返回', () {
      final Course course = _course(
        extraPlaces: <TimePlace>[
          TimePlace(
            day: 2,
            startSession: 5,
            length: 2,
            room: 'HE-1',
            weeks: List<int>.generate(20, (int i) => i + 1),
            rawWeeksText: '1-20周',
          ),
        ],
      );
      final List<ClassReminderItem> items = buildClassReminderPlan(
        courses: <Course>[course],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 7,
      );
      for (int i = 1; i < items.length; i++) {
        expect(
          items[i].fireAt.isBefore(items[i - 1].fireAt),
          isFalse,
          reason: '第 $i 条比前一条更早',
        );
      }
    });

    test('学期之外的日期不排（开学前 / 学期结束后）', () {
      // 开学前一周
      expect(
        buildClassReminderPlan(
          courses: <Course>[_course()],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: DateTime(2026, 2, 23, 7, 0),
          horizonDays: 7,
        ),
        isEmpty,
      );
      // 20 周学期结束之后（2026-07-20 是第 21 周周一）
      expect(
        buildClassReminderPlan(
          courses: <Course>[_course()],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: DateTime(2026, 7, 20, 7, 0),
          horizonDays: 7,
        ),
        isEmpty,
      );
    });

    test('单周课在双周不排', () {
      final Course course = _course(
        weeks: List<int>.generate(20, (int i) => i + 1),
        weekType: WeekType.odd,
      );
      // 2026-03-09 是第 2 周（双周）
      expect(
        buildClassReminderPlan(
          courses: <Course>[course],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: DateTime(2026, 3, 9, 7, 0),
          horizonDays: 1,
        ),
        isEmpty,
      );
      // 2026-03-16 是第 3 周（单周）
      expect(
        buildClassReminderPlan(
          courses: <Course>[course],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: DateTime(2026, 3, 16, 7, 0),
          horizonDays: 1,
        ),
        hasLength(1),
      );
    });

    test('缺该节作息时跳过，不用默认值猜时间', () {
      // 第 7 节不在 _sectionTimes 里
      expect(
        buildClassReminderPlan(
          courses: <Course>[_course(startSession: 7)],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: kMondayMorning,
          horizonDays: 1,
        ),
        isEmpty,
      );
    });

    test('同一门课同一天同一节的重复 TimePlace 只排一次（合班课去重）', () {
      final Course course = _course(
        extraPlaces: <TimePlace>[
          TimePlace(
            day: 1,
            startSession: 1,
            length: 2,
            room: 'HE-405',
            weeks: List<int>.generate(20, (int i) => i + 1),
            rawWeeksText: '1-20周',
          ),
        ],
      );
      expect(
        buildClassReminderPlan(
          courses: <Course>[course],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: kMondayMorning,
          horizonDays: 1,
        ),
        hasLength(1),
      );
    });

    test('被隐藏的课由调用方过滤（本函数不看 isHidden）', () {
      // 这里只确认"不主动读 userOverride"——隐藏过滤在 Provider 层做。
      final Course hidden = _course(id: 'ncst:2');
      final List<ClassReminderItem> items = buildClassReminderPlan(
        courses: <Course>[hidden],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      );
      expect(items, hasLength(1));
    });

    test('多门课各自独立排期', () {
      final List<ClassReminderItem> items = buildClassReminderPlan(
        courses: <Course>[
          _course(id: 'ncst:1', name: '高等数学'),
          _course(id: 'ncst:2', name: '大学物理', startSession: 3, room: 'HE-201'),
        ],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      );
      expect(items, hasLength(2));
      expect(items.first.fireAt, DateTime(2026, 3, 2, 8, 15));
      expect(items.last.fireAt, DateTime(2026, 3, 2, 10, 10));
    });

    test('课表为空时返回空排期', () {
      expect(
        buildClassReminderPlan(
          courses: const <Course>[],
          config: _config(),
          sectionTimes: _sectionTimes,
          settings: _on(),
          now: kMondayMorning,
        ),
        isEmpty,
      );
    });

    test('toJson 含原生需要的全部字段', () {
      final Map<String, dynamic> json = buildClassReminderPlan(
        courses: <Course>[_course()],
        config: _config(),
        sectionTimes: _sectionTimes,
        settings: _on(),
        now: kMondayMorning,
        horizonDays: 1,
      ).single.toJson();

      expect(json['requestCode'], isA<int>());
      expect(json['courseId'], 'ncst:1');
      expect(json['courseName'], '高等数学');
      expect(json['room'], 'HE-405');
      expect(json['startSession'], 1);
      expect(json['endSession'], 2);
      expect(json['offsetMinutes'], 15);
      expect(
        json['fireAtMillis'],
        DateTime(2026, 3, 2, 8, 15).millisecondsSinceEpoch,
      );
      // 文案直接给原生用，原生不再拼一遍
      expect(json['title'], '高等数学');
      expect(json['body'], contains('08:30'));
    });
  });

  group('classReminderRequestCode', () {
    test('同输入恒定（重排时能覆盖旧闹钟）', () {
      int call() => classReminderRequestCode(
            courseId: 'ncst:1',
            day: kSemesterStart,
            startSession: 1,
            offsetMinutes: 15,
          );
      expect(call(), call());
    });

    test('忽略时分秒，只看年月日', () {
      expect(
        classReminderRequestCode(
          courseId: 'ncst:1',
          day: DateTime(2026, 3, 2, 0, 0),
          startSession: 1,
          offsetMinutes: 15,
        ),
        classReminderRequestCode(
          courseId: 'ncst:1',
          day: DateTime(2026, 3, 2, 23, 59),
          startSession: 1,
          offsetMinutes: 15,
        ),
      );
    });

    test('课程 / 日期 / 节次 / 提前量任一不同就换值', () {
      final int base = classReminderRequestCode(
        courseId: 'ncst:1',
        day: kSemesterStart,
        startSession: 1,
        offsetMinutes: 15,
      );
      final Set<int> others = <int>{
        classReminderRequestCode(
          courseId: 'ncst:2',
          day: kSemesterStart,
          startSession: 1,
          offsetMinutes: 15,
        ),
        classReminderRequestCode(
          courseId: 'ncst:1',
          day: DateTime(2026, 3, 3),
          startSession: 1,
          offsetMinutes: 15,
        ),
        classReminderRequestCode(
          courseId: 'ncst:1',
          day: kSemesterStart,
          startSession: 3,
          offsetMinutes: 15,
        ),
        classReminderRequestCode(
          courseId: 'ncst:1',
          day: kSemesterStart,
          startSession: 1,
          offsetMinutes: 30,
        ),
      };
      expect(others, hasLength(4), reason: '四个维度都要能区分开');
      expect(others.contains(base), isFalse);
    });

    test('始终是正的 30 位整数（PendingIntent requestCode 是 Int）', () {
      for (int day = 1; day <= 28; day++) {
        final int code = classReminderRequestCode(
          courseId: 'ncst:课程:$day',
          day: DateTime(2026, 3, day),
          startSession: day % 12 + 1,
          offsetMinutes: 15,
        );
        expect(code, greaterThanOrEqualTo(0));
        expect(code, lessThan(1 << 30));
      }
    });
  });
}

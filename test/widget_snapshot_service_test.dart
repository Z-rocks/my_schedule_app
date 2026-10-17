// 小组件快照服务单元测试（Phase W1 / P1.4）。
//
// 覆盖拆解文档 P1.4 列出的边界：空数据、隐藏课程、单双周、周次越界、
// 本周无课、作业全部完成、无截止时间、颜色兜底与预截断。
import 'package:flutter_test/flutter_test.dart';

import 'package:my_schedule_app/models/course.dart';
import 'package:my_schedule_app/models/exam.dart';
import 'package:my_schedule_app/models/homework.dart';
import 'package:my_schedule_app/models/semester_config.dart';
import 'package:my_schedule_app/models/time_place.dart';
import 'package:my_schedule_app/models/user_override.dart';
import 'package:my_schedule_app/services/section_time_service.dart';
import 'package:my_schedule_app/services/widget_snapshot_service.dart';

void main() {
  // 学期：2026-10-12（周一）开学，共 20 周。
  final SemesterConfig semester = SemesterConfig(
    name: '2026-2027学年第一学期',
    startDate: DateTime(2026, 10, 12),
    totalWeeks: 20,
  );

  Course makeCourse({
    String id = 'ncst:1',
    String name = '高等数学',
    String room = '教三101',
    int day = 3, // 周三
    int startSession = 3,
    int length = 2,
    List<int>? weeks,
    WeekType weekType = WeekType.all,
    int? customColor,
    bool hidden = false,
    String? customName,
  }) {
    return Course(
      id: id,
      name: name,
      teacher: '张三',
      unit: 3,
      category: '必修',
      timePlaces: <TimePlace>[
        TimePlace(
          day: day,
          startSession: startSession,
          length: length,
          room: room,
          weeks: weeks ?? List<int>.generate(20, (int i) => i + 1),
          rawWeeksText: '1-20周',
          weekType: weekType,
        ),
      ],
      sourcePluginId: 'ncst',
      userOverride: (customColor != null || hidden || customName != null)
          ? UserOverride(
              customColor: customColor,
              hidden: hidden,
              customName: customName,
              updatedAt: DateTime(2026, 10, 1),
            )
          : null,
    );
  }

  group('空数据', () {
    test('无学期无课程：week=1、scheduleEmpty、计数为 0', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: null,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> json = snapshot.toJson();

      expect(json['version'], 1);
      expect(json['hasSemester'], false);
      expect(json['week'], 1);
      expect(json['scheduleEmpty'], true);
      expect(json['today'], 3);
      expect(json['todayLabel'], '周三');
      expect(json['updatedLabel'], '更新于 09:00');
      expect((json['homework'] as Map)['pendingCount'], 0);
      expect((json['exam'] as Map)['upcomingCount'], 0);
    });
  });

  group('课表快照', () {
    test('周三 3-4 节课程：todaySessions 合并成一段、网格索引正确', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: <Course>[makeCourse()],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0), // 第 1 周周三
      );
      final Map<String, dynamic> json = snapshot.toJson();
      final Map<String, dynamic> schedule =
          json['schedule'] as Map<String, dynamic>;

      expect(json['scheduleEmpty'], false);
      expect(json['week'], 1);

      final List<dynamic> sessions =
          schedule['todaySessions'] as List<dynamic>;
      expect(sessions.length, 1);
      final Map<String, dynamic> first =
          sessions.first as Map<String, dynamic>;
      expect(first['courseIdx'], 0);
      expect(first['session'], 3);
      expect(first['length'], 2);
      expect(first['sectionText'], '3-4节');

      final List<dynamic> table =
          schedule['courseTable'] as List<dynamic>;
      expect((table.first as Map)['name'], '高等数学');
      expect((table.first as Map)['room'], '教三101');

      // cells[周三-1][3-1] 与 [周三-1][4-1] 都是课程 0；周一第 1 节为空。
      final List<dynamic> cells = schedule['cells'] as List<dynamic>;
      expect((cells[2] as List)[2], 0);
      expect((cells[2] as List)[3], 0);
      expect((cells[0] as List)[0], -1);
      expect(schedule['maxSession'], 4);
    });

    test('插件作息：sectionText 带上起止时间', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: <Course>[makeCourse()],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        sectionTimes: const SectionTimes(
          times: <int, String>{3: '10:25-11:10', 4: '11:15-12:00'},
          pluginId: 'ncst',
          pluginName: 'NCST',
        ),
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> schedule =
          snapshot.toJson()['schedule'] as Map<String, dynamic>;
      final Map<String, dynamic> first =
          (schedule['todaySessions'] as List).first as Map<String, dynamic>;
      expect(first['sectionText'], '3-4节 10:25-12:00');

      final Map<String, dynamic> sectionTimesJson =
          snapshot.toJson()['sectionTimes'] as Map<String, dynamic>;
      expect(sectionTimesJson['3'], '10:25-11:10');
    });

    test('隐藏课程不出现在网格里（双重防御）', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: <Course>[makeCourse(hidden: true)],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> schedule =
          snapshot.toJson()['schedule'] as Map<String, dynamic>;
      expect((schedule['courseTable'] as List).isEmpty, true);
      expect((schedule['todaySessions'] as List).isEmpty, true);
    });

    test('单双周课：双周本周没课（scheduleEmpty 仍为 false）、单周才有', () {
      final Course course = makeCourse(weekType: WeekType.odd);
      // 2026-10-14 = 第 1 周周三（单周）→ 有课
      final WidgetSnapshot week1 = WidgetSnapshotService.build(
        courses: <Course>[course],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      expect(week1.toJson()['weekHasClass'], true);
      expect(((week1.toJson()['schedule'] as Map)['todaySessions'] as List)
          .isNotEmpty, true);

      // 2026-10-21 = 第 2 周周三（双周）→ 本周没课，但有这门课
      // （scheduleEmpty=false、weekHasClass=false，卡片该显示"本周没课"）。
      final WidgetSnapshot week2 = WidgetSnapshotService.build(
        courses: <Course>[course],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 21, 9, 0),
      );
      expect(((week2.toJson()['schedule'] as Map)['todaySessions'] as List)
          .isEmpty, true);
      expect(week2.toJson()['scheduleEmpty'], false);
      expect(week2.toJson()['weekHasClass'], false);
    });

    test('只在第 2 周有课的课：第 3 周起 weekHasClass=false 但课表非空', () {
      final Course course = makeCourse(weeks: const <int>[2]);
      // 2026-10-28 = 第 3 周周三 → 本周整周无课
      final WidgetSnapshot week3 = WidgetSnapshotService.build(
        courses: <Course>[course],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 28, 9, 0),
      );
      expect(week3.toJson()['week'], 3);
      expect(week3.toJson()['scheduleEmpty'], false);
      expect(week3.toJson()['weekHasClass'], false);
      expect(((week3.toJson()['schedule'] as Map)['todaySessions'] as List)
          .isEmpty, true);
    });

    test('学期未开始：week 钳到 1', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: <Course>[makeCourse()],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 9, 30, 9, 0), // 开学前
      );
      expect(snapshot.toJson()['week'], 1);
    });

    test('用户自定义色优先；缺省按课程 ID 哈希稳定取色', () {
      // 自定义色：快照里必须原样出现。
      final Course custom = makeCourse(customColor: 0xFF123456);
      final Map<String, dynamic> customJson = WidgetSnapshotService.build(
        courses: <Course>[custom],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      ).toJson();
      final List<dynamic> table =
          (customJson['schedule'] as Map)['courseTable'] as List<dynamic>;
      expect((table.first as Map<String, dynamic>)['color'],
          custom.displayColor);

      // 缺省色：同一门课两次生成必须同色（哈希稳定），且确实落在兜底色板里。
      final Course plain = makeCourse(id: 'ncst:2');
      int colorOf(WidgetSnapshot s) =>
          (((s.toJson()['schedule'] as Map<String, dynamic>)['courseTable']
                  as List<dynamic>)
              .first as Map<String, dynamic>)['color'] as int;
      final int colorA = colorOf(WidgetSnapshotService.build(
        courses: <Course>[plain],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      ));
      final int colorB = colorOf(WidgetSnapshotService.build(
        courses: <Course>[plain],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 15, 9, 0), // 换个时间也一样
      ));
      expect(colorA, colorB);
      expect(kWidgetFallbackPalette.contains(colorA), true);
    });
  });

  group('作业快照', () {
    Homework makeHomework({
      String id = 'chaoxing:1',
      String title = '实验报告',
      String courseName = '物理',
      DateTime? deadline,
      bool completed = false,
    }) {
      return Homework(
        id: id,
        title: title,
        courseName: courseName,
        deadline: deadline,
        completed: completed,
        sourcePluginId: 'chaoxing',
      );
    }

    test('已完成沉底、逾期标红、无截止给"无截止"', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: semester,
        homeworks: <Homework>[
          makeHomework(
            id: 'a',
            title: '旧作业',
            deadline: DateTime(2026, 10, 10, 23, 59), // 已逾期
          ),
          makeHomework(
            id: 'b',
            title: '今晚截止',
            deadline: DateTime(2026, 10, 14, 23, 59), // 今天
          ),
          makeHomework(id: 'c', title: '无截止时间'),
          makeHomework(
            id: 'd',
            title: '已完成的',
            deadline: DateTime(2026, 10, 20),
            completed: true,
          ),
        ],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> homework =
          snapshot.toJson()['homework'] as Map<String, dynamic>;

      expect(homework['pendingCount'], 3);
      expect(homework['overdueCount'], 1);

      final List<dynamic> items = homework['items'] as List<dynamic>;
      expect(items.length, 3); // top 5 cap 内的全部未交
      expect((items[0] as Map)['title'], '旧作业');
      expect((items[0] as Map)['overdue'], true);
      expect((items[0] as Map)['daysLeftText'], '已逾期');
      expect((items[1] as Map)['daysLeftText'], '今天截止');
      expect((items[2] as Map)['daysLeftText'], '无截止');
    });

    test('全部完成：pending 0、items 空', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: semester,
        homeworks: <Homework>[
          Homework(
            id: 'a',
            title: '已完成的',
            completed: true,
            sourcePluginId: 'user',
          ),
        ],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> homework =
          snapshot.toJson()['homework'] as Map<String, dynamic>;
      expect(homework['pendingCount'], 0);
      expect((homework['items'] as List).isEmpty, true);
    });

    test('超长标题预截断到 20 字 + 省略号', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: semester,
        homeworks: <Homework>[
          Homework(
            id: 'a',
            title: '数据结构与算法第三次上机实验报告一二三四五',
            sourcePluginId: 'user',
          ),
        ],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> item =
          ((snapshot.toJson()['homework'] as Map)['items'] as List).first
              as Map<String, dynamic>;
      // 21 字标题 → 前 20 字 + 省略号（Kotlin 的 ellipsize 对超长单词不可靠，
      // 所以在 Dart 侧预截断）。
      expect(item['title'], '数据结构与算法第三次上机实验报告一二三四…');
    });
  });

  group('考试快照', () {
    Exam makeExam({
      String id = 'chaoxing:e1',
      String name = '线性代数',
      String location = '教一201',
      required DateTime start,
    }) {
      return Exam(
        id: id,
        name: name,
        location: location,
        startTime: start,
        sourcePluginId: 'chaoxing',
      );
    }

    test('未开始的才进快照，已开始剔除；输入按开考时间升序（同 Provider 契约）', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: semester,
        homeworks: const <Homework>[],
        exams: <Exam>[
          // 传入顺序即 displayExams 的顺序：未开始优先、开考时间升序。
          makeExam(id: 'b', start: DateTime(2026, 10, 30, 9, 0)), // 16 天后
          makeExam(id: 'a', start: DateTime(2026, 11, 5, 9, 0)), // 22 天后
          makeExam(id: 'c', start: DateTime(2026, 10, 13, 9, 0)), // 已开始
        ],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> exam =
          snapshot.toJson()['exam'] as Map<String, dynamic>;

      expect(exam['upcomingCount'], 2);
      final List<dynamic> items = exam['items'] as List<dynamic>;
      expect(items.length, 2);
      expect((items[0] as Map)['name'], '线性代数');
      expect((items[0] as Map)['location'], '教一201');
      expect((items[0] as Map)['startText'], '10-30 09:00');
      expect((items[0] as Map)['daysLeftText'], '16天后');
    });

    test('没有任何考试：items 空', () {
      final WidgetSnapshot snapshot = WidgetSnapshotService.build(
        courses: const <Course>[],
        semester: semester,
        homeworks: const <Homework>[],
        exams: const <Exam>[],
        now: DateTime(2026, 10, 14, 9, 0),
      );
      final Map<String, dynamic> exam =
          snapshot.toJson()['exam'] as Map<String, dynamic>;
      expect(exam['upcomingCount'], 0);
      expect((exam['items'] as List).isEmpty, true);
    });
  });
}

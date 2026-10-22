// 课表重叠课程的布局测试。
//
// 背景（用户反馈）：同一时间有两门课时课表上只显示一节，另一门彻底消失。
// 根因是 `buildGrid` 每格只能存一个 `Course?`，后到的课被 `??=` 丢掉。
//
// 修法分两层，本文件两层都测：
// 1. 逻辑层 `TimetableLogic.buildCellGrid` / `layoutBlocks` 保留全部课程，
//    并给重叠块分配并排槽位（slotIndex / slotCount）；
// 2. 渲染层 `TimetableGrid` 按槽位把卡片压成半宽并排，两门课都看得见。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/course.dart';
import 'package:my_schedule_app/models/time_place.dart';
import 'package:my_schedule_app/models/user_override.dart';
import 'package:my_schedule_app/services/timetable_logic.dart';
import 'package:my_schedule_app/theme/app_theme.dart';
import 'package:my_schedule_app/widgets/timetable_grid.dart';

/// 构造一门课（默认周一 3-4 节，第 5 周有课）。
Course makeCourse({
  required String id,
  String? name,
  int day = 1,
  int startSession = 3,
  int length = 2,
  String room = 'HE-405',
  List<int> weeks = const <int>[5],
  WeekType weekType = WeekType.all,
  bool hidden = false,
}) {
  return Course(
    id: id,
    name: name ?? id,
    teacher: '张老师',
    unit: 3,
    category: '必修',
    timePlaces: <TimePlace>[
      TimePlace(
        day: day,
        startSession: startSession,
        length: length,
        room: room,
        weeks: weeks,
        rawWeeksText: weeks.join(','),
        weekType: weekType,
      ),
    ],
    sourcePluginId: 'test',
    userOverride: hidden
        ? UserOverride(hidden: true, updatedAt: DateTime(2026, 1, 1))
        : null,
  );
}

void main() {
  group('buildCellGrid：不再丢弃重叠课程', () {
    test('同一格两门课都保留（buildGrid 只留一门）', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 2),
        makeCourse(id: 'b', startSession: 3, length: 2),
      ];

      final List<List<List<TimetableCell>>> cells =
          TimetableLogic.buildCellGrid(courses, 5);
      expect(cells[1][3].length, 2, reason: '第 3 节应同时属于 a 和 b');
      expect(cells[1][4].length, 2);

      // 对照：旧的单值网格只剩先到的那门
      final List<List<Course?>> grid = TimetableLogic.buildGrid(courses, 5);
      expect(grid[1][3]!.id, 'a');
    });

    test('跨节填充复用同一个实例（上层靠 identical 判断块顶）', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 3),
      ];

      final List<List<List<TimetableCell>>> cells =
          TimetableLogic.buildCellGrid(courses, 5);
      expect(identical(cells[1][3].single, cells[1][4].single), isTrue);
      expect(identical(cells[1][3].single, cells[1][5].single), isTrue);
    });

    test('同一门课两段不同节次是两个独立实例', () {
      final Course course = Course(
        id: 'a',
        name: 'a',
        teacher: '张老师',
        unit: 3,
        category: '必修',
        timePlaces: <TimePlace>[
          const TimePlace(
            day: 1,
            startSession: 3,
            length: 2,
            room: 'HE-405',
            weeks: <int>[5],
            rawWeeksText: '5',
          ),
          const TimePlace(
            day: 1,
            startSession: 7,
            length: 2,
            room: 'HE-405',
            weeks: <int>[5],
            rawWeeksText: '5',
          ),
        ],
        sourcePluginId: 'test',
      );

      final List<List<List<TimetableCell>>> cells =
          TimetableLogic.buildCellGrid(<Course>[course], 5);
      expect(identical(cells[1][3].single, cells[1][7].single), isFalse);
    });

    test('隐藏课程不进入网格', () {
      final List<List<List<TimetableCell>>> cells =
          TimetableLogic.buildCellGrid(
        <Course>[makeCourse(id: 'a', hidden: true)],
        5,
      );
      expect(cells[1][3], isEmpty);
    });

    test('单双周过滤仍然生效', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', weeks: const <int>[4, 5], weekType: WeekType.odd),
      ];
      expect(TimetableLogic.buildCellGrid(courses, 5)[1][3], hasLength(1));
      expect(TimetableLogic.buildCellGrid(courses, 4)[1][3], isEmpty);
    });
  });

  group('layoutBlocks：重叠课程并排分槽', () {
    test('两门课完全重叠 → 两块、各占 2 槽中的一槽', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 2),
        makeCourse(id: 'b', startSession: 3, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks, hasLength(2), reason: '两门课都要出现，不能只剩一门');
      for (final TimetableBlock block in blocks) {
        expect(block.slotCount, 2);
        expect(block.length, 2);
      }
      expect(
        blocks.map((TimetableBlock b) => b.slotIndex).toSet(),
        <int>{0, 1},
        reason: '两门课必须分到不同槽位，否则还是互相盖住',
      );
    });

    test('只重叠一格（A 3-4 + B 4-5）也分成两槽', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 2),
        makeCourse(id: 'b', startSession: 4, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks, hasLength(2));
      expect(blocks.every((TimetableBlock b) => b.slotCount == 2), isTrue);
      expect(
        blocks.map((TimetableBlock b) => b.slotIndex).toSet(),
        <int>{0, 1},
      );
    });

    test('不重叠的课单独占满整列', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 1, length: 2),
        makeCourse(id: 'b', startSession: 6, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks, hasLength(2));
      expect(blocks.every((TimetableBlock b) => b.slotCount == 1), isTrue);
      expect(blocks.every((TimetableBlock b) => b.slotIndex == 0), isTrue);
    });

    test('重叠组之间的空隙会切断分组（前后互不影响）', () {
      // a、b 在 3-4 节重叠；c 在 8-9 节，离得远，不该被算进同一个组
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 2),
        makeCourse(id: 'b', startSession: 3, length: 2),
        makeCourse(id: 'c', startSession: 8, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);
      final TimetableBlock c =
          blocks.firstWhere((TimetableBlock b) => b.course.id == 'c');

      expect(c.slotCount, 1, reason: 'c 不该被前面那组挤成半宽');
      expect(c.slotIndex, 0);
    });

    test('三门同时重叠 → 三槽均分', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 3, length: 2),
        makeCourse(id: 'b', startSession: 3, length: 2),
        makeCourse(id: 'c', startSession: 3, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks, hasLength(3));
      expect(blocks.every((TimetableBlock b) => b.slotCount == 3), isTrue);
      expect(
        blocks.map((TimetableBlock b) => b.slotIndex).toSet(),
        <int>{0, 1, 2},
      );
    });

    test('长课横跨时，短课复用空出来的槽而不是无限加宽', () {
      // a 占 1-6 节；b 1-2；c 3-4。b 结束后槽位空出来，c 应复用 b 的槽，
      // 于是整组只需 2 槽（a 一槽、b/c 轮流用另一槽），而不是 3 槽。
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', startSession: 1, length: 6),
        makeCourse(id: 'b', startSession: 1, length: 2),
        makeCourse(id: 'c', startSession: 3, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks.every((TimetableBlock b) => b.slotCount == 2), isTrue);
      final TimetableBlock a =
          blocks.firstWhere((TimetableBlock b) => b.course.id == 'a');
      final TimetableBlock c =
          blocks.firstWhere((TimetableBlock b) => b.course.id == 'c');
      expect(a.slotIndex, 0);
      expect(c.slotIndex, 1, reason: 'c 应接在 b 让出的槽上');
    });

    test('跨节课程只算一块（不在每一节重复出卡片）', () {
      final List<TimetableBlock> blocks = TimetableLogic.layoutBlocks(
        <Course>[makeCourse(id: 'a', startSession: 3, length: 4)],
        5,
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.startSession, 3);
      expect(blocks.single.length, 4);
    });

    test('同一门课两段不同节次 → 两块（不并成 3-6 节）', () {
      final Course course = Course(
        id: 'a',
        name: 'a',
        teacher: '张老师',
        unit: 3,
        category: '必修',
        timePlaces: <TimePlace>[
          const TimePlace(
            day: 1,
            startSession: 3,
            length: 2,
            room: 'HE-405',
            weeks: <int>[5],
            rawWeeksText: '5',
          ),
          const TimePlace(
            day: 1,
            startSession: 5,
            length: 2,
            room: 'HE-406',
            weeks: <int>[5],
            rawWeeksText: '5',
          ),
        ],
        sourcePluginId: 'test',
      );

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(<Course>[course], 5);

      expect(blocks, hasLength(2));
      expect(blocks[0].startSession, 3);
      expect(blocks[1].startSession, 5);
    });

    test('不同天的课互不干扰（只按天分组）', () {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', day: 1, startSession: 3, length: 2),
        makeCourse(id: 'b', day: 2, startSession: 3, length: 2),
      ];

      final List<TimetableBlock> blocks =
          TimetableLogic.layoutBlocks(courses, 5);

      expect(blocks, hasLength(2));
      expect(blocks.every((TimetableBlock b) => b.slotCount == 1), isTrue);
    });

    test('本周没课 → 空列表', () {
      final List<TimetableBlock> blocks = TimetableLogic.layoutBlocks(
        <Course>[makeCourse(id: 'a', weeks: const <int>[1, 2])],
        5,
      );
      expect(blocks, isEmpty);
    });

    test('结果确定：输入顺序颠倒，左右位置不变', () {
      final List<Course> forward = <Course>[
        makeCourse(id: 'a', startSession: 3),
        makeCourse(id: 'b', startSession: 3),
      ];
      final List<Course> reversed = forward.reversed.toList();

      String describe(List<TimetableBlock> blocks) => blocks
          .map((TimetableBlock b) => '${b.course.id}:${b.slotIndex}')
          .join(',');

      expect(
        describe(TimetableLogic.layoutBlocks(reversed, 5)),
        describe(TimetableLogic.layoutBlocks(forward, 5)),
        reason: '顺序不稳定会让卡片左右跳',
      );
    });
  });

  group('assignSlots：单独校验分槽算法', () {
    test('空输入返回空', () {
      expect(TimetableLogic.assignSlots(<TimetableBlock>[]), isEmpty);
    });

    test('不改动传入的块（返回新列表）', () {
      final Course course = makeCourse(id: 'a');
      final List<TimetableBlock> input = <TimetableBlock>[
        TimetableBlock(
          course: course,
          day: 1,
          startSession: 3,
          length: 2,
          timePlace: course.timePlaces.first,
        ),
      ];

      final List<TimetableBlock> out = TimetableLogic.assignSlots(input);
      expect(out, hasLength(1));
      expect(input.single.slotCount, 1);
    });
  });

  group('TimetableGrid 渲染：两门重叠课都画出来', () {
    /// 默认主题下的几何参数（与 `TimetableGrid.build` 同一套算式）。
    ({double timeColumnWidth, double columnWidth, double cardWidth}) geometry() {
      final AppTheme theme = AppTheme.defaultTheme();
      const double screenWidth = 800;
      final int dayCount = theme.showWeekend ? 7 : 5;
      final double columnWidth =
          (screenWidth - theme.timetableTimeColumnWidth) / dayCount;
      final double usable = columnWidth - kCardInset * 2;
      return (
        timeColumnWidth: theme.timetableTimeColumnWidth,
        columnWidth: columnWidth,
        cardWidth: usable / 2 - kOverlapGap,
      );
    }

    Future<void> pumpGrid(
      WidgetTester tester,
      List<Course> courses,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableGrid(
              blocks: TimetableLogic.layoutBlocks(courses, 5),
              sectionTimes: const <int, String>{3: '10:00-10:45'},
              currentWeek: 5,
            ),
          ),
        ),
      );
    }

    testWidgets('重叠的两门课同时出现，且各占半宽并排', (WidgetTester tester) async {
      final List<Course> courses = <Course>[
        makeCourse(id: 'a', name: '大学物理实验', startSession: 3, length: 2),
        makeCourse(id: 'b', name: '高等数学', startSession: 3, length: 2),
      ];
      await pumpGrid(tester, courses);

      // 两门课的课程名都在 → 没有一门被另一门盖掉
      expect(find.text('大学物理实验'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);

      // 卡片 Key 格式：course.id-day-startSession-slotIndex-week
      final Rect rectA = tester.getRect(find.byKey(const ValueKey<String>(
        'a-1-3-0-5',
      )));
      final Rect rectB = tester.getRect(find.byKey(const ValueKey<String>(
        'b-1-3-1-5',
      )));

      expect(rectA.top, rectB.top, reason: '同一时间开始，顶部应齐平');
      expect(rectA.width, closeTo(rectB.width, 0.5));
      expect(rectA.right, lessThanOrEqualTo(rectB.left),
          reason: '两槽不能重叠，否则还是互相遮挡');

      final ({double timeColumnWidth, double columnWidth, double cardWidth}) g =
          geometry();
      expect(rectA.width, closeTo(g.cardWidth, 0.5),
          reason: '并排时应压到约半列宽');

      // 两槽合起来仍然落在"周一"这一列内
      final double columnLeft = g.timeColumnWidth;
      final double columnRight = g.timeColumnWidth + g.columnWidth;
      expect(rectA.left, greaterThanOrEqualTo(columnLeft));
      expect(rectB.right, lessThanOrEqualTo(columnRight));
    });

    testWidgets('不重叠的课占满整列（回归：改动没影响普通卡片）',
        (WidgetTester tester) async {
      final List<Course> courses = <Course>[
        makeCourse(id: 'solo', name: '线性代数', startSession: 3, length: 2),
      ];
      await pumpGrid(tester, courses);

      expect(find.text('线性代数'), findsOneWidget);
      final Rect rect = tester.getRect(
        find.byKey(const ValueKey<String>('solo-1-3-0-5')),
      );
      final AppTheme theme = AppTheme.defaultTheme();
      const double screenWidth = 800;
      final int dayCount = theme.showWeekend ? 7 : 5;
      final double columnWidth =
          (screenWidth - theme.timetableTimeColumnWidth) / dayCount;
      expect(rect.width, closeTo(columnWidth - kCardInset * 2, 0.5));
    });

  });
}

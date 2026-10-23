// 多学期归档：id 派生 / 兼容旧数据 / 归档与切换 / 课程归属。
//
// 重点在**兼容性**：旧课程没有 `semesterId`、旧学期没有 `id`。
// 这几条一旦处理错，升级后课表会变空、或者换学期后旧课跑到新学期里去，
// 所以每个兼容规则都有专门的用例。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/course.dart';
import 'package:my_schedule_app/models/semester_config.dart';
import 'package:my_schedule_app/models/time_place.dart';
import 'package:my_schedule_app/services/semester_archive_service.dart';
import 'package:my_schedule_app/services/storage_service.dart';

/// 2026 秋：2026-09-07 是周一。
final DateTime kAutumnStart = DateTime(2026, 9, 7);

/// 2027 春：2027-02-22 是周一。
final DateTime kSpringStart = DateTime(2027, 2, 22);

SemesterConfig _autumn() => SemesterConfig(
      name: '2026-2027 学年第一学期',
      startDate: kAutumnStart,
      totalWeeks: 20,
    );

SemesterConfig _spring() => SemesterConfig(
      name: '2026-2027 学年第二学期',
      startDate: kSpringStart,
      totalWeeks: 18,
    );

/// 一门最简课程（只有 id 和名字，够用来验证归属）。
Course _course(String id, {String semesterId = ''}) => Course(
      id: id,
      name: '课程 $id',
      teacher: '',
      unit: 2,
      category: '必修',
      timePlaces: const <TimePlace>[],
      sourcePluginId: 'ncst',
      semesterId: semesterId,
    );

/// 往 `courses` Box 里塞一条"原始 JSON"（模拟旧版本落盘的样子）。
Future<void> seedCourseJson(
  String id, {
  String? semesterId,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  final Map<String, dynamic> json = <String, dynamic>{
    'id': id,
    'name': '课程 $id',
    'teacher': '张老师',
    'unit': 4,
    'category': '必修',
    'timePlaces': <Map<String, dynamic>>[],
    'sourcePluginId': 'ncst',
    'semesterId': ?semesterId,
    ...extra,
  };
  return StorageService.coursesBox.put(id, jsonEncode(json));
}

/// 读回 Box 里的课程 JSON。
Map<String, dynamic> readCourseJson(String id) =>
    jsonDecode(StorageService.coursesBox.get(id)!) as Map<String, dynamic>;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('semester_archive_test_');
    await StorageService.init(path: tmp.path);
  });

  tearDown(() async {
    await StorageService.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('deriveSemesterId', () {
    test('同输入恒定（跨设备 / 跨进程一致）', () {
      expect(
        deriveSemesterId('2026 秋', kAutumnStart),
        deriveSemesterId('2026 秋', kAutumnStart),
      );
    });

    test('忽略时分秒：改个几点钟还是同一个学期', () {
      expect(
        deriveSemesterId('2026 秋', DateTime(2026, 9, 7, 0, 0)),
        deriveSemesterId('2026 秋', DateTime(2026, 9, 7, 23, 59)),
      );
    });

    test('名字或开学日期不同就换值', () {
      final String base = deriveSemesterId('2026 秋', kAutumnStart);
      expect(deriveSemesterId('2027 春', kAutumnStart), isNot(base));
      expect(deriveSemesterId('2026 秋', kSpringStart), isNot(base));
    });

    test('带 sem- 前缀，长度固定', () {
      final String id = deriveSemesterId('2026 秋', kAutumnStart);
      expect(id, startsWith('sem-'));
      expect(id.length, 12);
    });

    test('名字首尾空白不影响结果', () {
      expect(
        deriveSemesterId(' 2026 秋 ', kAutumnStart),
        deriveSemesterId('2026 秋', kAutumnStart),
      );
    });
  });

  group('SemesterConfig.id', () {
    test('默认空串，ensureId 后补齐且幂等', () {
      final SemesterConfig config = _autumn();
      expect(config.id, isEmpty);
      expect(config.hasId, isFalse);

      final SemesterConfig withId = config.ensureId();
      expect(withId.hasId, isTrue);
      expect(withId.id, deriveSemesterId(config.name, config.startDate));
      expect(withId.ensureId().id, withId.id);
    });

    test('旧数据（JSON 里没有 id）能读出来，id 为空', () {
      final SemesterConfig? config = SemesterConfig.tryDecode(
        '{"name":"2026 秋","startDate":"2026-09-07T00:00:00.000",'
        '"totalWeeks":20}',
      );
      expect(config, isNotNull);
      expect(config!.id, isEmpty);
      expect(config.ensureId().hasId, isTrue);
    });

    test('JSON 往返保留 id', () {
      final SemesterConfig config = _autumn().ensureId();
      final SemesterConfig back =
          SemesterConfig.fromJson(jsonDecode(jsonEncode(config.toJson()))
              as Map<String, dynamic>);
      expect(back.id, config.id);
      expect(back, config);
    });
  });

  group('Course.semesterId', () {
    test('默认空串；JSON 往返保留', () {
      final Course course = _course('c1');
      expect(course.semesterId, isEmpty);
      expect(course.hasSemester, isFalse);

      final Course back =
          Course.fromJson(jsonDecode(jsonEncode(course.toJson()))
              as Map<String, dynamic>);
      expect(back.semesterId, isEmpty);
    });

    test('旧数据（JSON 里没有 semesterId）读出来是空串，不报错', () {
      final Course back = Course.fromJson(<String, dynamic>{
        'id': 'c1',
        'name': '高等数学',
        'sourcePluginId': 'ncst',
      });
      expect(back.semesterId, isEmpty);
    });

    test('空串只归当前学期，不归其它学期', () {
      final Course legacy = _course('c1');
      expect(
        legacy.belongsToSemester('sem-a', currentSemesterId: 'sem-a'),
        isTrue,
      );
      expect(
        legacy.belongsToSemester('sem-b', currentSemesterId: 'sem-a'),
        isFalse,
      );
    });

    test('已打归属的课程严格按 id 匹配（即使它就是当前学期）', () {
      final Course course = _course('c1', semesterId: 'sem-a');
      expect(
        course.belongsToSemester('sem-a', currentSemesterId: 'sem-b'),
        isTrue,
      );
      expect(
        course.belongsToSemester('sem-b', currentSemesterId: 'sem-b'),
        isFalse,
      );
    });
  });

  group('当前学期读写', () {
    test('没设置时返回 null', () {
      expect(SemesterArchiveService.loadCurrent(), isNull);
    });

    test('saveCurrent 落盘后能读回，且带 id', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final SemesterConfig? current = SemesterArchiveService.loadCurrent();
      expect(current, isNotNull);
      expect(current!.name, '2026-2027 学年第一学期');
      expect(current.id, deriveSemesterId(current.name, current.startDate));
    });

    test('旧数据（没 id）读出来也会补上 id，但不写回存储', () async {
      await StorageService.settingsBox.put(
        kSemesterConfigKey,
        '{"name":"2026 秋","startDate":"2026-09-07T00:00:00.000",'
        '"totalWeeks":20}',
      );
      expect(SemesterArchiveService.loadCurrent()!.hasId, isTrue);
      // 存储里仍然是旧格式：id 是派生值，不落盘
      expect(
        StorageService.settingsBox.get(kSemesterConfigKey),
        isNot(contains('"id"')),
      );
    });
  });

  group('归档与切换', () {
    test('没有当前学期时归档失败（不产生空条目）', () async {
      final SemesterSwitchResult result =
          await SemesterArchiveService.archiveCurrent();
      expect(result.ok, isFalse);
      expect(SemesterArchiveService.loadArchived(), isEmpty);
    });

    test('switchTo 会把旧学期归档、新学期的成为当前', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final SemesterSwitchResult result =
          await SemesterArchiveService.switchTo(_spring());

      expect(result.ok, isTrue);
      expect(result.current!.name, '2026-2027 学年第二学期');
      expect(result.archivedCount, 1);

      final SemesterConfig? current = SemesterArchiveService.loadCurrent();
      expect(current!.name, '2026-2027 学年第二学期');

      final List<SemesterArchiveEntry> archived =
          SemesterArchiveService.loadArchived();
      expect(archived, hasLength(1));
      expect(archived.single.config.name, '2026-2027 学年第一学期');
    });

    test('首次设置学期（之前没有）不会产生归档条目', () async {
      final SemesterSwitchResult result =
          await SemesterArchiveService.switchTo(_autumn());
      expect(result.ok, isTrue);
      expect(result.archivedCount, 0);
      expect(result.message, contains('已设为'));
    });

    test('切到同一个学期：不重复归档，消息说明已在该学期', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final SemesterSwitchResult first =
          await SemesterArchiveService.switchTo(_spring());
      expect(first.archivedCount, 1);

      final SemesterSwitchResult again =
          await SemesterArchiveService.switchTo(_spring());
      expect(again.ok, isTrue);
      expect(again.message, contains('已经是'));
      expect(SemesterArchiveService.loadArchived(), hasLength(1));
    });

    test('archiveCurrent 只归档、不设新学期', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final SemesterSwitchResult result =
          await SemesterArchiveService.archiveCurrent();
      expect(result.ok, isTrue);
      expect(SemesterArchiveService.loadCurrent(), isNull);
      expect(SemesterArchiveService.loadArchived(), hasLength(1));
    });

    test('restoreArchived 把学期从归档移回当前', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await SemesterArchiveService.switchTo(_spring());
      final String autumnId = deriveSemesterId('2026-2027 学年第一学期', kAutumnStart);

      final SemesterSwitchResult result =
          await SemesterArchiveService.restoreArchived(autumnId);
      expect(result.ok, isTrue);
      expect(SemesterArchiveService.loadCurrent()!.id, autumnId);
      // 恢复后归档里只剩刚被换下去的那个
      final List<SemesterArchiveEntry> archived =
          SemesterArchiveService.loadArchived();
      expect(archived, hasLength(1));
      expect(archived.single.config.id, isNot(autumnId));
    });

    test('restoreArchived 找不到时明确失败', () async {
      final SemesterSwitchResult result =
          await SemesterArchiveService.restoreArchived('sem-不存在');
      expect(result.ok, isFalse);
      expect(result.message, contains('没有这个学期'));
    });

    test('removeArchived 只删归档，不动当前学期', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await SemesterArchiveService.switchTo(_spring());
      final String autumnId = deriveSemesterId('2026-2027 学年第一学期', kAutumnStart);

      expect(await SemesterArchiveService.removeArchived(autumnId), isTrue);
      expect(SemesterArchiveService.loadArchived(), isEmpty);
      expect(SemesterArchiveService.loadCurrent(), isNotNull);
    });

    test('归档数量超过上限时丢开学日期最早的', () async {
      // 先塞满 kMaxArchivedSemesters 个学期（逐年往后排）
      for (int i = 0; i < kMaxArchivedSemesters; i++) {
        await SemesterArchiveService.saveCurrent(
          SemesterConfig(
            name: '第 $i 学期',
            startDate: DateTime(2020, 3, 2).add(Duration(days: 200 * i)),
            totalWeeks: 20,
          ),
        );
        await SemesterArchiveService.archiveCurrent();
      }
      expect(
        SemesterArchiveService.loadArchived(),
        hasLength(kMaxArchivedSemesters),
      );

      // 再归档一个更新的学期 → 总数仍为上限，最早那个被挤掉
      final String oldestName =
          SemesterArchiveService.loadArchived().last.config.name;
      await SemesterArchiveService.saveCurrent(_spring());
      await SemesterArchiveService.archiveCurrent();

      final List<SemesterArchiveEntry> archived =
          SemesterArchiveService.loadArchived();
      expect(archived, hasLength(kMaxArchivedSemesters));
      expect(
        archived.map((SemesterArchiveEntry e) => e.config.name),
        isNot(contains(oldestName)),
      );
    });
  });

  group('课程归属', () {
    test('coursesOf：空串归当前学期，已打归属的严格匹配', () {
      final List<Course> all = <Course>[
        _course('legacy'),
        _course('autumn', semesterId: 'sem-a'),
        _course('spring', semesterId: 'sem-b'),
      ];
      expect(
        SemesterArchiveService.coursesOf(
          all,
          semesterId: 'sem-a',
          currentSemesterId: 'sem-a',
        ).map((Course c) => c.id),
        <String>['legacy', 'autumn'],
      );
      expect(
        SemesterArchiveService.coursesOf(
          all,
          semesterId: 'sem-b',
          currentSemesterId: 'sem-a',
        ).map((Course c) => c.id),
        <String>['spring'],
      );
    });

    test('切换学期时旧课程被打上旧学期 id（否则会被新学期认领）', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final String autumnId = deriveSemesterId('2026-2027 学年第一学期', kAutumnStart);
      await seedCourseJson('c1'); // 旧数据：没有 semesterId
      await seedCourseJson('c2');

      final SemesterSwitchResult result =
          await SemesterArchiveService.switchTo(_spring());
      expect(result.stampedCourses, 2);
      expect(readCourseJson('c1')['semesterId'], autumnId);
      expect(readCourseJson('c2')['semesterId'], autumnId);
    });

    test('已经有归属的课程不会被覆盖', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await seedCourseJson('c1', semesterId: 'sem-other');

      final SemesterSwitchResult result =
          await SemesterArchiveService.switchTo(_spring());
      expect(result.stampedCourses, 0);
      expect(readCourseJson('c1')['semesterId'], 'sem-other');
    });

    test('打归属时保留 Box 里的未知键（向前兼容）', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await seedCourseJson('c1', extra: <String, dynamic>{'futureField': '保留我'});

      await SemesterArchiveService.switchTo(_spring());
      final Map<String, dynamic> json = readCourseJson('c1');
      expect(json['futureField'], '保留我');
      expect(json['teacher'], '张老师');
    });

    test('打归属不会把 userOverride 写进课程 JSON（覆盖层以 overrides Box 为准）',
        () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await seedCourseJson('c1');

      await SemesterArchiveService.switchTo(_spring());
      expect(readCourseJson('c1').containsKey('userOverride'), isFalse);
    });

    test('archiveCurrent 同样会补归属（当前学期被清空前）', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      final String autumnId = deriveSemesterId('2026-2027 学年第一学期', kAutumnStart);
      await seedCourseJson('c1');

      final SemesterSwitchResult result =
          await SemesterArchiveService.archiveCurrent();
      expect(result.stampedCourses, 1);
      expect(readCourseJson('c1')['semesterId'], autumnId);
    });

    test('assignCoursesToSemester 只改指定课程', () async {
      await seedCourseJson('c1');
      await seedCourseJson('c2');

      final int changed = await SemesterArchiveService.assignCoursesToSemester(
        <String>['c2'],
        'sem-x',
      );
      expect(changed, 1);
      expect(readCourseJson('c1')['semesterId'], isNull);
      expect(readCourseJson('c2')['semesterId'], 'sem-x');
    });

    test('坏 JSON 的课程被跳过，不中断整批处理', () async {
      await StorageService.coursesBox.put('broken', '不是 JSON');
      await seedCourseJson('c1');

      final int changed =
          await SemesterArchiveService.stampUnassignedCourses('sem-x');
      expect(changed, 1);
      expect(StorageService.coursesBox.get('broken'), '不是 JSON');
    });

    test('semesterId 为空串时不做任何事', () async {
      await seedCourseJson('c1');
      expect(
        await SemesterArchiveService.stampUnassignedCourses(''),
        0,
      );
      expect(readCourseJson('c1')['semesterId'], isNull);
    });
  });

  group('listSemesters', () {
    test('当前 + 归档，按开学日期倒序，同 id 去重', () async {
      await SemesterArchiveService.saveCurrent(_autumn());
      await SemesterArchiveService.switchTo(_spring());

      final List<SemesterConfig> all =
          SemesterArchiveService.listSemesters();
      expect(all, hasLength(2));
      // 2027 春开学更晚，排前面
      expect(all.first.name, '2026-2027 学年第二学期');
      expect(all.last.name, '2026-2027 学年第一学期');
    });

    test('没有任何学期时返回空列表', () {
      expect(SemesterArchiveService.listSemesters(), isEmpty);
    });

    test('归档数据损坏时按空归档处理（不崩）', () async {
      await StorageService.settingsBox
          .put(kSemesterArchiveKey, '这不是 JSON');
      expect(SemesterArchiveService.loadArchived(), isEmpty);
    });

    test('归档里的坏条目逐条跳过', () async {
      final SemesterConfig good = _autumn().ensureId();
      await StorageService.settingsBox.put(
        kSemesterArchiveKey,
        jsonEncode(<Object?>[
          <String, dynamic>{
            'config': good.toJson(),
            'archivedAt': '2026-10-01T00:00:00.000',
          },
          <String, dynamic>{'config': <String, dynamic>{'name': '缺开学日期'}},
          '不是对象',
        ]),
      );
      final List<SemesterArchiveEntry> archived =
          SemesterArchiveService.loadArchived();
      expect(archived, hasLength(1));
      expect(archived.single.config.id, good.id);
    });
  });
}

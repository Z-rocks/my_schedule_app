// 课程搜索 / 筛选的纯函数测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/course.dart';
import 'package:my_schedule_app/models/time_place.dart';
import 'package:my_schedule_app/services/course_filter.dart';

Course _course({
  String id = 'c1',
  String name = '',
  String teacher = '',
  String category = '',
  List<TimePlace> places = const <TimePlace>[],
}) {
  return Course(
    id: id,
    name: name,
    teacher: teacher,
    unit: 3,
    category: category,
    timePlaces: places,
    sourcePluginId: 'test',
  );
}

TimePlace _place({String room = '', int day = 1, int start = 1}) {
  return TimePlace(
    day: day,
    startSession: start,
    length: 2,
    room: room,
    weeks: const <int>[1, 2],
    rawWeeksText: '1-2周',
  );
}

void main() {
  final List<Course> sample = <Course>[
    _course(
      id: 'a',
      name: '高等数学',
      teacher: '王建国',
      category: '公共基础课',
      places: <TimePlace>[_place(room: 'HE-405')],
    ),
    _course(
      id: 'b',
      name: '软件工程C',
      teacher: '石琳',
      category: '专业必修课',
      places: <TimePlace>[_place(room: 'HA-416')],
    ),
    _course(
      id: 'c',
      name: 'College English',
      teacher: '李梅',
      category: '公共基础课',
      places: <TimePlace>[_place(room: 'FL-201')],
    ),
  ];

  group('splitQueryTerms', () {
    test('按半角空格拆分并小写', () {
      expect(splitQueryTerms('Wang  Gao'), <String>['wang', 'gao']);
    });

    test('全角空格也当分隔符', () {
      // 中文输入法很容易打出 U+3000，只按 ' ' 拆会得到整串。
      expect(splitQueryTerms('王\u3000高数'), <String>['王', '高数']);
    });

    test('空串 / 纯空白得到空列表', () {
      expect(splitQueryTerms(''), isEmpty);
      expect(splitQueryTerms('   '), isEmpty);
      expect(splitQueryTerms('\u3000 '), isEmpty);
    });
  });

  group('courseMatchesQuery', () {
    test('空关键词恒为 true', () {
      for (final Course course in sample) {
        expect(courseMatchesQuery(course, ''), isTrue);
      }
    });

    test('按课程名匹配', () {
      expect(courseMatchesQuery(sample[0], '高等'), isTrue);
      expect(courseMatchesQuery(sample[1], '软件'), isTrue);
    });

    test('按教师匹配', () {
      expect(courseMatchesQuery(sample[1], '石琳'), isTrue);
      expect(courseMatchesQuery(sample[0], '石琳'), isFalse);
    });

    test('按教室匹配', () {
      expect(courseMatchesQuery(sample[0], 'HE-405'), isTrue);
      expect(courseMatchesQuery(sample[0], 'he-405'), isTrue);
    });

    test('按类别匹配', () {
      expect(courseMatchesQuery(sample[2], '公共基础'), isTrue);
    });

    test('英文忽略大小写', () {
      expect(courseMatchesQuery(sample[2], 'college'), isTrue);
      expect(courseMatchesQuery(sample[2], 'ENGLISH'), isTrue);
    });

    test('多关键词是 AND 关系', () {
      // "王" 命中教师、"高等" 命中课程名 → 同一门课两个词都命中
      expect(courseMatchesQuery(sample[0], '王 高等'), isTrue);
      // "王" 命中 a、"软件" 只在 b → 没有任何一门同时命中
      expect(courseMatchesQuery(sample[0], '王 软件'), isFalse);
    });

    test('全角空格分隔的多关键词同样生效', () {
      expect(courseMatchesQuery(sample[0], '王\u3000高等'), isTrue);
    });

    test('非连续子串不算命中（"高数" 不在 "高等数学" 里）', () {
      expect(courseMatchesQuery(sample[0], '高数'), isFalse);
      expect(courseMatchesQuery(sample[0], '数学'), isTrue);
    });

    test('完全不匹配返回 false', () {
      expect(courseMatchesQuery(sample[0], '量子力学'), isFalse);
    });

    test('教室为空时不产生空串命中', () {
      final Course noRoom =
          _course(name: '自习', places: <TimePlace>[_place(room: '')]);
      expect(courseMatchesQuery(noRoom, 'HE'), isFalse);
    });
  });

  group('filterCourses', () {
    test('无关键词且无类别时原样返回（同一实例，避免无谓复制）', () {
      expect(identical(filterCourses(sample, ''), sample), isTrue);
    });

    test('关键词过滤保持原顺序', () {
      final List<Course> result = filterCourses(sample, '公共基础');
      expect(result.map((Course c) => c.id), <String>['a', 'c']);
    });

    test('按类别筛选', () {
      final List<Course> result =
          filterCourses(sample, '', category: '专业必修课');
      expect(result.single.id, 'b');
    });

    test('类别 + 关键词同时生效', () {
      expect(filterCourses(sample, '王', category: '专业必修课'), isEmpty);
      expect(
        filterCourses(sample, '王', category: '公共基础课').single.id,
        'a',
      );
    });

    test('无匹配返回空列表', () {
      expect(filterCourses(sample, '不存在的课'), isEmpty);
    });
  });

  group('collectCategories', () {
    test('去重并排序', () {
      // Dart 的 String.compareTo 按 UTF-16 码点比："专"(U+4E13) < "公"(U+516C)。
      // 不是拼音序，但**稳定**——重新同步后 chips 顺序不会跳来跳去，这才是目的。
      expect(
        collectCategories(sample),
        <String>['专业必修课', '公共基础课'],
      );
    });

    test('剔除空类别', () {
      final List<Course> list = <Course>[
        _course(id: 'x', category: ''),
        _course(id: 'y', category: '  '),
        _course(id: 'z', category: '选修'),
      ];
      expect(collectCategories(list), <String>['选修']);
    });

    test('全空时返回空列表（UI 据此不显示筛选条）', () {
      expect(collectCategories(<Course>[]), isEmpty);
    });
  });
}

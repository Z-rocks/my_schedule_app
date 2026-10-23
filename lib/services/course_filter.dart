// 课程搜索与筛选：纯函数，不碰 UI 也不碰存储。
//
// 拆成独立文件的原因：搜索的匹配规则（匹配哪些字段、多关键词怎么组合、
// 大小写和空格怎么处理）是最容易"看起来对但用起来不对"的地方，
// 放进 Widget 里就只能靠点界面验证。这里做成纯函数，测试可以直接断言。
import '../models/course.dart';
import '../models/time_place.dart';

/// 课程名 / 教师 / 教室 / 类别——搜索时匹配的四个字段。
///
/// 刻意**不含**学分和周次：用户搜"3.5"或"1-16"的诉求几乎不存在，
/// 而把数字纳入匹配会让"搜 3"命中一堆无关课程。
List<String> _searchableFields(Course course) {
  final List<String> fields = <String>[
    course.displayName,
    course.displayTeacher,
    course.category,
  ];
  for (final TimePlace place in course.displayTimePlaces) {
    if (place.room.isNotEmpty) fields.add(place.room);
  }
  return fields;
}

/// 一门课是否命中搜索词。
///
/// 规则：
/// - 关键词按**空格拆分**，每个词都要命中（AND）——"王 高数"能同时收窄到
///   "王老师的高数"，比整串子串匹配好用得多；
/// - 每个词只要命中**任意一个字段**就算该词命中；
/// - 忽略大小写，全角空格也当分隔符（中文输入法很容易打出全角空格）。
bool courseMatchesQuery(Course course, String query) {
  final List<String> terms = splitQueryTerms(query);
  if (terms.isEmpty) return true;
  final List<String> fields =
      _searchableFields(course).map((String f) => f.toLowerCase()).toList();
  for (final String term in terms) {
    bool hit = false;
    for (final String field in fields) {
      if (field.contains(term)) {
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  return true;
}

/// 把搜索框内容拆成关键词（小写、去空）。
///
/// 全角空格（U+3000）必须一起处理：中文输入法下用户经常打出全角空格，
/// 只按 `' '` 拆会得到"王　高数"这种整串，永远搜不到。
List<String> splitQueryTerms(String query) {
  return query
      .toLowerCase()
      .split(RegExp(r'[\s\u3000]+'))
      .where((String s) => s.isNotEmpty)
      .toList();
}

/// 过滤课程列表（保持原有顺序）。
List<Course> filterCourses(
  List<Course> courses,
  String query, {
  String category = '',
}) {
  final bool byCategory = category.isNotEmpty;
  if (splitQueryTerms(query).isEmpty && !byCategory) return courses;
  return courses.where((Course course) {
    if (byCategory && course.category != category) return false;
    return courseMatchesQuery(course, query);
  }).toList();
}

/// 收集课程里出现过的类别（去重、按名称排序，空类别剔除）。
///
/// 用于筛选 chips。排序而不是按出现顺序：同一批课程重新同步后顺序可能变，
/// 按名称排能让 chips 的位置保持稳定。
List<String> collectCategories(List<Course> courses) {
  final Set<String> seen = <String>{};
  for (final Course course in courses) {
    final String category = course.category.trim();
    if (category.isNotEmpty) seen.add(category);
  }
  final List<String> result = seen.toList()..sort();
  return result;
}

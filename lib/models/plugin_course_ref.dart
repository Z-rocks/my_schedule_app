// Phase 8：插件自报的"课程引用"——用于"勾选课程 → 抓取作业/考试"的中间载体。
//
// ## 为什么需要这个模型（CONTEXT 3.1 的边界）
//
// 作业与考试的抓取入口（`fetchHomeworks` / `fetchExams`）需要插件自己那套
// **课程标识**（学习通是 `courseId` + `classId` + `cpi`，别的学校可能是别的字段）。
// 内核**不允许知道**这些字段名，因此本模型把它们当作**不透明数据**：
//
//   - [raw] 原样保存插件返回的那个对象，回传时**一个键都不改**；
//   - 内核只读三个**约定的展示字段**（`id` / `name` / `teacher` / `className`），
//     它们缺失时退化为空串，不影响功能（只是列表上少一行副标题）。
//
// 换句话说：内核负责"把它显示出来、让用户勾选"，插件负责"看得懂它"。
// 契约（写在插件侧注释里）：
//   `fetchCourseList` → `{ courses: [{ id, name, teacher?, className?, ...任意字段 }] }`
//   `fetchHomeworks` / `fetchExams` → `args.courses` 收到被勾选的那些对象**原样**
import 'dart:collection';

/// 一条由插件产出的课程引用（不透明对象 + 少量约定展示字段）。
///
/// 不实现 `==` / `hashCode`：它是**容器**而非值对象，
/// 身份由 [id] 决定，比较请显式用 [id]（列表去重也按 [id] 做）。
class PluginCourseRef {
  /// 构造。直接持有 [raw]，**不做拷贝**——调用方不应再修改传入的 Map。
  const PluginCourseRef(this.raw);

  /// 插件返回的原始对象，回传时原样交给插件。
  ///
  /// 内核**只**把它当字符串键值容器用，不解释任何业务字段。
  final Map<String, dynamic> raw;

  /// 从 JSON 构造；非 Map 时返回 `null`（调用方跳过该条）。
  static PluginCourseRef? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> map = <String, dynamic>{};
    value.forEach((dynamic key, dynamic item) {
      if (key != null) map['$key'] = item;
    });
    return PluginCourseRef(map);
  }

  /// 取一个约定展示字段；缺失或类型不符时返回空串。
  String _text(String key) {
    final Object? value = raw[key];
    if (value == null) return '';
    if (value is String) return value;
    return '$value';
  }

  /// 勾选状态用的稳定标识（插件约定字段 `id`）。
  ///
  /// 插件没给 `id` 时退化为 [name] + `raw` 的哈希——仍然稳定（同一次会话内
  /// 同一个对象的 `hashCode` 不变），只是跨会话不保证一致，仅用于本次勾选。
  String get id {
    final String explicit = _text('id');
    if (explicit.isNotEmpty) return explicit;
    return 'anon_${name}_${raw.hashCode}';
  }

  /// 课程名（插件约定字段 `name`），列表主标题。
  String get name => _text('name');

  /// 教师名（约定字段 `teacher`），可能为空。
  String get teacher => _text('teacher');

  /// 班级名（约定字段 `className`），可能为空。
  String get className => _text('className');

  /// 列表副标题：`教师 · 班级`，两者都空时返回空串。
  String get subtitle {
    final List<String> parts = <String>[
      if (teacher.isNotEmpty) teacher,
      if (className.isNotEmpty) className,
    ];
    return parts.join(' · ');
  }

  /// 列表主标题：插件没给 `name` 时用 id 兜底，避免显示一行空白。
  String get displayName => name.isNotEmpty ? name : id;

  /// 原样返回插件给的 JSON 对象（**不做任何字段改名 / 增删**）。
  Map<String, dynamic> toJson() => raw;

  @override
  String toString() => 'PluginCourseRef($id, $displayName)';
}

/// 把插件返回的 `courses` 数组解析成 [PluginCourseRef] 列表。
///
/// 非列表返回空列表；单个元素不是对象时跳过。**不抛异常**。
List<PluginCourseRef> parseCourseRefs(Object? raw) {
  if (raw is! List) return const <PluginCourseRef>[];
  final List<PluginCourseRef> result = <PluginCourseRef>[];
  for (final Object? item in raw) {
    final PluginCourseRef? ref = PluginCourseRef.tryFromJson(item);
    if (ref != null) result.add(ref);
  }
  return List<PluginCourseRef>.unmodifiable(result);
}

/// 按 [PluginCourseRef.id] 去重（后出现的覆盖先出现的），保持首次出现顺序。
///
/// 插件理论上不该返回重复 id，但去重能让"勾选数量"与"实际抓取数量"一致。
List<PluginCourseRef> dedupeCourseRefs(Iterable<PluginCourseRef> refs) {
  final LinkedHashMap<String, PluginCourseRef> byId =
      LinkedHashMap<String, PluginCourseRef>();
  for (final PluginCourseRef ref in refs) {
    byId[ref.id] = ref;
  }
  return List<PluginCourseRef>.unmodifiable(byId.values);
}

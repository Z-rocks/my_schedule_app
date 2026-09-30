// 课程编辑页：新增 / 编辑一门课程的基本信息与多个上课时间段
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/time_place.dart';
import '../../models/user_override.dart';
import '../../providers/course_provider.dart';
import '../../providers/semester_provider.dart';
import '../../services/timetable_logic.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_extension.dart';
import '../../widgets/timetable_grid.dart'
    show kWeekdayLabels;

/// 与 `TimetableLogic` 对齐的节次 / 星期上限（编辑模式反填时用来收敛越界值）。
const int _kMaxSessions = 12;
const int _kDaysPerWeek = 7;

/// 课程名最大长度。
const int kMaxCourseNameLength = 30;

/// 学分范围与步进。
const double kMinUnit = 0;
const double kMaxUnit = 10;
const double kUnitStep = 0.5;

/// 持续节数范围。
const int kMinLength = 1;
const int kMaxLength = 4;

/// 把"起始周 / 结束周 / 单双周"转换成 `TimePlace.weeks`。
///
/// 按提示词约定，这里**直接过滤**单双周：
/// - [WeekType.all]  → `[start..end]`
/// - [WeekType.odd]  → `[start..end]` 中的奇数周
/// - [WeekType.even] → `[start..end]` 中的偶数周
///
/// 区间非法（`end < start`）返回空列表。
///
/// 注意：这与 Phase 2.2a 的设计不同——`TimetableLogic.parseWeeks` 解析插件文本时
/// 保留**基础周次**（不过滤），由 `hasClassInWeek` 叠加单双周判断。
/// 这里按提示词要求预先过滤，两种数据表示在界面上等价（`hasClassInWeek`
/// 对已过滤的 weeks 再判一次单双周不会改变结果），但 `weeks` 的值形态不一致，
/// 详见 PROGRESS 阻塞表。
List<int> weeksFromRange(int startWeek, int endWeek, WeekType weekType) {
  if (endWeek < startWeek) return const <int>[];
  final List<int> result = <int>[];
  for (int week = startWeek; week <= endWeek; week++) {
    switch (weekType) {
      case WeekType.all:
        result.add(week);
      case WeekType.odd:
        if (week.isOdd) result.add(week);
      case WeekType.even:
        if (week.isEven) result.add(week);
    }
  }
  return result;
}

/// 把周次区间转成展示用原始文本：`"1-16周"` / `"1-16周(单)"` / `"2-16周(双)"`；
/// 起止相同时写成 `"9周"`。
String rawWeeksTextFromRange(int startWeek, int endWeek, WeekType weekType) {
  final String base =
      startWeek == endWeek ? '$startWeek周' : '$startWeek-$endWeek周';
  switch (weekType) {
    case WeekType.all:
      return base;
    case WeekType.odd:
      return '$base(单)';
    case WeekType.even:
      return '$base(双)';
  }
}

/// 课程编辑页（新增 / 编辑）。
///
/// 入口：
/// - **新增**：课表页顶部 `+`、课表页空态的"添加课程"按钮（不传 [course]）；
/// - **编辑**：课程详情弹层的「编辑」、课表卡片长按（传 [course]）。
///
/// **必须先配置学期**（周次范围依赖 `SemesterConfig.totalWeeks`），
/// 入口处会拦截并提示，本页也做一次兜底。
///
/// ## 编辑两种课程时的落点是**不同**的（CONTEXT 3.3）
///
/// | 课程来源 | 保存到哪 | 为什么 |
/// |----------|----------|--------|
/// | 自建（`sourcePluginId == 'user'`） | `courses` Box 的**原始字段** | 这条数据本来就是用户的，没有"教务原始值"要保护 |
/// | 插件同步来的 | `overrides` Box 的**覆盖层** | 原始字段是教务权威数据，重同步会覆盖它；用户改动必须放在覆盖层里才不会被冲掉 |
///
/// ⚠️ **学分与类别在编辑插件课程时是只读的**：`UserOverride` 没有
/// `customUnit` / `customCategory` 字段，硬写进 `Course` 会被下次同步冲掉
/// （那正是 Phase 4.3 修掉的那类 bug）。所以这两个字段在插件课程里显示教务值
/// 并置灰，并给出说明——**不假装能改**。
class CourseEditPage extends StatefulWidget {
  const CourseEditPage({super.key, this.course});

  /// 要编辑的课程；`null` 表示新增。
  final Course? course;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  /// 学分。
  double _unit = 2;

  /// 选中的自定义颜色；`null` 表示"自动"（由系统按课程 id 哈希分配）。
  int? _selectedColor;

  /// 时间段草稿列表（可变，保存时转成 [TimePlace]）。
  final List<_TimePlaceDraft> _drafts = <_TimePlaceDraft>[];

  /// 进入编辑时，原始课程的安排（用于判断用户到底改没改时间段）。
  List<TimePlace> _originalPlaces = const <TimePlace>[];

  /// 是否处于编辑模式。
  bool get _isEditing => widget.course != null;

  /// 编辑的是否是**用户自建**课程（决定保存到原始字段还是覆盖层）。
  bool get _isUserCourse => widget.course?.isUserCreated ?? false;

  /// 插件课程的学分 / 类别是否可改。
  ///
  /// 自建课程可以改（写原始字段）；插件课程不行（见类文档说明）。
  bool get _canEditSchoolFields => !_isEditing || _isUserCourse;

  @override
  void initState() {
    super.initState();
    final Course? course = widget.course;

    if (course == null) {
      // 新增：默认选中第一个预设颜色（"自动"是额外选项，排在最后）
      final List<Color> palette = AppTheme.defaultTheme().courseCardColors;
      _selectedColor = palette.isEmpty ? null : palette.first.toARGB32();
      // 默认时间段覆盖整个学期
      _drafts.add(_TimePlaceDraft(endWeek: _totalWeeks));
      return;
    }

    // 编辑：把已有值填进表单。展示值一律走 displayXxx（已叠加覆盖层）。
    _nameController.text = course.displayName;
    _teacherController.text = course.displayTeacher;
    _categoryController.text = course.category;
    _noteController.text = course.userOverride?.note ?? '';
    _unit = course.unit;
    // 覆盖层里没有颜色 → 保持"自动"，不要凭空选一个（那会改掉用户的自动配色）
    _selectedColor = course.displayColor;
    _originalPlaces = course.displayTimePlaces;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 时间段草稿依赖 `_totalWeeks`，它要读 SemesterProvider——
    // `initState` 里读会拿不到 InheritedWidget，所以放在这里。
    // 用一个标记保证只初始化一次（本回调会因依赖变化重复触发）。
    if (_draftsInitialized) return;
    _draftsInitialized = true;
    final List<TimePlace> places =
        _isEditing ? _originalPlaces : const <TimePlace>[];
    if (places.isEmpty) {
      _drafts.add(_TimePlaceDraft(endWeek: _totalWeeks));
    } else {
      for (final TimePlace tp in places) {
        _drafts.add(_TimePlaceDraft.fromTimePlace(tp, totalWeeks: _totalWeeks));
      }
    }
  }

  /// 时间段草稿是否已初始化（见 [didChangeDependencies]）。
  bool _draftsInitialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    for (final _TimePlaceDraft draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  /// 学期总周数（周次范围上限）；没有学期时为 1。
  int get _totalWeeks {
    final int weeks = context.read<SemesterProvider>().config?.totalWeeks ?? 1;
    return weeks < 1 ? 1 : weeks;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 删除 / 隐藏当前课程。
  ///
  /// **语义按来源分岔**（CONTEXT 3.3：教务课程只能隐藏或永久忽略，不能真删）：
  ///
  /// | 来源 | 动作 | 为什么 |
  /// |------|------|--------|
  /// | 自建 | **真删**（`deleteCourse`，连覆盖层一起清） | 这条数据只属于用户，没有"教务原始值"要留 |
  /// | 插件同步来的 | **隐藏**（写 `userOverride.hidden = true`） | 原始数据是教务权威数据，删了下次同步还会回来；隐藏可撤销 |
  ///
  /// 两者的确认文案也不同——"删除"和"隐藏"对用户是两件事，
  /// 不能共用一句"确定吗"。
  Future<void> _confirmDelete() async {
    final Course? course = widget.course;
    if (course == null) return;

    final bool isUserCourse = course.isUserCreated;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(isUserCourse ? '删除课程' : '从课表隐藏'),
        content: Text(
          isUserCourse
              ? '确定删除「${course.displayName}」吗？这会同时删除它的颜色与备注。'
              : '确定把「${course.displayName}」从课表隐藏吗？\n\n'
                  '课程原始数据会保留，之后可以在'
                  '「设置 → 课表设置 → 已隐藏的课程」里恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isUserCourse ? '删除' : '隐藏'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final CourseProvider courses = context.read<CourseProvider>();

    if (isUserCourse) {
      await courses.deleteCourse(course.id);
      if (!mounted) return;
      navigator.pop(false);
      messenger.showSnackBar(const SnackBar(content: Text('课程已删除')));
      return;
    }

    // 插件课程：写 hidden 覆盖层。保留已有覆盖层的其他字段（颜色 / 备注 / 改名）。
    final UserOverride base = course.userOverride ??
        UserOverride(updatedAt: DateTime.now());
    await courses.saveCourse(
      course.copyWith(
        userOverride: base.copyWith(hidden: true, updatedAt: DateTime.now()),
      ),
    );
    if (!mounted) return;
    navigator.pop(false);
    messenger.showSnackBar(const SnackBar(content: Text('已从课表隐藏')));
  }

  void _addDraft() {
    setState(() => _drafts.add(_TimePlaceDraft(endWeek: _totalWeeks)));
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) {
      _showSnack('至少保留一个时间段');
      return;
    }
    setState(() {
      _drafts.removeAt(index).dispose();
    });
  }

  /// 把草稿转成 [TimePlace]。
  TimePlace _toTimePlace(_TimePlaceDraft draft) => TimePlace(
        day: draft.day,
        startSession: draft.startSession,
        length: draft.length,
        room: draft.roomController.text.trim(),
        weeks: weeksFromRange(draft.startWeek, draft.endWeek, draft.weekType),
        rawWeeksText: rawWeeksTextFromRange(
            draft.startWeek, draft.endWeek, draft.weekType),
        weekType: draft.weekType,
      );

  Future<void> _save() async {
    // 兜底：理论上入口已拦截，这里防止直接构造本页
    final SemesterProvider semester = context.read<SemesterProvider>();
    if (!semester.hasConfig) {
      _showSnack('请先配置学期');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 周次区间非法 / 与单双周组合后为空 → 该时间段永远不会显示
    for (int i = 0; i < _drafts.length; i++) {
      final _TimePlaceDraft draft = _drafts[i];
      if (draft.endWeek < draft.startWeek) {
        _showSnack('第 ${i + 1} 个时间段的结束周不能早于起始周');
        return;
      }
      if (weeksFromRange(draft.startWeek, draft.endWeek, draft.weekType)
          .isEmpty) {
        _showSnack('第 ${i + 1} 个时间段的周次与单双周设置组合后为空，请调整');
        return;
      }
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final CourseProvider courses = context.read<CourseProvider>();

    final String name = _nameController.text.trim();
    final String teacher = _teacherController.text.trim();
    final String category = _categoryController.text.trim();
    final String note = _noteController.text.trim();
    final List<TimePlace> places =
        _drafts.map(_toTimePlace).toList(growable: false);

    final Course? original = widget.course;

    if (original != null) {
      // ── 编辑 ──
      final UserOverride? override = _buildOverride(
        base: original.userOverride,
        name: name,
        teacher: teacher,
        note: note,
        places: places,
      );

      final Course updated = original.isUserCreated
          // 自建课程：本来就是用户的数据，直接改原始字段。
          ? original.copyWith(
              name: name,
              teacher: teacher,
              unit: _unit,
              category: category,
              timePlaces: places,
              userOverride: override,
            )
          // 插件课程：原始字段保持教务值，改动全部进覆盖层
          // （否则下次同步会把用户的修改冲掉，见类文档）。
          : original.copyWith(userOverride: override);

      await courses.saveCourse(updated);
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('课程已保存')));
      return;
    }

    // ── 新增 ──
    final Course created = Course(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      teacher: teacher,
      unit: _unit,
      category: category,
      timePlaces: places,
      sourcePluginId: kUserSourcePluginId,
      userOverride: _buildOverride(
        base: null,
        name: name,
        teacher: teacher,
        note: note,
        places: places,
      ),
    );
    await courses.saveCourse(created);
    if (!mounted) return;
    navigator.pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('课程已添加')));
  }

  /// 构造新的覆盖层。
  ///
  /// 四条规则：
  /// 1. **颜色**：始终按表单值写（`null` = 未覆盖，走"自动"配色）；
  /// 2. **名称 / 教师**：只在**与原始值不同**时才写覆盖；改回原值就不覆盖
  ///    （避免留下"改了等于没改"的空覆盖，那会让下次同步无谓地判成有变化）；
  /// 3. **时间地点**：只有用户**真的改过**才写 `customTimePlaces`——
  ///    没改就不写，让课程继续跟着教务的原始安排走
  ///    （教务调课了也该跟着变，不该被一次无意义的"保存"冻结住）；
  /// 4. **`hidden` 必须原样保留**：否则"隐藏了某门课 → 顺手编辑一下"
  ///    会让它重新出现在课表里。
  ///
  /// 新增模式（[base] 与 `widget.course` 都为 `null`）下规则 2 退化为
  /// "一律不写覆盖层"——因为新课程的原始字段就是用户填的值。
  ///
  /// 返回 `null` 表示新覆盖层是空的，等价于"没有覆盖层"。
  UserOverride? _buildOverride({
    required UserOverride? base,
    required String name,
    required String teacher,
    required String note,
    required List<TimePlace> places,
  }) {
    final Course? original = widget.course;
    final bool placesChanged =
        original != null && !_samePlaces(places, _originalPlaces);

    final UserOverride draft = UserOverride(
      customColor: _selectedColor,
      // 新增时不写 customName/customTeacher（原始字段已承载）；
      // 编辑时只在改动过才写。
      customName: original == null || name == original.name ? null : name,
      customTeacher:
          original == null || teacher == original.teacher ? null : teacher,
      note: note.isEmpty ? null : note,
      hidden: base?.hidden ?? false,
      customTimePlaces: placesChanged ? places : null,
      updatedAt: DateTime.now(),
    );
    return draft.isEmpty ? null : draft;
  }

  /// 两个时间地点列表是否等价（按值比较，与顺序无关）。
  ///
  /// 用序列化字符串比较：`TimePlace` 没有实现 `==`，
  /// 而它的字段都是标量 + `List<int>`，序列化后比较既准又省事。
  static bool _samePlaces(List<TimePlace> a, List<TimePlace> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    String key(TimePlace tp) => '${tp.day}/${tp.startSession}/${tp.length}/'
        '${tp.room}/${tp.weekType.name}'
        '/${(List<int>.of(tp.weeks)..sort()).join(",")}';
    final List<String> ka = a.map(key).toList()..sort();
    final List<String> kb = b.map(key).toList()..sort();
    for (int i = 0; i < ka.length; i++) {
      if (ka[i] != kb[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme theme = AppThemeExtension.of(context);
    final int totalWeeks = _totalWeeks;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑课程' : '添加课程'),
        centerTitle: true,
        actions: <Widget>[
          // 删除 / 隐藏（Phase 5）。语义按课程来源分岔，见 _confirmDelete。
          if (_isEditing)
            IconButton(
              icon: Icon(
                _isUserCourse ? Icons.delete_outline : Icons.visibility_off_outlined,
              ),
              tooltip: _isUserCourse ? '删除课程' : '从课表隐藏',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(theme.cardPadding * 1.5),
          children: <Widget>[
            _SectionTitle(theme: theme, text: '基本信息'),

            TextFormField(
              controller: _nameController,
              maxLength: kMaxCourseNameLength,
              decoration: InputDecoration(
                labelText: '课程名',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(fontSize: theme.bodySize),
              validator: (String? value) {
                final String text = (value ?? '').trim();
                if (text.isEmpty) return '请输入课程名';
                if (text.length > kMaxCourseNameLength) {
                  return '课程名不能超过 $kMaxCourseNameLength 个字';
                }
                return null;
              },
            ),
            SizedBox(height: theme.gridGap * 2),

            TextFormField(
              controller: _teacherController,
              decoration: InputDecoration(
                labelText: '教师（可选）',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(fontSize: theme.bodySize),
            ),
            SizedBox(height: theme.sectionGap),

            // 学分
            _FieldLabel(theme: theme, text: '学分'),
            if (!_canEditSchoolFields)
              _ReadOnlyNotice(
                theme: theme,
                text: '学分与类别来自教务系统，暂不支持修改'
                    '（改了下一次同步也会被覆盖回来）。',
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Slider(
                    value: _unit,
                    min: kMinUnit,
                    max: kMaxUnit,
                    divisions: ((kMaxUnit - kMinUnit) / kUnitStep).round(),
                    label: _formatUnit(_unit),
                    activeColor: theme.primary,
                    // 插件课程的学分只读：置灰并忽略拖动。
                    onChanged: _canEditSchoolFields
                        ? (double value) => setState(() => _unit = value)
                        : null,
                  ),
                ),
                SizedBox(
                  width: theme.timetableTimeColumnWidth + theme.cardPadding,
                  child: Text(
                    _formatUnit(_unit),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: theme.bodySize,
                      color: _canEditSchoolFields
                          ? theme.onBackground
                          : theme.onBackground.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: theme.sectionGap),

            TextFormField(
              controller: _categoryController,
              // 插件课程的类别只读（同上）。
              readOnly: !_canEditSchoolFields,
              decoration: InputDecoration(
                labelText: '课程类别（可选）',
                hintText: '如：专业必修课',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(
                fontSize: theme.bodySize,
                color: _canEditSchoolFields
                    ? theme.onBackground
                    : theme.onBackground.withValues(alpha: 0.45),
              ),
            ),
            SizedBox(height: theme.sectionGap),

            // 颜色
            _FieldLabel(theme: theme, text: '课程颜色'),
            _ColorPicker(
              theme: theme,
              palette: theme.courseCardColors,
              selected: _selectedColor,
              onChanged: (int? value) =>
                  setState(() => _selectedColor = value),
            ),
            SizedBox(height: theme.sectionGap * 1.5),

            // 时间段
            Row(
              children: <Widget>[
                Expanded(child: _SectionTitle(theme: theme, text: '上课时间地点')),
                TextButton.icon(
                  onPressed: _addDraft,
                  icon: Icon(Icons.add, size: theme.bodySize),
                  label: Text('添加时间段',
                      style: TextStyle(fontSize: theme.bodySize)),
                  style: TextButton.styleFrom(foregroundColor: theme.primary),
                ),
              ],
            ),
            for (int i = 0; i < _drafts.length; i++)
              _TimePlaceCard(
                key: ObjectKey(_drafts[i]),
                theme: theme,
                index: i,
                draft: _drafts[i],
                totalWeeks: totalWeeks,
                onChanged: () => setState(() {}),
                onRemove: () => _removeDraft(i),
              ),
            SizedBox(height: theme.sectionGap),

            _SectionTitle(theme: theme, text: '备注'),
            TextFormField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '备注（可选）',
                labelStyle: TextStyle(fontSize: theme.bodySize),
              ),
              style: TextStyle(fontSize: theme.bodySize),
            ),
            SizedBox(height: theme.sectionGap * 1.5),

            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                SizedBox(width: theme.gridGap * 2),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: theme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.buttonRadius),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 学分展示：整数去掉小数点（`3.0` → `3`）。
String _formatUnit(double unit) {
  if (unit == unit.roundToDouble()) return unit.round().toString();
  return unit.toString();
}

/// 一个时间段的草稿（可变，供表单编辑；保存时转成 [TimePlace]）。
class _TimePlaceDraft {
  /// [endWeek] 由调用方按学期总周数传入，避免默认值超出学期范围
  /// （否则会把课程排到学期结束之后）。
  _TimePlaceDraft({required this.endWeek});

  /// 从已有安排反填（Phase 5 编辑模式）。
  ///
  /// 周次区间的还原策略：优先用 [TimePlace.weeks] 的**最小/最大值**——
  /// 它一定是解析好的真值；`rawWeeksText` 只是展示文本，可能解析不出
  /// （例如它是全角标点或乱码）。两者都拿不到时退化成"整个学期"。
  ///
  /// [totalWeeks] 用来把越界的周次收进当前学期（学期周数改小过的情况）。
  factory _TimePlaceDraft.fromTimePlace(
    TimePlace tp, {
    required int totalWeeks,
  }) {
    final int maxWeek = totalWeeks < 1 ? 1 : totalWeeks;
    int startWeek = 1;
    int endWeek = maxWeek;
    if (tp.weeks.isNotEmpty) {
      final List<int> sorted = List<int>.of(tp.weeks)..sort();
      startWeek = sorted.first.clamp(1, maxWeek);
      endWeek = sorted.last.clamp(1, maxWeek);
    }
    final _TimePlaceDraft draft = _TimePlaceDraft(endWeek: endWeek)
      ..day = tp.day.clamp(1, _kDaysPerWeek)
      ..startSession = tp.startSession.clamp(1, _kMaxSessions)
      ..length = tp.length.clamp(kMinLength, kMaxLength)
      ..startWeek = startWeek
      ..weekType = tp.weekType;
    draft.roomController.text = tp.room;
    return draft;
  }

  int day = 1;
  int startSession = 1;
  int length = 2;
  int startWeek = 1;
  int endWeek;
  WeekType weekType = WeekType.all;
  final TextEditingController roomController = TextEditingController();

  void dispose() => roomController.dispose();
}

/// 时间段编辑卡片。
class _TimePlaceCard extends StatelessWidget {
  const _TimePlaceCard({
    super.key,
    required this.theme,
    required this.index,
    required this.draft,
    required this.totalWeeks,
    required this.onChanged,
    required this.onRemove,
  });

  final AppTheme theme;
  final int index;
  final _TimePlaceDraft draft;
  final int totalWeeks;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      padding: EdgeInsets.all(theme.cardPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.cardShadowColor,
            blurRadius: theme.cardShadowBlur,
            offset: Offset(0, theme.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '时间段 ${index + 1}',
                  style: TextStyle(
                    fontSize: theme.bodySize,
                    fontWeight: theme.titleFontWeight,
                    color: theme.onBackground,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: theme.bodySize + 4),
                tooltip: '删除该时间段',
                color: theme.onBackground.withValues(alpha: 0.5),
                onPressed: onRemove,
              ),
            ],
          ),

          // 星期
          _FieldLabel(theme: theme, text: '星期'),
          Wrap(
            spacing: theme.gridGap * 2,
            runSpacing: theme.gridGap * 2,
            children: <Widget>[
              for (int day = 1; day <= kDaysPerWeek; day++)
                ChoiceChip(
                  label: Text(kWeekdayLabels[day - 1]),
                  selected: draft.day == day,
                  onSelected: (bool _) {
                    draft.day = day;
                    onChanged();
                  },
                  labelStyle: TextStyle(
                    fontSize: theme.captionSize,
                    color: draft.day == day
                        ? theme.onPrimary
                        : theme.onBackground,
                  ),
                  selectedColor: theme.primary,
                  backgroundColor: theme.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.chipRadius),
                  ),
                ),
            ],
          ),
          SizedBox(height: theme.sectionGap),

          // 起始节次 / 持续节数
          Row(
            children: <Widget>[
              Expanded(
                child: _NumberDropdown(
                  theme: theme,
                  label: '起始节次',
                  value: draft.startSession,
                  min: 1,
                  max: kMaxSessions,
                  onChanged: (int value) {
                    draft.startSession = value;
                    onChanged();
                  },
                ),
              ),
              SizedBox(width: theme.cardPadding),
              Expanded(
                child: _NumberDropdown(
                  theme: theme,
                  label: '持续节数',
                  value: draft.length,
                  min: kMinLength,
                  max: kMaxLength,
                  onChanged: (int value) {
                    draft.length = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: theme.sectionGap),

          // 教室
          TextFormField(
            controller: draft.roomController,
            decoration: InputDecoration(
              labelText: '教室（可选）',
              labelStyle: TextStyle(fontSize: theme.bodySize),
            ),
            style: TextStyle(fontSize: theme.bodySize),
          ),
          SizedBox(height: theme.sectionGap),

          // 周次范围
          _FieldLabel(
            theme: theme,
            text: '周次：第 ${draft.startWeek} - ${draft.endWeek} 周',
          ),
          _WeekRangeSlider(
            theme: theme,
            totalWeeks: totalWeeks,
            startWeek: draft.startWeek,
            endWeek: draft.endWeek,
            onChanged: (int start, int end) {
              draft.startWeek = start;
              draft.endWeek = end;
              onChanged();
            },
          ),
          SizedBox(height: theme.sectionGap),

          // 单双周
          _FieldLabel(theme: theme, text: '单双周'),
          Wrap(
            spacing: theme.gridGap * 2,
            children: <Widget>[
              for (final WeekType type in WeekType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: draft.weekType == type,
                  onSelected: (bool _) {
                    draft.weekType = type;
                    onChanged();
                  },
                  labelStyle: TextStyle(
                    fontSize: theme.captionSize,
                    color: draft.weekType == type
                        ? theme.onPrimary
                        : theme.onBackground,
                  ),
                  selectedColor: theme.primary,
                  backgroundColor: theme.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.chipRadius),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 周次范围选择：`RangeSlider`（1..totalWeeks）。
///
/// 用 RangeSlider 而不是两行数字 chip：总周数最多 30，chip 行会很长；
/// 而且 RangeSlider 天然保证"起始周 <= 结束周"。
class _WeekRangeSlider extends StatelessWidget {
  const _WeekRangeSlider({
    required this.theme,
    required this.totalWeeks,
    required this.startWeek,
    required this.endWeek,
    required this.onChanged,
  });

  final AppTheme theme;
  final int totalWeeks;
  final int startWeek;
  final int endWeek;
  final void Function(int start, int end) onChanged;

  @override
  Widget build(BuildContext context) {
    // 只有 1 周时没有可拖动的区间
    if (totalWeeks <= 1) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: theme.gridGap * 2),
        child: Text(
          '第 1 周',
          style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
        ),
      );
    }

    return RangeSlider(
      values: RangeValues(
        startWeek.clamp(1, totalWeeks).toDouble(),
        endWeek.clamp(1, totalWeeks).toDouble(),
      ),
      min: 1,
      max: totalWeeks.toDouble(),
      divisions: totalWeeks - 1,
      labels: RangeLabels('第 $startWeek 周', '第 $endWeek 周'),
      activeColor: theme.primary,
      onChanged: (RangeValues values) =>
          onChanged(values.start.round(), values.end.round()),
    );
  }
}

/// 数字下拉选择（起始节次 / 持续节数）。
class _NumberDropdown extends StatelessWidget {
  const _NumberDropdown({
    required this.theme,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final AppTheme theme;
  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(theme: theme, text: label),
        DropdownButton<int>(
          value: value.clamp(min, max),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: TextStyle(fontSize: theme.bodySize, color: theme.onBackground),
          items: <DropdownMenuItem<int>>[
            for (int i = min; i <= max; i++)
              DropdownMenuItem<int>(value: i, child: Text('$i')),
          ],
          onChanged: (int? picked) {
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// 颜色选择器：预设色 + "自动"（`null`，由系统哈希分配）。
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onChanged,
  });

  final AppTheme theme;
  final List<Color> palette;

  /// `null` 表示选中"自动"。
  final int? selected;
  final void Function(int? value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: theme.gridGap * 2,
      runSpacing: theme.gridGap * 2,
      children: <Widget>[
        for (final Color color in palette)
          _ColorDot(
            theme: theme,
            color: color,
            selected: selected == color.toARGB32(),
            onTap: () => onChanged(color.toARGB32()),
          ),
        // "自动"：不指定颜色，交给主题按课程 id 哈希分配
        ChoiceChip(
          label: Text('自动'),
          selected: selected == null,
          onSelected: (bool _) => onChanged(null),
          labelStyle: TextStyle(
            fontSize: theme.captionSize,
            color: selected == null ? theme.onPrimary : theme.onBackground,
          ),
          selectedColor: theme.primary,
          backgroundColor: theme.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.chipRadius),
          ),
        ),
      ],
    );
  }
}

/// 单个色块。
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.theme,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: theme.timetableTimeColumnWidth * 0.75,
        height: theme.timetableTimeColumnWidth * 0.75,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? theme.primary : theme.background,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: theme.captionSize, color: theme.primary)
            : null,
      ),
    );
  }
}

/// 区块标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          fontWeight: theme.titleFontWeight,
          color: theme.primary,
        ),
      ),
    );
  }
}

/// 只读字段的说明条（Phase 5：编辑插件课程时学分 / 类别不可改）。
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap * 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: theme.captionSize,
            // 用主题的 warning 令牌，不硬编码黄色（CONTEXT 3.2）。
            color: theme.warning,
          ),
          SizedBox(width: theme.gridGap),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: theme.captionSize,
                color: theme.onBackground.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 字段上方的小标题。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: theme.gridGap),
      child: Text(
        text,
        style: TextStyle(
          fontSize: theme.captionSize,
          color: theme.onBackground.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
// Phase 8：学习通插件 ↔ 内核接线的验证测试。
//
// 数据不是编造的：下面 [kRealCourseList] / [kRealHomework] / [kRealExam]
// 是 `tools/chaoxing/test-plugin.js` 在**真实账号**上跑出来的插件返回值原文
// （2026-10-16）。因此这些用例真正验证的是"插件产出的形状内核读得懂"，
// 而不只是"内核读得懂我自己编的形状"。
//
// 覆盖：
//   1. 课程引用：解析、去重、原样透传（内核不认识学校字段）
//   2. 作业 / 考试：逐字段映射（含 Phase 8 新增的 note / courseName）
//   3. 覆盖层保留：插件重同步不会冲掉用户的勾选 / 隐藏 / 备注
//   4. 排序：未完成在前、无截止时间垫底、考试按开考时间
//   5. 同步服务：入口缺失 / 插件缺失时的降级
//   6. 站内消息文案：课程 / 作业 / 考试的量词
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/exam.dart';
import 'package:my_schedule_app/models/homework.dart';
import 'package:my_schedule_app/models/message.dart';
import 'package:my_schedule_app/models/plugin_course_ref.dart';
import 'package:my_schedule_app/models/sync_report.dart';
import 'package:my_schedule_app/models/user_override.dart';
import 'package:my_schedule_app/providers/exam_provider.dart';
import 'package:my_schedule_app/providers/homework_provider.dart';
import 'package:my_schedule_app/runtime/js_sandbox.dart';
import 'package:my_schedule_app/runtime/plugin_handle.dart';
import 'package:my_schedule_app/services/plugin_entity_sync_service.dart';

/// 真实 `fetchCourseList` 返回值的前 3 条（共 68 条，此处截取以保持用例可读）。
const String kRealCourseList = '''
{
  "courses": [
    {"id":"267787514_156498244","courseId":"267787514","classId":"156498244",
     "cpi":"344942005","name":"综合评价方法","teacher":"周丽晖","className":"23计3"},
    {"id":"267126809_155325476","courseId":"267126809","classId":"155325476",
     "cpi":"340484539","name":"软件工程C-2026","teacher":"石琳","className":"23计1-3"},
    {"id":"241979849_155051855","courseId":"241979849","classId":"155051855",
     "cpi":"335822651","name":"《国家学生体质健康标准》指导攻略",
     "teacher":"华北理工大学体育部","className":"2026秋测试2023级——人工智能学院"}
  ],
  "warnings": []
}
''';

/// 真实 `fetchHomeworks` 返回值（含正文，节选题目以保持可读）。
const String kRealHomework = '''
{
  "id": "chaoxing:57058627",
  "title": "第一章作业",
  "description": "题量：9　满分：100.0 分\\n\\n一.简答题 （共3 题,65.0分）\\n1. 简述多指标综合评价方法所具备的特点。",
  "courseName": "综合评价方法",
  "courseId": "chaoxing:267787514",
  "deadline": "2026-10-18T23:29:00",
  "publishTime": "2026-10-16T17:29:00",
  "completed": false,
  "submitStatus": "待做",
  "attachments": [],
  "sourcePluginId": "chaoxing",
  "remindMinutesBefore": 0
}
''';

/// 真实 `fetchExams` 返回值。
const String kRealExam = '''
{
  "id": "chaoxing:10735748",
  "name": "形势与政策2026年秋",
  "startTime": "2026-09-18T09:00:00",
  "endTime": "2027-01-08T16:00:00",
  "location": "",
  "seatNumber": "",
  "examType": "",
  "unit": 0,
  "durationMinutes": 0,
  "courseId": "chaoxing:267126105",
  "courseName": "形势与政策7",
  "sourcePluginId": "chaoxing",
  "remindMinutesBefore": 0,
  "note": "待做 · 完成任务点80%"
}
''';

Map<String, dynamic> _decodeObject(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

void main() {
  // ───────────────────── 1. 课程引用 ─────────────────────

  group('课程引用（PluginCourseRef）', () {
    test('解析真实课程列表，展示字段正确', () {
      final List<PluginCourseRef> refs =
          parseCourseRefs(_decodeObject(kRealCourseList)['courses']);

      expect(refs, hasLength(3));
      expect(refs.first.id, '267787514_156498244');
      expect(refs.first.name, '综合评价方法');
      expect(refs.first.teacher, '周丽晖');
      expect(refs.first.className, '23计3');
      expect(refs.first.subtitle, '周丽晖 · 23计3');
      // 第 3 条的班级名很长，确认没有被截断 / 转义搞坏。
      expect(refs.last.displayName, '《国家学生体质健康标准》指导攻略');
    });

    test('toJson 原样透传，内核不增删任何字段', () {
      final List<PluginCourseRef> refs =
          parseCourseRefs(_decodeObject(kRealCourseList)['courses']);
      final Map<String, dynamic> json = refs.first.toJson();

      // 学校相关字段（courseId / classId / cpi）内核不解释，但必须一个不少地还回去。
      expect(json['courseId'], '267787514');
      expect(json['classId'], '156498244');
      expect(json['cpi'], '344942005');
      expect(json['name'], '综合评价方法');
      expect(json.keys.toSet(), <String>{
        'id', 'courseId', 'classId', 'cpi', 'name', 'teacher', 'className',
      });
    });

    test('非列表 / 元素不是对象时不抛异常', () {
      expect(parseCourseRefs(null), isEmpty);
      expect(parseCourseRefs('oops'), isEmpty);
      expect(parseCourseRefs(<Object?>[1, 'x', null]), isEmpty);
    });

    test('重复 id 去重且保持首次出现顺序', () {
      final List<PluginCourseRef> refs = dedupeCourseRefs(<PluginCourseRef>[
        PluginCourseRef(<String, dynamic>{'id': 'a', 'name': 'A'}),
        PluginCourseRef(<String, dynamic>{'id': 'b', 'name': 'B'}),
        PluginCourseRef(<String, dynamic>{'id': 'a', 'name': 'A2'}),
      ]);

      expect(refs.map((PluginCourseRef r) => r.id).toList(), <String>['a', 'b']);
      // 后出现的覆盖先出现的（保留最新那条的内容）。
      expect(refs.first.name, 'A2');
    });

    test('缺少 id 时退化为稳定标识，不会出现空 id', () {
      final PluginCourseRef ref =
          PluginCourseRef(<String, dynamic>{'name': '无 id 课程'});
      expect(ref.id, isNotEmpty);
      expect(ref.id, startsWith('anon_无 id 课程_'));
    });
  });

  // ───────────────────── 2. 作业 / 考试逐字段 ─────────────────────

  group('作业模型（Homework.fromJson）', () {
    test('真实返回值逐字段落到模型上', () {
      final Homework hw = Homework.fromJson(_decodeObject(kRealHomework));

      expect(hw.id, 'chaoxing:57058627');
      expect(hw.title, '第一章作业');
      expect(hw.courseName, '综合评价方法');
      expect(hw.courseId, 'chaoxing:267787514');
      expect(hw.deadline, DateTime(2026, 10, 18, 23, 29));
      expect(hw.publishTime, DateTime(2026, 10, 16, 17, 29));
      expect(hw.completed, isFalse);
      expect(hw.submitStatus, '待做');
      expect(hw.sourcePluginId, 'chaoxing');
      // 正文里的大题与题目要在（这是"连正文一起抓"的验收点）。
      expect(hw.description, contains('题量：9'));
      expect(hw.description, contains('简述多指标综合评价方法所具备的特点'));
    });

    test('展示口径：无覆盖层时回落原始值', () {
      final Homework hw = Homework.fromJson(_decodeObject(kRealHomework));
      expect(hw.displayTitle, '第一章作业');
      expect(hw.displayDeadline, DateTime(2026, 10, 18, 23, 29));
      expect(hw.isCompleted, isFalse);
      expect(hw.isHidden, isFalse);
    });

    test('逾期与倒计时（以固定"现在"断言，避免用例随时间漂移）', () {
      final Homework hw = Homework.fromJson(_decodeObject(kRealHomework));

      expect(hw.isOverdue(DateTime(2026, 10, 18, 23, 0)), isFalse);
      expect(hw.isOverdue(DateTime(2026, 10, 19, 0, 1)), isTrue);
      expect(hw.daysUntilDeadline(DateTime(2026, 10, 16, 18, 0)), 3);
      // 已逾期时倒计时归零（不是负数）。
      expect(hw.timeUntilDeadline(DateTime(2026, 10, 20)), Duration.zero);
    });
  });

  group('考试模型（Exam.fromJson）', () {
    test('真实返回值逐字段落到模型上（含 Phase 8 新增字段）', () {
      final Exam exam = Exam.fromJson(_decodeObject(kRealExam));

      expect(exam.id, 'chaoxing:10735748');
      expect(exam.name, '形势与政策2026年秋');
      expect(exam.startTime, DateTime(2026, 9, 18, 9));
      expect(exam.endTime, DateTime(2027, 1, 8, 16));
      expect(exam.courseId, 'chaoxing:267126105');
      expect(exam.courseName, '形势与政策7');
      expect(exam.note, '待做 · 完成任务点80%');
      expect(exam.sourcePluginId, 'chaoxing');
    });

    test('displayNote：用户备注优先于插件原文', () {
      final Exam exam = Exam.fromJson(_decodeObject(kRealExam));
      expect(exam.displayNote, '待做 · 完成任务点80%');

      final Exam withNote = exam.copyWith(
        userOverride: UserOverride(note: '在 A 楼机房', updatedAt: DateTime.now()),
      );
      expect(withNote.displayNote, '在 A 楼机房');
    });

    test('effectiveEndTime：有结束时间就用它，否则按时长推算', () {
      final Exam exam = Exam.fromJson(_decodeObject(kRealExam));
      expect(exam.effectiveEndTime, DateTime(2027, 1, 8, 16));

      final Exam noEnd = exam.copyWith(clearEndTime: true, durationMinutes: 90);
      expect(noEnd.effectiveEndTime, DateTime(2026, 9, 18, 10, 30));
    });
  });

  // ───────────────────── 3. 覆盖层保留 ─────────────────────

  group('覆盖层保留（插件重同步不冲掉用户修改）', () {
    test('作业：勾选完成后，插件再同步一次原始数据仍然保留勾选', () async {
      final HomeworkProvider provider = HomeworkProvider();
      final Homework incoming = Homework.fromJson(_decodeObject(kRealHomework));

      await provider.save(incoming);
      expect(provider.getById(incoming.id)!.isCompleted, isFalse);

      await provider.setCompleted(incoming.id, true);
      expect(provider.getById(incoming.id)!.isCompleted, isTrue);

      // 插件再次同步：传入的是**不带覆盖层**的原始作业。
      await provider.save(Homework.fromJson(_decodeObject(kRealHomework)));
      final Homework after = provider.getById(incoming.id)!;
      expect(after.isCompleted, isTrue, reason: '用户的勾选不该被同步冲掉');
      expect(after.userOverride, isNotNull);
    });

    test('作业：隐藏后，插件再同步一次仍然隐藏', () async {
      final HomeworkProvider provider = HomeworkProvider();
      final Homework incoming = Homework.fromJson(_decodeObject(kRealHomework));

      await provider.save(incoming);
      await provider.setHidden(incoming.id, true);
      await provider.save(Homework.fromJson(_decodeObject(kRealHomework)));

      expect(provider.getById(incoming.id)!.isHidden, isTrue);
      expect(provider.displayHomeworks, isEmpty);
      expect(provider.hiddenHomeworks, hasLength(1));
    });

    test('考试：隐藏后，插件再同步一次仍然隐藏', () async {
      final ExamProvider provider = ExamProvider();
      final Exam incoming = Exam.fromJson(_decodeObject(kRealExam));

      await provider.save(incoming);
      await provider.setHidden(incoming.id, true);
      await provider.save(Exam.fromJson(_decodeObject(kRealExam)));

      expect(provider.getById(incoming.id)!.isHidden, isTrue);
      expect(provider.displayExams, isEmpty);
      expect(provider.hiddenExams, hasLength(1));
    });

    test('setCompleted / setHidden 对不存在的 id 返回 false', () async {
      final HomeworkProvider provider = HomeworkProvider();
      expect(await provider.setCompleted('nope', true), isFalse);
      expect(await provider.setHidden('nope', true), isFalse);
      expect(await ExamProvider().setHidden('nope', true), isFalse);
    });
  });

  // ───────────────────── 4. 排序与统计 ─────────────────────

  group('列表排序与统计', () {
    test('作业：未完成在前，无截止时间的垫底', () {
      final HomeworkProvider provider = HomeworkProvider();
      provider.setHomeworks(<Homework>[
        _homework(id: 'c', title: 'C 无截止'),
        _homework(id: 'b', title: 'B 已逾期', deadline: DateTime(2026, 10, 1)),
        _homework(
            id: 'a', title: 'A 明天截止', deadline: DateTime(2026, 10, 20)),
        _homework(
            id: 'd',
            title: 'D 已完成',
            deadline: DateTime(2026, 10, 2),
            completed: true),
      ]);

      expect(
        provider.displayHomeworks.map((Homework h) => h.id).toList(),
        <String>['b', 'a', 'c', 'd'],
      );
    });

    test('考试：未开始在前并按开考时间升序', () {
      final ExamProvider provider = ExamProvider();
      provider.setExams(<Exam>[
        _exam(id: 'old', name: '很久以前', start: DateTime(2000, 1, 1)),
        _exam(id: 'far', name: '很远以后', start: DateTime(2099, 1, 1)),
        _exam(id: 'soon', name: '马上', start: DateTime(2098, 1, 1)),
      ]);

      expect(
        provider.displayExams.map((Exam e) => e.id).toList(),
        <String>['soon', 'far', 'old'],
      );
      expect(provider.upcomingCount, 2);
      expect(provider.nextExam(DateTime.now())!.id, 'soon');
    });

    test('作业：pendingCount 与 overdueCount 口径', () {
      final HomeworkProvider provider = HomeworkProvider();
      provider.setHomeworks(<Homework>[
        _homework(id: 'a', title: 'A', deadline: DateTime(2026, 10, 1)),
        _homework(
            id: 'b', title: 'B', deadline: DateTime(2026, 10, 30), completed: true),
      ]);

      expect(provider.pendingCount, 1);
      expect(provider.overdueCount(DateTime(2026, 10, 20)), 1);
      expect(provider.length, 2);
      expect(provider.hiddenCount, 0);
    });
  });

  // ───────────────────── 5. 同步服务降级 ─────────────────────

  group('PluginEntitySyncService', () {
    test('插件缺失 → unavailable（不是抛异常）', () async {
      final SyncReport report = await PluginEntitySyncService.sync<Homework>(
        pluginId: 'chaoxing',
        handle: null,
        spec: PluginEntitySyncService.homeworkSpec(),
        store: HomeworkProvider(),
      );

      expect(report.isSuccess, isFalse);
      expect(report.outcome, SyncOutcome.unavailable);
      expect(report.reason, contains('插件未加载'));
    });

    test('插件没有该入口 → unsupported', () async {
      const PluginHandle handle = PluginHandle(
        status: JsSandboxStatus.success,
        entries: <String>['fetchCourses'],
      );

      final SyncReport report = await PluginEntitySyncService.sync<Homework>(
        pluginId: 'chaoxing',
        handle: handle,
        spec: PluginEntitySyncService.homeworkSpec(),
        store: HomeworkProvider(),
      );

      expect(report.outcome, SyncOutcome.unsupported);
      expect(report.reason, contains('fetchHomeworks'));
    });

    test('onReport 在失败路径上也会被调用一次', () async {
      int calls = 0;
      await PluginEntitySyncService.sync<Exam>(
        pluginId: 'chaoxing',
        handle: null,
        spec: PluginEntitySyncService.examSpec(),
        store: ExamProvider(),
        onReport: (SyncReport _) => calls++,
      );
      expect(calls, 1);
    });

    test('fetchCourseRefs：插件缺失 / 入口缺失都返回可读错误', () async {
      final CourseRefFetchResult noPlugin =
          await PluginEntitySyncService.fetchCourseRefs(
        pluginId: 'chaoxing',
        handle: null,
      );
      expect(noPlugin.isSuccess, isFalse);
      expect(noPlugin.error, contains('插件未加载'));

      final CourseRefFetchResult noEntry =
          await PluginEntitySyncService.fetchCourseRefs(
        pluginId: 'chaoxing',
        handle: const PluginHandle(
          status: JsSandboxStatus.success,
          entries: <String>['fetchCourses'],
        ),
      );
      expect(noEntry.isSuccess, isFalse);
      expect(noEntry.error, contains('fetchCourseList'));
    });

    test('buildCoursesArgs：课程对象原样透传 + withContent 开关', () {
      final List<PluginCourseRef> refs =
          parseCourseRefs(_decodeObject(kRealCourseList)['courses']);
      final Map<String, dynamic> args =
          PluginEntitySyncService.buildCoursesArgs(refs);

      expect(args[PluginEntitySyncService.kArgWithContent], isTrue);
      final List<dynamic> courses = args[PluginEntitySyncService.kArgCourses] as List<dynamic>;
      expect(courses, hasLength(3));
      // 回传给插件的必须是**原始对象**（courseId/classId/cpi 都在），
      // 否则插件拿不到课程标识、抓取会失败。
      final Map<String, dynamic> first = courses.first as Map<String, dynamic>;
      expect(first['courseId'], '267787514');
      expect(first['classId'], '156498244');
      expect(first['cpi'], '344942005');
    });
  });

  // ───────────────────── 6. 契约工厂（指纹 / 覆盖层） ─────────────────────

  group('PluginEntitySpec 契约', () {
    test('作业指纹不含覆盖层（用户勾选不该被判成"数据变了"）', () {
      final PluginEntitySpec<Homework> spec =
          PluginEntitySyncService.homeworkSpec();
      final Homework raw = Homework.fromJson(_decodeObject(kRealHomework));
      final Homework withOverride = raw.copyWith(
        userOverride:
            UserOverride(customCompleted: true, updatedAt: DateTime.now()),
      );

      expect(spec.fingerprintOf(withOverride), spec.fingerprintOf(raw));
      expect(spec.hasOverride(withOverride), isTrue);
      expect(spec.hasOverride(raw), isFalse);
      expect(spec.idOf(raw), 'chaoxing:57058627');
      expect(spec.entry, 'fetchHomeworks');
      expect(spec.payloadKey, 'homeworks');
    });

    test('考试指纹不含覆盖层', () {
      final PluginEntitySpec<Exam> spec = PluginEntitySyncService.examSpec();
      final Exam raw = Exam.fromJson(_decodeObject(kRealExam));
      final Exam withOverride = raw.copyWith(
        userOverride: UserOverride(note: '备注', updatedAt: DateTime.now()),
      );

      expect(spec.fingerprintOf(withOverride), spec.fingerprintOf(raw));
      expect(spec.hasOverride(withOverride), isTrue);
      expect(spec.entry, 'fetchExams');
      expect(spec.payloadKey, 'exams');
    });

    test('原始字段变化会改变指纹（保证"更新"能被识别）', () {
      final PluginEntitySpec<Homework> spec =
          PluginEntitySyncService.homeworkSpec();
      final Homework raw = Homework.fromJson(_decodeObject(kRealHomework));
      final Homework changed = raw.copyWith(title: '改了标题');

      expect(spec.fingerprintOf(changed), isNot(spec.fingerprintOf(raw)));
    });
  });

  // ───────────────────── 7. 站内消息文案 ─────────────────────

  group('同步结果 → 站内消息', () {
    test('课程文案与 Phase 7 完全一致（向后兼容）', () {
      final Message message = Message.fromSyncReport(
        report: const SyncReport(
          pluginId: 'ncst-jwxt',
          outcome: SyncOutcome.success,
          added: 2,
          updated: 1,
          unchanged: 5,
        ),
        pluginName: '教务系统',
      );

      expect(message.title, '教务系统 同步完成');
      expect(message.body, contains('新增 2 · 更新 1 · 未变 5'));
    });

    test('课程"已是最新"文案未被 Phase 8 改动', () {
      final Message message = Message.fromSyncReport(
        report: const SyncReport(
          pluginId: 'ncst-jwxt',
          outcome: SyncOutcome.success,
          unchanged: 68,
        ),
        pluginName: '教务系统',
      );

      expect(message.body, contains('68门课程已是最新，无需更新'));
    });

    test('作业 / 考试使用各自量词', () {
      final Message homework = Message.fromSyncReport(
        report: const SyncReport(
          pluginId: 'chaoxing',
          outcome: SyncOutcome.success,
          unchanged: 1,
        ),
        pluginName: '学习通（超星）',
        itemLabel: '作业',
        itemUnit: '份',
      );
      expect(homework.body, contains('1份作业已是最新，无需更新'));

      final Message exam = Message.fromSyncReport(
        report: const SyncReport(
          pluginId: 'chaoxing',
          outcome: SyncOutcome.success,
          added: 1,
        ),
        pluginName: '学习通（超星）',
        itemLabel: '考试',
        itemUnit: '场',
      );
      expect(exam.body, contains('新增 1 · 更新 0 · 未变 0'));

      final Message empty = Message.fromSyncReport(
        report: const SyncReport(
          pluginId: 'chaoxing',
          outcome: SyncOutcome.success,
        ),
        pluginName: '学习通（超星）',
        itemLabel: '考试',
        itemUnit: '场',
      );
      expect(empty.body, contains('没有考试'));
    });
  });
}

// ───────────────────────── 测试辅助 ─────────────────────────

/// 构造一份最小作业，只关心排序 / 统计用例需要的字段。
Homework _homework({
  required String id,
  required String title,
  DateTime? deadline,
  bool completed = false,
}) {
  return Homework(
    id: id,
    title: title,
    deadline: deadline,
    completed: completed,
    sourcePluginId: 'chaoxing',
  );
}

/// 构造一份最小考试。
Exam _exam({required String id, required String name, required DateTime start}) {
  return Exam(id: id, name: name, startTime: start, sourcePluginId: 'chaoxing');
}

// Phase 9：作业提醒的排期与设置解析（纯逻辑，不碰网络 / 存储）。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/models/homework.dart';
import 'package:my_schedule_app/models/homework_reminder_plan.dart';
import 'package:my_schedule_app/models/homework_reminder_settings.dart';
import 'package:my_schedule_app/models/plugin_course_ref.dart';
import 'package:my_schedule_app/models/user_override.dart';
import 'package:my_schedule_app/runtime/js_sandbox.dart';
import 'package:my_schedule_app/services/homework_check_entry.dart';

/// 造一份作业（默认未完成、有截止时间）。
Homework _homework({
  String id = 'chaoxing:1',
  String title = '第 3 章习题',
  String courseName = '高等数学',
  String courseId = 'chaoxing:1001',
  String pluginId = 'chaoxing',
  DateTime? deadline,
  bool completed = false,
  UserOverride? override,
}) {
  return Homework(
    id: id,
    title: title,
    courseName: courseName,
    courseId: courseId,
    deadline: deadline,
    completed: completed,
    sourcePluginId: pluginId,
    userOverride: override,
  );
}

void main() {
  final DateTime now = DateTime(2026, 10, 18, 12, 0);

  group('HomeworkReminderSettings', () {
    test('归一化：去重、降序、丢弃非正数', () {
      expect(
        HomeworkReminderSettings.normalizeOffsets(<int>[10, 60, 30, 10, 0, -5]),
        <int>[60, 30, 10],
      );
    });

    test('归一化：超过上限截断', () {
      final List<int> many =
          List<int>.generate(kMaxReminderOffsets + 3, (int i) => i + 1);
      expect(HomeworkReminderSettings.normalizeOffsets(many).length,
          kMaxReminderOffsets);
    });

    test('默认值：关闭、三档、校验失败仍提醒', () {
      const HomeworkReminderSettings s = HomeworkReminderSettings();
      expect(s.enabled, isFalse);
      expect(s.offsetsMinutes, kDefaultReminderOffsets);
      expect(s.notifyWhenCheckFails, isTrue);
      expect(s.isEffective, isFalse);
    });

    test('JSON 往返一致', () {
      final HomeworkReminderSettings s = HomeworkReminderSettings.decode(
        const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[120, 5],
          notifyWhenCheckFails: false,
        ).encode(),
      );
      expect(s.enabled, isTrue);
      expect(s.offsetsMinutes, <int>[120, 5]);
      expect(s.notifyWhenCheckFails, isFalse);
    });

    test('坏数据回落默认值（不抛异常）', () {
      expect(HomeworkReminderSettings.decode('不是 JSON').enabled, isFalse);
      // 档位字段类型不对 → 回落默认三档（比"静默变成不提醒"安全）
      expect(
        HomeworkReminderSettings.decode(
          '{"enabled":true,"offsetsMinutes":"x"}',
        ).offsetsMinutes,
        kDefaultReminderOffsets,
      );
      expect(HomeworkReminderSettings.decode(null).enabled, isFalse);
    });

    test('档位文案：整小时用小时，整天用天', () {
      expect(HomeworkReminderSettings.describeOffset(60), '截止前 1 小时');
      expect(HomeworkReminderSettings.describeOffset(1440), '截止前 1 天');
      expect(HomeworkReminderSettings.describeOffset(45), '截止前 45 分钟');
    });
  });

  group('buildHomeworkReminderPlan', () {
    test('关闭时不排任何提醒', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(),
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('每个档位一条，按触发时刻升序，slot 从"最远的一档"数起', () {
      // 截止 15:00，现在 12:00 → 三档都还在未来：14:00 / 14:30 / 14:50
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60, 30, 10],
        ),
        now: now,
      );
      expect(plan.length, 3);
      expect(
        plan.map((HomeworkReminderItem i) => i.offsetMinutes),
        <int>[60, 30, 10],
      );
      expect(plan.first.fireAt, now.add(const Duration(minutes: 120)));
      expect(plan.last.fireAt, now.add(const Duration(minutes: 170)));
      expect(plan.map((HomeworkReminderItem i) => i.slot), <int>[1, 2, 3]);
      expect(plan.first.totalSlots, 3);
    });

    test('已过触发点的档位被剔除（不会"刚排好就立刻响"）', () {
      // 截止 12:30，现在 12:00：60 分钟档（11:30）已过，只剩 30 分钟档
      // （12:00，正好等于 now）与 10 分钟档（12:20）——12:00 在 minLead 内也要剔除。
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(minutes: 30))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60, 30, 10],
        ),
        now: now,
      );
      expect(plan.map((HomeworkReminderItem i) => i.offsetMinutes), <int>[10]);
    });

    test('已完成 / 已隐藏 / 无截止时间 / 已逾期 都不排', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(id: 'a', deadline: now.add(const Duration(hours: 3)),
              completed: true),
          _homework(
            id: 'b',
            deadline: now.add(const Duration(hours: 3)),
            override: UserOverride(updatedAt: now, hidden: true),
          ),
          _homework(id: 'c'),
          _homework(id: 'd', deadline: now.subtract(const Duration(hours: 1))),
          // 用户勾了完成（覆盖层优先于插件原值）
          _homework(
            id: 'e',
            deadline: now.add(const Duration(hours: 3)),
            override: UserOverride(updatedAt: now, customCompleted: true),
          ),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
        ),
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('带上匹配的 courseRef（作业 courseId 带插件前缀）', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
        ),
        now: now,
        refsByPlugin: <String, List<PluginCourseRef>>{
          'chaoxing': <PluginCourseRef>[
            PluginCourseRef(<String, dynamic>{
              'id': '1001_2001',
              'courseId': '1001',
              'classId': '2001',
              'cpi': '3001',
              'name': '高等数学',
            }),
          ],
        },
      );
      expect(plan.length, 1);
      expect(plan.first.courseRef?['courseId'], '1001');
      expect(plan.first.courseRef?['cpi'], '3001');
    });

    test('课程 ref 对不上时 courseRef 为 null（后台校验会自己补拉）', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
        ),
        now: now,
        refsByPlugin: <String, List<PluginCourseRef>>{
          'chaoxing': <PluginCourseRef>[
            PluginCourseRef(<String, dynamic>{'id': 'x', 'courseId': '999'}),
          ],
        },
      );
      expect(plan.first.courseRef, isNull);
    });

    test('条数上限生效', () {
      final List<Homework> many = List<Homework>.generate(
        30,
        (int i) => _homework(
          id: 'h$i',
          deadline: now.add(Duration(hours: 3, minutes: i)),
        ),
      );
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: many,
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60, 30, 10],
        ),
        now: now,
        maxItems: 10,
      );
      expect(plan.length, 10);
    });

    test('"校验失败仍提醒"偏好被快照进每条排期', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
          notifyWhenCheckFails: false,
        ),
        now: now,
      );
      expect(plan.first.notifyWhenCheckFails, isFalse);
    });

    test('通知文案包含课程、标题与剩余时间', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
        ),
        now: now,
      );
      final HomeworkReminderItem item = plan.first;
      expect(item.notificationTitle, '作业提醒 · 高等数学');
      expect(item.notificationBody, contains('第 3 章习题'));
      expect(item.notificationBody, contains('1 小时'));
    });

    test('JSON 往返：字段不丢（原生靠它排闹钟）', () {
      final List<HomeworkReminderItem> plan = buildHomeworkReminderPlan(
        homeworks: <Homework>[
          _homework(deadline: now.add(const Duration(hours: 3))),
        ],
        settings: const HomeworkReminderSettings(
          enabled: true,
          offsetsMinutes: <int>[60],
        ),
        now: now,
      );
      final Map<String, dynamic> json = plan.first.toJson();
      final HomeworkReminderItem back = HomeworkReminderItem.fromJson(json);
      expect(back.homeworkId, plan.first.homeworkId);
      expect(back.fireAt, plan.first.fireAt);
      expect(back.offsetMinutes, 60);
      expect(back.pluginId, 'chaoxing');
    });
  });

  group('HomeworkStatusChecker.interpretFetchResult', () {
    const String target = 'chaoxing:123';

    String payload(List<Map<String, Object?>> items) {
      return '{"homeworks":${items.map((Map<String, Object?> m) => _jsonOf(m)).toList()}}';
    }

    test('远端已完成 → completed（不打扰）', () {
      final HomeworkCheckResult r = HomeworkStatusChecker.interpretFetchResult(
        JsSandboxResult.success(
          payload(<Map<String, Object?>>[
            <String, Object?>{'id': target, 'completed': true},
          ]),
        ),
        target,
      );
      expect(r.status, HomeworkCheckStatus.completed);
      expect(r.isCompleted, isTrue);
    });

    test('远端未完成 → pending（照常提醒）', () {
      final HomeworkCheckResult r = HomeworkStatusChecker.interpretFetchResult(
        JsSandboxResult.success(
          payload(<Map<String, Object?>>[
            <String, Object?>{'id': target, 'completed': false},
          ]),
        ),
        target,
      );
      expect(r.status, HomeworkCheckStatus.pending);
    });

    test('只关心目标作业（同课其它作业的完成状态不影响判断）', () {
      final HomeworkCheckResult r = HomeworkStatusChecker.interpretFetchResult(
        JsSandboxResult.success(
          payload(<Map<String, Object?>>[
            <String, Object?>{'id': 'other', 'completed': true},
            <String, Object?>{'id': target, 'completed': false},
          ]),
        ),
        target,
      );
      expect(r.status, HomeworkCheckStatus.pending);
    });

    test('插件返回 error → unknown（交给"校验失败仍提醒"策略）', () {
      final HomeworkCheckResult r = HomeworkStatusChecker.interpretFetchResult(
        JsSandboxResult.success('{"error":"登录已过期"}'),
        target,
      );
      expect(r.status, HomeworkCheckStatus.unknown);
      expect(r.reason, contains('登录已过期'));
    });

    test('执行失败 / 返回值不是 JSON → unknown', () {
      expect(
        HomeworkStatusChecker.interpretFetchResult(
          JsSandboxResult.error('boom'),
          target,
        ).status,
        HomeworkCheckStatus.unknown,
      );
      expect(
        HomeworkStatusChecker.interpretFetchResult(
          JsSandboxResult.success('不是 JSON'),
          target,
        ).status,
        HomeworkCheckStatus.unknown,
      );
      expect(
        HomeworkStatusChecker.interpretFetchResult(
          JsSandboxResult.success('{"homeworks":{}}'),
          target,
        ).status,
        HomeworkCheckStatus.unknown,
      );
    });

    test('列表里找不到该作业 → pending（宁可提醒）', () {
      final HomeworkCheckResult r = HomeworkStatusChecker.interpretFetchResult(
        JsSandboxResult.success(
          payload(<Map<String, Object?>>[
            <String, Object?>{'id': 'other', 'completed': true},
          ]),
        ),
        target,
      );
      expect(r.status, HomeworkCheckStatus.pending);
      expect(r.reason, contains('没找到'));
    });
  });

  group('matchCourseRefForCheck', () {
    test('去掉插件前缀后按 courseId 匹配', () {
      final PluginCourseRef? ref = matchCourseRefForCheck(
        courseId: 'chaoxing:1001',
        pluginId: 'chaoxing',
        refs: <PluginCourseRef>[
          PluginCourseRef(<String, dynamic>{'id': '1001_2001', 'courseId': '1001'}),
        ],
      );
      expect(ref?.id, '1001_2001');
    });

    test('没有前缀时按 ref.id 兜底匹配', () {
      final PluginCourseRef? ref = matchCourseRefForCheck(
        courseId: '1001_2001',
        pluginId: 'chaoxing',
        refs: <PluginCourseRef>[
          PluginCourseRef(<String, dynamic>{'id': '1001_2001', 'courseId': '1001'}),
        ],
      );
      expect(ref, isNotNull);
    });

    test('空输入返回 null', () {
      expect(
        matchCourseRefForCheck(
          courseId: '',
          pluginId: 'chaoxing',
          refs: const <PluginCourseRef>[],
        ),
        isNull,
      );
    });
  });
}

/// 极简 JSON 序列化（只用于测试里的字符串拼装，避免再引一个依赖）。
String _jsonOf(Map<String, Object?> map) {
  final List<String> parts = map.entries.map((MapEntry<String, Object?> e) {
    final Object? v = e.value;
    final String encoded = v is bool
        ? '$v'
        : v is num
            ? '$v'
            : '"${'$v'.replaceAll('"', r'\"')}"';
    return '"${e.key}":$encoded';
  }).toList();
  return '{${parts.join(',')}}';
}

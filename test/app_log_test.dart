// 运行日志的单元测试。
//
// 重点不是"能写进去"，而是三条**承诺**：
// 1. 只留近 24 小时（用户手机上的日志不会无限增长）；
// 2. 凭据永远不进日志（日志是要发给开发者的）；
// 3. 写盘的文件能被完整解析回来（否则导出的东西没法用）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/services/app_log.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('applog_test_');
    await AppLog.resetForTest();
    AppLog.retention = const Duration(hours: 24);
    AppLog.maxEntries = 3000;
    AppLog.maxFileBytes = 2 * 1024 * 1024;
    AppLog.floodLimitPerSecond = 300;
  });

  tearDown(() async {
    await AppLog.resetForTest();
    // Windows 上文件句柄的释放比 `close()` 的 Future 稍晚一点，
    // 偶尔会删不掉临时目录。删不掉不影响测试结论，交给系统清理即可。
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // 忽略。
    }
  });

  /// 用临时目录初始化（跳过 path_provider 的平台通道），
  /// 并关闭全局 hook —— 测试环境要保留自己的错误处理。
  Future<void> initLog() =>
      AppLog.init(dirOverride: tempDir.path, installHandlers: false);

  group('序列化', () {
    test('一条日志可以完整往返解析', () {
      final LogEntry entry = LogEntry(
        time: DateTime(2026, 10, 22, 16, 30, 30, 123),
        level: LogLevel.error,
        tag: 'sync',
        message: '同步失败：连接超时',
        data: <String, Object?>{'plugin': 'ncst-phylab', 'attempts': 3},
        error: 'TimeoutException after 0:00:20',
        stack: '#0 main (package:app/main.dart:1:1)',
      );

      final LogEntry? parsed = LogEntry.tryParse(entry.toLine());

      expect(parsed, isNotNull);
      expect(parsed!.time, entry.time);
      expect(parsed.level, LogLevel.error);
      expect(parsed.tag, 'sync');
      expect(parsed.message, '同步失败：连接超时');
      expect(parsed.data['plugin'], 'ncst-phylab');
      expect(parsed.data['attempts'], 3);
      expect(parsed.error, contains('TimeoutException'));
      expect(parsed.stack, contains('#0 main'));
    });

    test('没有附加信息时不写尾部 JSON', () {
      final LogEntry entry = LogEntry(
        time: DateTime(2026, 10, 22, 8, 0, 0),
        level: LogLevel.info,
        tag: 'app',
        message: '启动',
      );
      expect(entry.toLine().contains('\t'), isFalse);
    });

    test('message 里的换行和制表符被压成单行', () {
      final LogEntry entry = LogEntry(
        time: DateTime(2026, 10, 22, 8, 0, 0),
        level: LogLevel.debug,
        tag: 'print',
        message: '第一行\n第二行\t带制表符',
      );
      final String line = entry.toLine();
      // 一行一条：换行必须消失，否则解析会把它当成两条记录。
      expect(line.contains('\n'), isFalse);
      expect(LogEntry.tryParse(line)!.message, contains('第一行'));
    });

    test('格式不符的行返回 null 而不是抛异常', () {
      expect(LogEntry.tryParse(''), isNull);
      expect(LogEntry.tryParse('随便一行乱码'), isNull);
      // 级别字符非法
      expect(LogEntry.tryParse('2026-10-22 16:30:30.123 X tag msg'), isNull);
      // 时间不合法
      expect(LogEntry.tryParse('2026-13-45 16:30:30.123 I tag msg'), isNull);
    });

    test('尾部 JSON 损坏时仍能读出正文', () {
      final LogEntry? parsed = LogEntry.tryParse(
        '2026-10-22 16:30:30.123 I sync 同步完成\t{坏掉的 json',
      );
      expect(parsed, isNotNull);
      expect(parsed!.message, '同步完成');
      expect(parsed.data, isEmpty);
    });
  });

  group('脱敏', () {
    test('密码 / 令牌 / Cookie 一律替换成 ***', () {
      final Map<String, Object?> out = AppLog.redactMap(<String, Object?>{
        'password': 'hunter2',
        'Token': 'abc123',
        'cookie': 'SESSION=xyz',
        'userName': 'zhang',
      });

      expect(out['password'], '***');
      expect(out['Token'], '***');
      expect(out['cookie'], '***');
      // 非敏感字段原样保留
      expect(out['userName'], 'zhang');
    });

    test('嵌套结构里的敏感字段也会被抹掉', () {
      final Map<String, Object?> out = AppLog.redactMap(<String, Object?>{
        'headers': <String, Object?>{
          'Authorization': 'Bearer xxx',
          'Accept': 'application/json',
        },
        'items': <Object?>[
          <String, Object?>{'secret': 's', 'name': 'n'},
        ],
      });

      final Map<Object?, Object?> headers = out['headers']! as Map<Object?, Object?>;
      expect(headers['Authorization'], '***');
      expect(headers['Accept'], 'application/json');

      final List<Object?> items = out['items']! as List<Object?>;
      final Map<Object?, Object?> first = items.first! as Map<Object?, Object?>;
      expect(first['secret'], '***');
      expect(first['name'], 'n');
    });

    test('URL 只保留 scheme + host + path，丢掉 query', () {
      expect(
        AppLog.sanitizeUrl('https://jw.ncst.edu.cn/login?ticket=ST-123&x=1'),
        'https://jw.ncst.edu.cn/login',
      );
      expect(
        AppLog.sanitizeUrl('http://phylab.ncst.edu.cn:8100/BaseInfo/Index/#/x'),
        'http://phylab.ncst.edu.cn:8100/BaseInfo/Index/',
      );
      // 没有 scheme 的串原样返回（不猜）
      expect(AppLog.sanitizeUrl('not a url'), 'not a url');
    });

    test('写进日志的 data 已经是脱敏后的', () async {
      await initLog();
      AppLog.i('t', '登录', <String, Object?>{'password': 'p', 'user': 'u'});

      final LogEntry last = AppLog.snapshot().last;
      expect(last.data['password'], '***');
      expect(last.data['user'], 'u');
      // 文件里也不能留原文
      final String text = File(AppLog.filePath).readAsStringSync();
      expect(text.contains('"password":"p"'), isFalse);
    });
  });

  group('落盘与读回', () {
    test('写入后能立刻从文件读回', () async {
      await initLog();
      AppLog.i('sync', '同步完成');
      AppLog.e('sync', '同步失败：超时', error: Exception('boom'));
      await AppLog.flush();

      final String text = File(AppLog.filePath).readAsStringSync();
      expect(text, contains('同步完成'));
      expect(text, contains('同步失败：超时'));
      expect(text, contains('boom'));
    });

    test('重启后能读回 24 小时内的历史', () async {
      await initLog();
      AppLog.i('t', '第一次启动写的');
      await AppLog.flush();

      // 模拟重启：清状态但不删文件
      await AppLog.resetForTest();
      await initLog();

      final List<String> messages =
          AppLog.snapshot().map((LogEntry e) => e.message).toList();
      expect(messages, contains('第一次启动写的'));
    });

    test('超过 24 小时的记录在启动时被丢弃', () async {
      final Directory dir = Directory('${tempDir.path}/logs')
        ..createSync(recursive: true);
      final File file = File('${dir.path}/app.log');

      final LogEntry old = LogEntry(
        time: DateTime.now().subtract(const Duration(hours: 25)),
        level: LogLevel.info,
        tag: 't',
        message: '二十五小时前的旧日志',
      );
      final LogEntry fresh = LogEntry(
        time: DateTime.now().subtract(const Duration(hours: 1)),
        level: LogLevel.info,
        tag: 't',
        message: '一小时前的日志',
      );
      file.writeAsStringSync('${old.toLine()}\n${fresh.toLine()}\n');

      await initLog();

      final List<String> messages =
          AppLog.snapshot().map((LogEntry e) => e.message).toList();
      expect(messages, contains('一小时前的日志'));
      expect(messages, isNot(contains('二十五小时前的旧日志')));
      // 文件里也要清掉，不能只是内存里过滤
      expect(file.readAsStringSync(), isNot(contains('二十五小时前的旧日志')));
    });

    test('超过条数上限时丢最旧的', () async {
      await initLog();
      AppLog.maxEntries = 10;
      for (int i = 0; i < 40; i++) {
        AppLog.i('t', 'msg$i');
      }
      await AppLog.prune();

      expect(AppLog.snapshot().length, lessThanOrEqualTo(10));
      // 最新的那条一定还在
      expect(AppLog.snapshot().last.message, 'msg39');
      // 最旧的一定没了
      expect(
        AppLog.snapshot().any((LogEntry e) => e.message == 'msg0'),
        isFalse,
      );
    });

    test('清空会同时清掉内存与文件', () async {
      await initLog();
      AppLog.i('t', '待清空');
      await AppLog.flush();
      await AppLog.clear();

      expect(
        AppLog.snapshot().any((LogEntry e) => e.message == '待清空'),
        isFalse,
      );
      expect(File(AppLog.filePath).readAsStringSync(), isNot(contains('待清空')));
    });
  });

  group('导出', () {
    test('完整导出包含全部级别', () async {
      await initLog();
      AppLog.i('t', 'info-内容');
      AppLog.w('t', 'warn-内容');
      AppLog.e('t', 'error-内容');

      final String text = AppLog.buildExportText(header: '头部信息');

      expect(text, contains('头部信息'));
      expect(text, contains('info-内容'));
      expect(text, contains('warn-内容'));
      expect(text, contains('error-内容'));
    });

    test('仅问题模式只保留警告与错误', () async {
      await initLog();
      AppLog.i('t', 'info-内容');
      AppLog.w('t', 'warn-内容');
      AppLog.e('t', 'error-内容');

      final String text = AppLog.buildExportText(problemsOnly: true);

      expect(text.contains('info-内容'), isFalse);
      expect(text, contains('warn-内容'));
      expect(text, contains('error-内容'));
    });

    test('堆栈单独缩进展开，不挤在正文行里', () async {
      await initLog();
      AppLog.e(
        't',
        '崩了',
        error: Exception('boom'),
        stack: StackTrace.fromString('#0 a\n#1 b'),
      );

      final String text = AppLog.buildExportText();
      final List<String> lines = text.split('\n');
      final int at = lines.indexWhere((String l) => l.contains('崩了'));
      expect(at, greaterThanOrEqualTo(0));
      expect(lines[at + 1].trimLeft().startsWith('#0 a'), isTrue);
      expect(lines[at + 2].trimLeft().startsWith('#1 b'), isTrue);
    });

    test('导出文件写到指定目录且内容完整', () async {
      final File file = await AppLog.writeExportFile(
        '日志正文',
        dirOverride: tempDir.path,
      );

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), '日志正文');
      expect(file.path.contains('export'), isTrue);
    });
  });

  group('洪泛保护', () {
    test('一秒内超量的 debug 日志被丢弃', () async {
      await initLog();
      AppLog.floodLimitPerSecond = 5;

      for (int i = 0; i < 50; i++) {
        AppLog.d('t', 'flood$i');
      }

      final int written = AppLog.snapshot()
          .where((LogEntry e) => e.message.startsWith('flood'))
          .length;
      expect(written, lessThanOrEqualTo(5));
    });

    test('错误级不受洪泛限制', () async {
      await initLog();
      AppLog.floodLimitPerSecond = 1;

      for (int i = 0; i < 10; i++) {
        AppLog.e('t', 'err$i');
      }

      final int written = AppLog.snapshot()
          .where((LogEntry e) => e.message.startsWith('err'))
          .length;
      // 错误是排查的唯一线索，宁可撑大文件也不能丢。
      expect(written, 10);
    });
  });

  group('统计', () {
    test('countAtLeast 按级别累计', () async {
      await initLog();
      AppLog.d('t', 'd');
      AppLog.i('t', 'i');
      AppLog.w('t', 'w');
      AppLog.e('t', 'e');

      // 初始化时自己会写一条 info（"日志系统就绪"），所以 debug 级是 5 条。
      expect(AppLog.countAtLeast(LogLevel.debug), 5);
      // warn 级只看 w + e 两条；info 不算。
      expect(AppLog.countAtLeast(LogLevel.warn), 2);
      expect(AppLog.countAtLeast(LogLevel.error), 1);
    });

    test('时间范围随写入推进', () async {
      await initLog();
      final DateTime first = AppLog.firstTime!;
      final DateTime last = AppLog.lastTime!;

      AppLog.i('t', '稍后');

      expect(AppLog.firstTime, first);
      expect(AppLog.lastTime!.isBefore(last), isFalse);
    });
  });
}

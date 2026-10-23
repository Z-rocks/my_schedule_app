// 日志查看页的渲染测试。
//
// 这个页面是"用户把问题交出去"的唯一出口，崩了就等于整套日志白做，
// 所以至少要保证：能渲染、能筛选、能展开详情。
//
// ⚠️ 两条测试环境约束（踩过的坑）：
// 1. `testWidgets` 跑在**假时钟**里，真实文件 IO 的 Future 不会推进，
//    `await` 到磁盘的操作直接卡死 —— 必须包 `tester.runAsync()`；
// 2. `AppLog` 内部的 flush / 裁剪定时器如果在假时钟里创建，
//    测试结束会报 "A Timer is still pending" —— 同样靠 `runAsync` 规避。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_schedule_app/pages/settings/log_viewer_page.dart';
import 'package:my_schedule_app/services/app_log.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('logview_test_');
    await AppLog.resetForTest();
    await AppLog.init(dirOverride: tempDir.path, installHandlers: false);
  });

  tearDown(() async {
    await AppLog.resetForTest();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows 上句柄释放稍晚，删不掉交给系统清理。
    }
  });

  /// 在**真实**异步环境里写日志并落盘。
  Future<void> writeLogs(
    WidgetTester tester,
    void Function() body,
  ) async {
    await tester.runAsync(() async {
      body();
      await AppLog.flush();
    });
  }

  /// 卸载页面树并停掉日志内部的定时器。
  ///
  /// 两件事都要做：`pumpWidget(SizedBox)` 让页面 dispose（取消 1 秒刷新器），
  /// `resetForTest` 清掉 `AppLog` 自己的 flush / 裁剪定时器——
  /// 少任何一个，测试结束的 `_verifyInvariants` 都会报
  /// "A Timer is still pending even after the widget tree was disposed"。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(AppLog.resetForTest);
  }

  testWidgets('有日志时按模块与内容渲染', (WidgetTester tester) async {
    await writeLogs(tester, () {
      AppLog.i('sync', '同步完成');
      AppLog.e('sync', '同步失败：连接超时');
    });

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    expect(find.textContaining('同步完成'), findsOneWidget);
    expect(find.textContaining('同步失败：连接超时'), findsOneWidget);
    // 模块名作为前缀展示
    expect(find.textContaining('[sync]'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('顶部统计能反映错误条数', (WidgetTester tester) async {
    await writeLogs(tester, () {
      AppLog.i('t', '正常');
      AppLog.e('t', '错误一');
      AppLog.e('t', '错误二');
    });

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    expect(find.textContaining('错误 2 条'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('筛选「错误」后只剩错误级', (WidgetTester tester) async {
    await writeLogs(tester, () {
      AppLog.i('t', '一条普通信息');
      AppLog.e('t', '一条错误信息');
    });

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pump();

    expect(find.textContaining('一条错误信息'), findsOneWidget);
    expect(find.textContaining('一条普通信息'), findsNothing);
    await unmount(tester);
  });

  testWidgets('筛选后没有匹配项时显示空提示', (WidgetTester tester) async {
    await writeLogs(tester, () => AppLog.i('t', '只有一条普通信息'));

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pump();

    expect(find.text('没有符合条件的日志'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('点开条目能看到错误详情', (WidgetTester tester) async {
    await writeLogs(
      tester,
      () => AppLog.e('plugin', '插件执行失败', error: Exception('boom')),
    );

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    await tester.tap(find.textContaining('插件执行失败'));
    // 不能用 `pumpAndSettle`：详情里的 `SelectableText` 有一个持续闪烁的
    // 光标动画，帧永远不会"settle"，测试会卡到超时。固定推进两帧即可。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 详情弹层里的分块标题与内容
    expect(find.text('错误'), findsWidgets);
    expect(find.textContaining('boom'), findsWidgets);
    expect(find.text('复制这条日志'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('日志系统未初始化时给出明确提示', (WidgetTester tester) async {
    await tester.runAsync(() => AppLog.resetForTest());

    await tester.pumpWidget(const MaterialApp(home: LogViewerPage()));
    await tester.pump();

    expect(find.text('日志系统不可用'), findsOneWidget);
    await unmount(tester);
  });
}

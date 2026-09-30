// 同步结果模型：一次插件数据同步的结论（供 UI 展示与重试判定）
//
// 纯数据类，不依赖任何 Provider / 运行时——`CourseSyncService` 产出它，
// `PluginDetailPage` 消费它。放在 models/ 是因为它和 Course 一样属于
// "在层与层之间传递的数据形状"，不是服务。

/// 一次同步的最终结论。
enum SyncOutcome {
  /// 成功拿到数据（可能 0 门课，那是合法的"这学期没选课"）。
  success,

  /// 插件没有声明该入口函数（例如插件不支持课程同步）。
  unsupported,

  /// 凭证缺失或已失效 —— **重试无用**，必须引导用户去登录。
  authRequired,

  /// 插件返回了我们读不懂的数据（结构不符 / 不是 JSON）。
  /// **重试无用**，通常是插件与教务系统版本不匹配。
  protocolError,

  /// 网络类失败（超时 / 连不上 / 5xx）—— **可重试**。
  networkError,

  /// 插件在沙箱里执行超时（疑似死循环），沙箱已被 kill。**重试无用**。
  timeout,

  /// 插件不可用（未加载 / 已被销毁 / 沙箱创建失败）。**重试无用**。
  unavailable,

  /// 其它未归类的异常。**重试无用**（重试同一条路径只会再抛一次）。
  failed,
}

/// 一次同步的完整报告。
///
/// 不可变；由 [CourseSyncService.sync] 返回，**不抛异常**——
/// 所有失败都表达为带 [outcome] 与 [reason] 的对象。
class SyncReport {
  const SyncReport({
    required this.pluginId,
    required this.outcome,
    this.reason = '',
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.skipped = 0,
    this.userEdited = 0,
    this.sectionTimes = 0,
    this.allUnits,
    this.warnings = const <String>[],
    this.attempts = 1,
    this.httpErrors = const <String>[],
    this.duration = Duration.zero,
  });

  /// 产出本报告的插件 id。
  final String pluginId;

  /// 最终结论。
  final SyncOutcome outcome;

  /// 失败原因（成功时为空串），面向用户的中文文案。
  final String reason;

  /// 本次新写入的课程数。
  final int added;

  /// 本次覆盖更新的课程数（原始字段有变化）。
  final int updated;

  /// 本次**跳过落盘**的课程数（原始字段与库中完全一致，属增量策略的省写）。
  final int unchanged;

  /// 插件返回了、但解析失败被跳过的条目数。
  final int skipped;

  /// 本次被更新的课程里，**带有用户覆盖层**的数量。
  ///
  /// 这个数字是"用户的修改没有被同步冲掉"的可见证据（CONTEXT 3.3），
  /// 所以单独统计并展示，而不是埋在日志里。
  final int userEdited;

  /// 插件顺带回传的节次时间条数（0 表示没拿到，不影响课程）。
  final int sectionTimes;

  /// 插件顺带回传的总学分（`null` 表示没提供）。
  final double? allUnits;

  /// 插件给出的非致命警告（例如"节次时间获取失败"）。
  final List<String> warnings;

  /// 实际尝试次数（1 表示一次成功，>1 表示发生了重试）。
  final int attempts;

  /// 本次同步期间宿主记录到的 HTTP 失败短标识（Phase 4.3）。
  final List<String> httpErrors;

  /// 同步总耗时。
  final Duration duration;

  /// 是否成功。
  bool get isSuccess => outcome == SyncOutcome.success;

  /// 是否值得重试（只有网络类失败可重试）。
  bool get isRetryable => outcome == SyncOutcome.networkError;

  /// 是否确实写入了变化（用于决定提示文案是"已更新"还是"已是最新"）。
  bool get hasChanges => added > 0 || updated > 0;

  /// 插件返回的课程总数（成功解析的）。
  int get totalCourses => added + updated + unchanged;

  /// 失败报告（不含任何写入计数）。
  factory SyncReport.failure({
    required String pluginId,
    required SyncOutcome outcome,
    required String reason,
    int attempts = 1,
    List<String> httpErrors = const <String>[],
    List<String> warnings = const <String>[],
    Duration duration = Duration.zero,
  }) {
    return SyncReport(
      pluginId: pluginId,
      outcome: outcome,
      reason: reason,
      attempts: attempts,
      httpErrors: httpErrors,
      warnings: warnings,
      duration: duration,
    );
  }

  @override
  String toString() => 'SyncReport($pluginId, ${outcome.name}, '
      'added: $added, updated: $updated, unchanged: $unchanged, '
      'skipped: $skipped, attempts: $attempts)';
}

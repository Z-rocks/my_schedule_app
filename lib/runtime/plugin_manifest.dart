// Phase 3.2b.1：插件 manifest 模型（插件文件格式里的**可选**元数据部分）。
//
// 插件文件格式（最小版）：
//   <name>.js               必需。必须定义全局对象 `__plugin`，其属性中的函数即入口函数。
//   <name>.manifest.json    可选。缺省时元数据从 `__plugin` 的 id/name/version/capabilities 推导。
//
// manifest 的 JSON 键名一律小驼峰（CONTEXT 4.2.1 序列化字段冻结），
// 与 lib/models/plugin_meta.dart 的命名保持一致，便于将来映射到 PluginMeta。
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// manifest 文件的扩展名约定（与 `.js` 同目录同主名）。
const String kPluginManifestSuffix = '.manifest.json';

/// 插件 manifest：描述一个插件的最小元数据。
///
/// 不包含 UI 信息（导航栏模块等）——那是 `PluginMeta` / `ModuleInfo` 的职责，
/// 本阶段只做"文件 → 可执行 JS"的骨架，不做模块注册。
@immutable
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.author = '',
    this.description = '',
    this.school = '',
    this.capabilities = const <String>[],
    this.loginUrl = '',
    this.checkUrl = '',
    this.postLoginUrl = '',
  });

  /// 插件唯一 ID，如 `"demo-course-plugin"`。**必须非空**（由加载器校验）。
  final String id;

  /// 显示名。
  final String name;

  /// 版本号。
  final String version;

  /// 作者。
  final String author;

  /// 说明。
  final String description;

  /// 适用学校。
  final String school;

  /// 数据能力 ID 列表，如 `['exam', 'homework']`。
  final List<String> capabilities;

  /// 登录页 URL（Phase 4.1 新增）。空串表示**未声明**，登录按钮会提示用户。
  ///
  /// 由插件自己声明（各校教务地址不同，内核不得硬编码任何学校 URL，见 CONTEXT 3.1）。
  /// 之所以放在 `PluginManifest` 而不是 `PluginMeta`：`PluginManifest` 是**运行时**从
  /// 插件 JS / `.manifest.json` 解析出来的，**不落盘**，所以加字段**无需迁移**
  /// （`PluginMeta` 存在 Hive 里，受 CONTEXT 4.2.1 约束）。
  final String loginUrl;

  /// 登录成功判定用的 **URL 前缀**（Phase 4.1 新增）。
  ///
  /// 登录页里当 WebView 的当前 URL 以它为前缀时判定成功；空串表示未声明，
  /// 此时登录页退化为"拿到任意 Cookie 即视为成功"的兜底策略。
  final String checkUrl;

  /// 登录成功后**自动导航**到的地址（可选）。
  ///
  /// 解决的问题：很多教务系统登录后停在首页，而 [checkUrl] 指向的是更深一层的
  /// 业务页（如"选课结果"）。只靠 [checkUrl] 判定成功的话，用户必须自己点菜单
  /// 走过去，登录页才会返回——明明已经登录了，却卡在那儿。
  ///
  /// 声明本字段后，登录页一旦发现**已经离开登录表单页**，就自动导航到这里，
  /// 再由 [checkUrl] 判定成功。未声明（空串）时行为与以前完全一致（向后兼容）。
  ///
  /// 为什么不让内核自己猜"登录成功"：各校登录流程差异极大（有的走 CAS 单点、
  /// 有的表单 POST 后原地刷新），猜错的代价是页面乱跳。把"登录后该去哪"交给
  /// 插件声明，内核只做机械的导航，符合 CONTEXT 3.1（内核不知道任何学校 URL）。
  final String postLoginUrl;

  /// id 是否有效（非空且非纯空白）。
  bool get hasValidId => id.trim().isNotEmpty;

  /// 是否声明了能力。
  bool get hasCapabilities => capabilities.isNotEmpty;

  /// 从 JSON 构造。缺失字段用兜底值，类型不符则忽略该项，**任何输入都不抛异常**。
  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: _asString(json['id']),
      name: _asString(json['name']),
      version: _asString(json['version'], '0.0.0'),
      author: _asString(json['author']),
      description: _asString(json['description']),
      school: _asString(json['school']),
      capabilities: _asStringList(json['capabilities']),
      loginUrl: _asString(json['loginUrl']),
      checkUrl: _asString(json['checkUrl']),
      postLoginUrl: _asString(json['postLoginUrl']),
    );
  }

  /// 序列化为 JSON。键名与 [PluginManifest.fromJson] 读取的键一一对应。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'school': school,
      'capabilities': capabilities,
      'loginUrl': loginUrl,
      'checkUrl': checkUrl,
      'postLoginUrl': postLoginUrl,
    };
  }

  /// 从存储/文件里的字符串解析；坏 JSON、非对象、**缺 id 或 id 为空白**一律返回 `null`。
  ///
  /// 供加载器判定"manifest 文件不可用"，避免用兜底值伪造出一个 manifest。
  static PluginManifest? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final PluginManifest manifest = PluginManifest.fromJson(decoded);
      return manifest.hasValidId ? manifest : null;
    } catch (e) {
      debugPrint('[PluginManifest] 解析失败：$e');
      return null;
    }
  }

  @override
  String toString() => 'PluginManifest($id, $name, v$version)';

  /// 安全取字符串：非 String 或 null 时用兜底值。
  static String _asString(Object? value, [String fallback = '']) {
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return fallback;
  }

  /// 安全取字符串列表：非 List 返回空；忽略非字符串与空白项。
  static List<String> _asStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
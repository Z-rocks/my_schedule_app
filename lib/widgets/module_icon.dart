// 模块图标解析：把 ModuleInfo.iconName（字符串）转成 IconData
import 'package:flutter/material.dart';

/// Material 图标名 → [IconData] 映射。
///
/// 模型层的 `ModuleInfo.iconName` 是字符串（模型不依赖 Flutter），
/// 由本表在 UI 层转成 [IconData]。内置模块的图标名见
/// `ModuleProvider._initialModules`；插件可在 `.js` 里用同样的名字声明图标。
///
/// 由 `home_page.dart` 抽出（PROGRESS 阻塞表已记录该计划），
/// 供主页导航栏与设置页的导航栏配置共用，避免出现第二份图标表。
const Map<String, IconData> kModuleIconByName = <String, IconData>{
  // —— 内置模块 ——
  'calendar_month': Icons.calendar_month,
  'book_outlined': Icons.book_outlined,
  'assignment_outlined': Icons.assignment_outlined,
  'edit_note': Icons.edit_note,
  'notifications_outlined': Icons.notifications_outlined,
  'settings_outlined': Icons.settings_outlined,
  // —— 预留：插件常用图标 ——
  'grade_outlined': Icons.grade_outlined,
  'school_outlined': Icons.school_outlined,
  'task_outlined': Icons.task_outlined,
  'message_outlined': Icons.message_outlined,
};

/// 把图标名转成 [IconData]。
///
/// 查不到（含空字符串、插件未声明 `iconName` 的情况）时兜底为
/// [Icons.extension]——"扩展/插件"的通用图标。
IconData iconFromName(String name) => kModuleIconByName[name] ?? Icons.extension;
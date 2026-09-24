// 示例插件（Phase 3.5 UI 验证用）
//
// ⚠️ 这是**临时**文件：只为让插件管理页在没有任何真实插件时也能看到
// "已安装 → 已启用 → 沙箱就绪"的完整效果。Phase 4 做出真实的教务插件后，
// 本文件与 PluginProvider.installExamplePluginForDemo() 一并删除。
//
// 文件格式见 docs/API.md 的「插件文件格式」一节：
// 必须定义全局对象 __plugin，其属性中的函数即入口函数。
var __plugin = {
  id: 'example-plugin',
  name: '示例插件',
  version: '1.0.0',
  author: 'MySchedule',
  description: '内置示例，用于验证插件管理页与运行时链路',
  capabilities: ['exam'],
  fetchExams: function (args) {
    // 真实插件这里会请求教务系统；示例只返回空列表。
    return { exams: [] };
  }
};

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
  },

  // Phase 3.6：验证宿主注入的 ctx（日志 / 私有存储 / 凭证）。
  // 注意：插件函数可能被宿主**执行多次**（ctx.http 需要重放），
  // 所以这里只做幂等的读写，不做累加类副作用。
  testCtx: function (args) {
    ctx.log.info('测试 ctx.log：插件 ' + __plugin.id + ' 开始');
    ctx.storage.set('counter', '42');
    var v = ctx.storage.get('counter');
    var missing = ctx.storage.get('never-set');
    ctx.notify.schedule('测试提醒', '来自示例插件', '2026-09-25T08:00:00Z');
    return {
      counter: v,
      missingIsEmpty: missing === '',
      cookie: ctx.cookie,
      cookieIsString: typeof ctx.cookie === 'string'
    };
  },

  // Phase 3.6：验证 ctx.http（真发请求由宿主完成，插件侧看起来是同步的）。
  // 默认打的是本机不存在的地址，因此会走到 ok=false；真机验证时会传入真实 URL。
  testHttp: function (args) {
    var url = (args && args.url) ? args.url : 'http://127.0.0.1:1/nope';
    var r = ctx.http.get(url, { 'X-From': 'example-plugin' });
    return { ok: r.ok, status: r.status, error: r.error, bodyLen: r.body ? r.body.length : 0 };
  }
};

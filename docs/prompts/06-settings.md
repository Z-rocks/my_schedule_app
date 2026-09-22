# 任务：设置页（Phase 1.6）

## 目标
生成设置主页、模块配置页、以及插件管理、创意工坊、课表设置的占位页。

## 要生成的文件

### 1. `lib/pages/settings/settings_page.dart` — SettingsPage
- AppBar 标题"设置"
- Body 用 `ListView` 分组，每组一个 `Card`，组内用 `ListTile`

**分组结构**：

**账号**
- 登录管理 `>` → `SnackBar('登录管理（待实现）')`

**扩展**
- 插件管理 `>` → `PluginManagePage`
- 创意工坊 `>` → `WorkshopPage`

**外观**
- 深色模式 → 弹出 `SnackBar('深色模式（待实现）')`
- 当前主题 → 显示"默认蓝"，点击 `SnackBar('主题切换（待实现）')`

**布局**
- 导航栏配置 `>` → `ModuleConfigPage`
- 课表设置 `>` → `TimetableSettingsPage`

**数据**
- 导出数据 → `SnackBar('导出（待实现）')`
- 导入数据 → `SnackBar('导入（待实现）')`
- 清理缓存 → 弹确认框，确认后 `SnackBar('已清理（待实现）')`

**关于**
- 版本号 → 显示 `v0.1.0`，不可点击
- 反馈 → `SnackBar('反馈（待实现）')`

### 2. `lib/pages/settings/module_config_page.dart` — ModuleConfigPage
- AppBar 标题"导航栏配置"
- 顶部提示："最多显示 5 个模块，课表和设置不可关闭"
- 用 `ListView` 列出所有模块（从 `ModuleProvider.allModules`）
- 每行 `ListTile`：
    - leading: 模块图标
    - title: 模块名称
    - trailing:
        - 如果 `required == true`：显示"必需"文字，`Switch` 禁用且打开
        - 如果 `available == false`：显示"未激活"文字，`Switch` 禁用且关闭
        - 否则：`Switch(value: enabled, onChanged: toggle)`
- 用户切换时调用 `ModuleProvider.toggle(type, value)`
- 如果切换后 `visibleModules.length > 5`，弹 `SnackBar('最多显示 5 个模块')` 并回滚
    - 或者：在 toggle 之前检查

### 3. `lib/pages/settings/plugin_manage_page.dart` — PluginManagePage
- AppBar 标题"插件管理"，右侧 `+` 按钮
    - `+` 点击：`SnackBar('安装插件（待实现）')`
- Body：空态
    - 图标 `Icons.extension`
    - 主文案"还没有安装插件"
    - 副文案"插件可以从创意工坊下载，或从本地文件导入"
    - 按钮"去创意工坊" → `Navigator.push(WorkshopPage)`

### 4. `lib/pages/settings/workshop_page.dart` — WorkshopPage
- `DefaultTabController(length: 2)`
- AppBar 标题"创意工坊"，底部 `TabBar`（两个 Tab：皮肤 / 插件）
- Body 用 `TabBarView`：
    - Tab 1（皮肤）：空态，`Icons.palette_outlined` + "暂无皮肤" + "敬请期待"
    - Tab 2（插件）：空态，`Icons.extension_outlined` + "暂无插件" + "敬请期待"

### 5. `lib/pages/settings/timetable_settings_page.dart` — TimetableSettingsPage
- AppBar 标题"课表设置"
- Body 用 `ListView`：
    - `SwitchListTile` "显示周末"，值默认 true，改动后 `SnackBar('（待实现）')`
    - `SwitchListTile` "显示节次时间"，值默认 true
    - `Slider` "每节高度"（范围 40-100，默认 60）
- 全部为占位，不保存

## 约束
- 使用 Material 3
- 颜色从 `AppThemeExtension` 读
- 跳转用 `Navigator.push(MaterialPageRoute(...))`
- 不引入 go_router

## 输出
- 每个文件单独代码块
- 代码块前标注文件路径
- 完整输出
- 写完后额外输出 API 接口清单
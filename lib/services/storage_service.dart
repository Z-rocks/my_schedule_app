// 存储服务：统一管理 Hive 的初始化与 Box 访问
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Box 名称。落盘后即为契约（见 CONTEXT.md 4.2.1），不得随意改动。
const String kCoursesBoxName = 'courses';
const String kExamsBoxName = 'exams';
const String kHomeworksBoxName = 'homeworks';
const String kMessagesBoxName = 'messages';
const String kOverridesBoxName = 'overrides';
const String kSettingsBoxName = 'settings';
const String kPluginsBoxName = 'plugins';
const String kSkinsBoxName = 'skins';

/// 插件私有 KV 数据（Phase 3.6 新增）。
///
/// key 格式为 `"<pluginId>:<userKey>"`——**插件之间靠前缀隔离**，
/// 见 `PluginContext`。插件 id 只允许字母数字下划线横线（见
/// `PluginStorageService.isValidPluginId`），所以 `:` 作分隔符不会歧义。
const String kPluginDataBoxName = 'plugin_data';

/// `settings` Box 中的键名。与 Box 名一样属于契约（CONTEXT.md 4.2.1）。
///
/// 集中放在这里，避免各 Provider 各自硬编码字符串导致拼写漂移。

/// 导航栏模块的启用状态，值为 JSON 对象 `{"<capabilityId>": bool}`。
const String kModuleEnabledStateKey = 'module_enabled_state';

/// 明暗模式偏好，值为 `"light"` / `"dark"` / `"system"`。
///
/// **Phase 6** 起多出 `"system"`（跟随系统）；旧数据里的 `light` / `dark`
/// 语义不变，因此无需迁移。
const String kThemeBrightnessKey = 'theme_brightness';

/// 当前皮肤 ID（Phase 6），值为 `SkinPack.id`。
///
/// 为空 / 缺键表示使用内置默认主题。
/// 与 [kThemeBrightnessKey] **分开存**：明暗偏好与"用哪套皮肤"是两个独立的
/// 用户选择，合在一个键里会让"只换明暗"变成一次读改写。
const String kThemeSkinIdKey = 'theme_skin_id';

/// 学期配置，值为 `SemesterConfig` 的 JSON 字符串。
///
/// 目前只支持单学期，因此是一个"单值键"而不是列表。
/// 由 `SemesterConfigPage`（学期配置页）编辑、`SemesterProvider` 读写。
/// 解析请走 `SemesterConfig.tryDecode`——它会拒绝缺 `startDate` / `totalWeeks`
/// 的数据，避免用兜底值伪造出一个学期。
const String kSemesterConfigKey = 'semester_config';

/// 已归档的学期列表，值为 `SemesterArchiveEntry` 的 JSON **数组**字符串。
///
/// 当前学期仍单独存在 [kSemesterConfigKey]（保持单学期时代的读取路径不变），
/// 这个键只放"已经结束 / 被换下去"的学期。拆成两个键而不是一个列表，
/// 是为了让"读当前学期"这条最热的路径不必解析整个列表。
const String kSemesterArchiveKey = 'semester_archive';

/// 是否允许在课表页左右滑动切换周次，值为 JSON `true` / `false`。
///
/// 属于 **UI 偏好**（只影响交互，不影响数据），由 `SettingsProvider` 管理。
const String kGestureSwitchWeekKey = 'gesture_switch_week';

/// 上课提醒设置，值为 `ClassReminderSettings` 的 JSON 字符串。
///
/// 与作业提醒的设置**分开存**（作业的在 `homework_reminder_*` 系列键里）：
/// 两者的开关语义不同，一个用户很可能只想要上课提醒。
const String kClassReminderSettingsKey = 'class_reminder_settings';

/// Hive 存储服务。
///
/// 职责：初始化 Hive、打开全部 Box、对外提供只读的 Box 引用。
/// **不**负责具体的序列化与业务逻辑——那是 `OverrideEngine` 和各 Provider 的事。
///
/// 设计约定：
/// - 所有 Box 统一为 `Box<String>`，值存 JSON 字符串。
///   不使用 `TypeAdapter` / `build_runner`（CONTEXT.md 禁止代码生成），
///   因此没有注册任何 adapter，模型的手写 `toJson`/`fromJson` 是唯一序列化途径。
/// - Box 名用小写下划线，与业务含义一一对应（见 [kCoursesBoxName] 等常量）。
/// - 初始化失败不抛异常，只 `debugPrint`；访问未打开的 Box 时才抛 [StateError]，
///   由调用方的 try-catch 兜住。
class StorageService {
  /// 纯静态工具类，禁止实例化。
  StorageService._();

  static Box<String>? _coursesBox;
  static Box<String>? _examsBox;
  static Box<String>? _homeworksBox;
  static Box<String>? _messagesBox;
  static Box<String>? _overridesBox;
  static Box<String>? _settingsBox;
  static Box<String>? _pluginsBox;
  static Box<String>? _skinsBox;
  static Box<String>? _pluginDataBox;

  static bool _initialized = false;

  /// 是否已完成初始化（不代表每个 Box 都成功打开）。
  static bool get isInitialized => _initialized;

  /// 初始化 Hive 并打开全部 Box。
  ///
  /// 生产环境调用 `await StorageService.init()`，内部走 `Hive.initFlutter()`
  /// （依赖 `path_provider` 定位应用目录）。
  /// 测试环境传 [path] 直接指定目录，避免依赖平台插件。
  ///
  /// 重复调用是安全的（已初始化则直接返回）。
  static Future<void> init({String? path}) async {
    if (_initialized) return;

    try {
      if (path == null) {
        await Hive.initFlutter();
      } else {
        Hive.init(path);
      }
    } catch (error, stackTrace) {
      debugPrint('StorageService.init: Hive 初始化失败: $error');
      debugPrint('$stackTrace');
      return;
    }

    // 依次打开，顺序与字段声明一致，便于排查。
    _coursesBox = await _openBox(kCoursesBoxName);
    _examsBox = await _openBox(kExamsBoxName);
    _homeworksBox = await _openBox(kHomeworksBoxName);
    _messagesBox = await _openBox(kMessagesBoxName);
    _overridesBox = await _openBox(kOverridesBoxName);
    _settingsBox = await _openBox(kSettingsBoxName);
    _pluginsBox = await _openBox(kPluginsBoxName);
    _skinsBox = await _openBox(kSkinsBoxName);
    _pluginDataBox = await _openBox(kPluginDataBoxName);

    _initialized = true;
  }

  /// 关闭全部 Box 并清空缓存（测试收尾 / App 退出时用）。
  static Future<void> close() async {
    try {
      await Hive.close();
    } catch (error, stackTrace) {
      debugPrint('StorageService.close: 关闭 Hive 失败: $error');
      debugPrint('$stackTrace');
    }
    _coursesBox = null;
    _examsBox = null;
    _homeworksBox = null;
    _messagesBox = null;
    _overridesBox = null;
    _settingsBox = null;
    _pluginsBox = null;
    _skinsBox = null;
    _pluginDataBox = null;
    _initialized = false;
  }

  /// 课程原始数据（key = 课程 ID，value = Course JSON）。
  static Box<String> get coursesBox => _require(_coursesBox, kCoursesBoxName);

  /// 考试数据（key = 考试 ID）。
  static Box<String> get examsBox => _require(_examsBox, kExamsBoxName);

  /// 作业数据（key = 作业 ID）。
  static Box<String> get homeworksBox =>
      _require(_homeworksBox, kHomeworksBoxName);

  /// 消息数据（key = 消息 ID）。
  static Box<String> get messagesBox => _require(_messagesBox, kMessagesBoxName);

  /// 用户覆盖层（key = 课程 ID，见 CONTEXT.md 3.5）。
  static Box<String> get overridesBox =>
      _require(_overridesBox, kOverridesBoxName);

  /// 模块配置 / 用户偏好 / 当前皮肤 ID（见 CONTEXT.md 3.5）。
  static Box<String> get settingsBox => _require(_settingsBox, kSettingsBoxName);

  /// 已安装插件元数据（key = 插件 ID）。
  static Box<String> get pluginsBox => _require(_pluginsBox, kPluginsBoxName);

  /// 已安装皮肤包（key = 皮肤 ID）。
  static Box<String> get skinsBox => _require(_skinsBox, kSkinsBoxName);

  /// 插件私有 KV（key = `"<pluginId>:<userKey>"`，见 [kPluginDataBoxName]）。
  static Box<String> get pluginDataBox =>
      _require(_pluginDataBox, kPluginDataBoxName);

  static Future<Box<String>?> _openBox(String name) async {
    try {
      return await Hive.openBox<String>(name);
    } catch (error, stackTrace) {
      debugPrint('StorageService: 打开 Box "$name" 失败: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// 取已打开的 Box；未初始化或该 Box 打开失败时抛 [StateError]。
  static Box<String> _require(Box<String>? box, String name) {
    if (box == null) {
      throw StateError(
        'Hive Box "$name" 尚未打开，请先 await StorageService.init()',
      );
    }
    return box;
  }
}
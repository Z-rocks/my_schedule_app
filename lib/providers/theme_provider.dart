// 主题状态：包装 ThemeEngine，向 UI 暴露当前主题与明暗模式偏好
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../models/skin_pack.dart';
import '../services/app_log.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/default_skins.dart';
import '../theme/theme_engine.dart';

/// assets 里的皮肤目录（目录级声明，见 `pubspec.yaml`）。
///
/// 新增皮肤文件**不用改代码、不用改 pubspec**，见 [ThemeProvider.loadAssetSkins]。
const String kSkinAssetDir = 'assets/skins/';

/// 用户的明暗模式偏好（**Phase 6** 新增"跟随系统"）。
enum ThemeBrightnessMode {
  /// 始终亮色。
  light,

  /// 始终暗色。
  dark,

  /// 跟随系统设置。**默认值**——这是绝大多数用户的期望行为。
  system;

  /// 存储用的字符串（与枚举名一致，便于 `decode` 往返）。
  String get storageValue => name;

  /// 面向用户的中文标签。
  String get label {
    switch (this) {
      case ThemeBrightnessMode.light:
        return '亮色';
      case ThemeBrightnessMode.dark:
        return '暗色';
      case ThemeBrightnessMode.system:
        return '跟随系统';
    }
  }

  /// 解析存储值；无法识别返回 `null`（调用方保持默认）。
  static ThemeBrightnessMode? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw.trim().toLowerCase()) {
      case 'light':
        return ThemeBrightnessMode.light;
      case 'dark':
        return ThemeBrightnessMode.dark;
      case 'system':
        return ThemeBrightnessMode.system;
      default:
        return null;
    }
  }
}

/// 主题状态。
///
/// 内部持有 [ThemeEngine]（Phase 1.2 已完成"皮肤 → AppTheme"的转换与合并），
/// 本类只负责把它包装成 UI 可用的 Provider：对外暴露 [currentTheme] /
/// [brightness]，并在状态变化后 `notifyListeners`。
///
/// **Phase 6**：明暗偏好从"亮/暗两态"扩成"亮/暗/跟随系统"三态（[mode]），
/// 并把"当前皮肤"的 ID 一并持久化（`settings` Box）。
/// 本类不引用其他 Provider。
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({ThemeEngine? engine}) : _engine = engine ?? ThemeEngine();

  final ThemeEngine _engine;

  /// 用户的明暗模式偏好；默认"跟随系统"。
  ThemeBrightnessMode _mode = ThemeBrightnessMode.system;

  /// 上次解析出的系统亮度（`system` 模式下用）。
  ///
  /// 由 `MyApp` 在 `didChangePlatformBrightness` 时通过 [syncSystemBrightness] 告知。
  Brightness _systemBrightness = Brightness.light;

  /// 当前生效皮肤的 ID（用于持久化与"当前主题"展示）。
  String _skinId = '';

  bool _disposed = false;

  /// 当前生效的主题令牌集合（供 `AppThemeExtension` 使用）。
  ///
  /// 注意这会先应用明暗偏好，所以 UI 拿到的永远是与当前模式一致的配色。
  AppTheme get currentTheme => _engine.current;

  /// 当前皮肤 ID；空字符串表示使用内置默认主题。
  String get currentSkinId => _engine.currentSkinId;

  /// 用户的明暗模式偏好。
  ThemeBrightnessMode get mode => _mode;

  /// 上次解析出的系统亮度。
  Brightness get systemBrightness => _systemBrightness;

  /// **最终生效**的明暗模式（把 `system` 解析成实际的亮 / 暗）。
  ///
  /// 这是 UI 与引擎真正使用的值；[mode] 只是用户的选择。
  Brightness get brightness {
    switch (_mode) {
      case ThemeBrightnessMode.light:
        return Brightness.light;
      case ThemeBrightnessMode.dark:
        return Brightness.dark;
      case ThemeBrightnessMode.system:
        return _systemBrightness;
    }
  }

  /// 换算成 `MaterialApp.themeMode`（`app.dart` 用它同时驱动 Material 与扩展）。
  ThemeMode get themeMode {
    switch (_mode) {
      case ThemeBrightnessMode.light:
        return ThemeMode.light;
      case ThemeBrightnessMode.dark:
        return ThemeMode.dark;
      case ThemeBrightnessMode.system:
        return ThemeMode.system;
    }
  }

  /// 按当前偏好取主题。
  ///
  /// Phase 1 的 `withBrightness` 曾返回 `this`；**Phase 6 起是真实推导**，
  /// 所以这里与 [currentTheme] 可能不同（引擎内已按模式合成，二者通常一致）。
  AppTheme get themedForBrightness =>
      _engine.current.withBrightness(brightness);

  /// 应用一份皮肤。
  ///
  /// 调用 [ThemeEngine.loadSkin] 解析并合并皮肤，然后通知 UI 重建。
  /// 皮肤解析失败时引擎会保持原主题（内部已 try-catch），本方法不会抛出。
  ///
  /// Phase 6：同时把皮肤 ID 落盘，重启后能恢复。
  /// 皮肤的 `mode == 'dark'` / `'light'` 会覆盖用户的明暗偏好（见
  /// [_forcedBrightnessOf]）——所以这里用 [_effectiveBrightnessFor] 而不是
  /// 裸 [brightness]，否则"暗夜紫"在亮色偏好下会被推导成亮色。
  Future<void> applySkin(SkinPack skin) async {
    final Brightness target = _effectiveBrightnessFor(skin);
    await _engine.loadSkin(skin, brightness: target);
    // 记住这次实际用的亮度：切走再切回同一个暗色皮肤时行为一致。
    if (target != brightness) {
      _mode = target == Brightness.dark
          ? ThemeBrightnessMode.dark
          : ThemeBrightnessMode.light;
    }
    _skinId = skin.id;
    AppLog.action('theme_skin', <String, Object?>{'skin': skin.id});
    _notify();
    unawaited(saveToStorage());
  }

  /// 恢复内置默认主题。
  ///
  /// 用 [_resolvedBrightness]（而不是裸 [brightness]）重建默认主题：
  /// 用户偏好是"暗色"时，"恢复默认"应该恢复到**暗色的默认主题**，
  /// 而不是把他踢回亮色。
  Future<void> resetTheme() async {
    await _engine.reset();
    // 引擎的 reset 会把当前主题设为"默认主题 + 自身记录的亮度"，
    // 这里再按解析后的亮度对齐一次，避免两者不一致。
    _engine.setBrightness(_resolvedBrightness);
    _skinId = '';
    _notify();
    unawaited(saveToStorage());
  }

  /// 设置明暗模式偏好。
  ///
  /// 变更后自动落盘（见 [saveToStorage]），杀进程重开仍保留。
  ///
  /// ⚠️ 当前皮肤若是 `mode: 'dark'` / `'light'`（自带强制亮度），
  /// 偏好会**记下来但暂时不生效**——引擎仍按皮肤声明合成。
  /// 这是有意的：皮肤作者的意图优先于全局偏好。
  void setMode(ThemeBrightnessMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    AppLog.action('theme_mode', <String, Object?>{'mode': mode.name});
    // 让引擎按新模式重新合成（有皮肤时用同一份皮肤重算）。
    _engine.setBrightness(_resolvedBrightness);
    _notify();
    // 不 await：同步接口，落盘失败只记日志。
    unawaited(saveToStorage());
  }

  /// 保留旧接口：直接设亮 / 暗（等价于 [setMode]，供旧调用方与测试使用）。
  void setBrightness(Brightness b) => setMode(
        b == Brightness.dark
            ? ThemeBrightnessMode.dark
            : ThemeBrightnessMode.light,
      );

  /// 系统亮度变化时由 `MyApp` 调用（只影响 `system` 模式）。
  ///
  /// 返回是否**真的**改变了生效亮度——调用方据此决定要不要重建。
  bool syncSystemBrightness(Brightness value) {
    if (_systemBrightness == value) return false;
    final Brightness before = _resolvedBrightness;
    _systemBrightness = value;
    if (_resolvedBrightness == before) return false; // 非 system 模式不受影响
    _engine.setBrightness(_resolvedBrightness);
    _notify();
    return true;
  }

  /// 最终交给引擎的亮度：**皮肤强制 > 用户偏好（可能来自系统）**。
  Brightness get _resolvedBrightness {
    final SkinPack? skin = _engine.skin;
    if (skin != null) {
      final Brightness? forced = _forcedBrightnessOf(skin);
      if (forced != null) return forced;
    }
    return brightness;
  }

  /// 预览皮肤效果，**不改变**当前状态、不通知 UI。
  AppTheme previewSkin(SkinPack skin) =>
      _engine.preview(skin, brightness: brightness);

  // ————————————————— 持久化（settings Box） —————————————————

  /// 从 `settings` Box 恢复明暗偏好**与当前皮肤 ID**。
  ///
  /// 兼容旧值（Phase 2 只存过 `light` / `dark`）：
  /// 缺键 / 空串 / 无法识别 → 保持默认（`system`）。
  ///
  /// 皮肤恢复的边界情况：
  /// - 存了 ID 但皮肤已不在（用户卸了 / 创意工坊下线了）→ 保持内置默认主题；
  /// - 恢复皮肤需要 [SkinSource] 能找到它，所以**先把 ID 读出来**，
  ///   由调用方（`main.dart`）在拿到皮肤列表后调用 [restoreSkin]。
  ///   本方法只负责把 ID 记下来。
  Future<void> loadFromStorage() async {
    try {
      final String? raw = StorageService.settingsBox.get(kThemeBrightnessKey);
      final String? rawSkin = StorageService.settingsBox.get(kThemeSkinIdKey);

      final ThemeBrightnessMode? stored = ThemeBrightnessMode.decode(raw);
      if (stored != null && stored != _mode) {
        _mode = stored;
        _engine.setBrightness(brightness);
      }
      _skinId = rawSkin?.trim() ?? '';
      _notify();
    } catch (error, stackTrace) {
      debugPrint('ThemeProvider.loadFromStorage 失败（保持默认偏好）: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 待恢复的皮肤 ID（`loadFromStorage` 读出，`restoreStoredSkin` 消费）。
  String get pendingSkinId => _skinId;

  /// 启动时恢复上次使用的皮肤（**Phase 6**）。
  ///
  /// 皮肤来源分两类，都走同一套 `SkinPack` 解析：
  /// 1. **assets 里的 `.skin.json`**（`assets/skins/`）——随 App 打包，支持用户
  ///    通过重新打包的方式加入自己的皮肤；
  /// 2. **代码内置皮肤**（`default_skins.dart`）——保证开箱有内容。
  ///
  /// 找不到对应 ID 时**静默保持默认主题**并清掉记录——
  /// 皮肤被删掉后不该让 App 一直显示一个不存在的主题名。
  ///
  /// 返回是否成功恢复。任何解析/IO 异常都被吞掉（皮肤问题不该让 App 起不来）。
  Future<bool> restoreStoredSkin() async {
    if (_skinId.isEmpty) return false;
    try {
      final List<SkinPack> available = <SkinPack>[
        ...await loadAssetSkins(),
        ...builtinSkins(),
      ];
      for (final SkinPack skin in available) {
        if (skin.id == _skinId) {
          await _engine.loadSkin(skin, brightness: _effectiveBrightnessFor(skin));
          _notify();
          return true;
        }
      }
      debugPrint('ThemeProvider: 皮肤 "$_skinId" 已不存在，改用默认主题');
    } catch (error, stackTrace) {
      debugPrint('ThemeProvider.restoreStoredSkin 失败（改用默认主题）: $error');
      debugPrint('$stackTrace');
    }
    _skinId = '';
    // 必须 await：调用方（main）紧接着就要用默认主题起 UI，
    // 而且测试也要能在返回后立刻断言存储已被清理。
    await saveToStorage();
    return false;
  }

  /// 读出 `assets/skins/` 下的全部皮肤（**Phase 6**）。
  ///
  /// 用 `AssetManifest` 列目录而不是硬编码文件名：`pubspec.yaml` 里
  /// `assets/skins/` 是**目录声明**，以后新增皮肤文件**不用改代码、不用改 pubspec**
  /// （这条约定沿用 Phase 4.2 给 `assets/plugins/` 定的做法）。
  ///
  /// 单个文件坏掉只跳过它，不影响其余皮肤，也不抛异常。
  static Future<List<SkinPack>> loadAssetSkins() async {
    final List<SkinPack> result = <SkinPack>[];
    try {
      final AssetManifest manifest =
          await AssetManifest.loadFromAssetBundle(rootBundle);
      final Iterable<String> keys = manifest
          .listAssets()
          .where((String k) => k.startsWith(kSkinAssetDir) && k.endsWith('.json'));
      for (final String key in keys) {
        try {
          final String raw = await rootBundle.loadString(key);
          final Object? decoded = jsonDecode(raw);
          if (decoded is! Map) {
            debugPrint('ThemeProvider: 皮肤文件 $key 不是 JSON 对象，已跳过');
            continue;
          }
          final Map<String, dynamic> map = <String, dynamic>{};
          decoded.forEach((dynamic k, dynamic v) {
            if (k != null) map['$k'] = v;
          });
          final SkinPack skin = SkinPack.fromJson(map);
          if (skin.id.trim().isEmpty) {
            debugPrint('ThemeProvider: 皮肤文件 $key 缺少 id，已跳过');
            continue;
          }
          result.add(skin);
        } catch (e) {
          debugPrint('ThemeProvider: 解析皮肤文件 $key 失败，已跳过：$e');
        }
      }
    } catch (e) {
      // 没有 assets/skins 目录、或平台不支持 AssetManifest（测试环境）时
      // 会走到这里——退化成"只有内置皮肤"，这是完全可用的状态。
      debugPrint('ThemeProvider: 读取 assets 皮肤目录失败（按无皮肤处理）：$e');
    }
    return result;
  }

  /// 把明暗偏好与当前皮肤 ID 写入 `settings` Box。
  ///
  /// 明暗值取枚举名（`light` / `dark` / `system`）；
  /// 皮肤 ID 为空串时**删掉该键**，不留无意义的空记录。
  ///
  /// ⚠️ 皮肤 ID 取 **[_skinId] 字段**而不是 `_engine.currentSkinId`：
  /// 两者含义不同——字段是"用户选了哪个皮肤"，引擎那个是"当前合成用的是哪个"。
  /// 用错会让 `resetTheme()` 之后的落盘把引擎的旧 id 又写回去。
  Future<void> saveToStorage() async {
    try {
      final box = StorageService.settingsBox;
      await box.put(kThemeBrightnessKey, _mode.storageValue);
      if (_skinId.isEmpty) {
        await box.delete(kThemeSkinIdKey);
      } else {
        await box.put(kThemeSkinIdKey, _skinId);
      }
    } catch (error, stackTrace) {
      debugPrint('ThemeProvider.saveToStorage 失败: $error');
      debugPrint('$stackTrace');
    }
  }

  /// 解析存储里的明暗偏好；无法识别返回 `null`（调用方保持默认）。
  ///
  /// **保留旧签名**（返回 `Brightness?`）以免破坏既有调用方与测试：
  /// `system` 在旧语义下没有对应值，按 `null`（保持默认）处理。
  static Brightness? decodeBrightness(String? raw) {
    final ThemeBrightnessMode? mode = ThemeBrightnessMode.decode(raw);
    switch (mode) {
      case ThemeBrightnessMode.light:
        return Brightness.light;
      case ThemeBrightnessMode.dark:
        return Brightness.dark;
      case ThemeBrightnessMode.system:
      case null:
        return null;
    }
  }

  /// 皮肤声明"我天生就是暗的"（`mode == 'dark'`）时用 [Brightness.dark]。
  ///
  /// 这是一处**有意的特例**：普通皮肤跟随用户的明暗偏好，
  /// 但作者明确标了 `mode: 'dark'` 的皮肤（如"暗夜紫"）意图就是"这套是暗的"，
  /// 强行按用户偏好给亮色会破坏它的配色。反之 `mode: 'light'` 的皮肤
  /// 在任何偏好下都保持亮色。
  static Brightness? _forcedBrightnessOf(SkinPack skin) {
    switch (skin.mode.trim().toLowerCase()) {
      case 'dark':
        return Brightness.dark;
      case 'light':
        return Brightness.light;
      default:
        return null; // system / 缺省 → 跟随用户偏好
    }
  }

  /// 把 [skin] 的 `mode` 声明的强制亮度考虑进来，算出该用哪个亮度。
  Brightness _effectiveBrightnessFor(SkinPack skin) =>
      _forcedBrightnessOf(skin) ?? brightness;

  @override
  void dispose() {
    _disposed = true;
    _engine.dispose();
    super.dispose();
  }

  /// 已释放则不再通知：`applySkin` / `resetTheme` 是异步的，
  /// 若在 await 期间 Provider 被 dispose，直接 `notifyListeners` 会触发 assert。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
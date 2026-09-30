// 内置皮肤包（Phase 6）：随 App 打包的几套配色，保证"创意工坊"开箱有内容。
//
// 为什么内置：Phase 6 之前创意工坊是纯空态，用户点进去什么都做不了。
// 内置皮肤让皮肤系统**立刻可用**，同时也是皮肤 JSON 结构的活文档
// （想写自己的皮肤，照抄一份改颜色即可）。
//
// 远程索引（如果将来接上）返回的皮肤与此处结构完全一致——
// 都走 `SkinPack.fromJson`，所以 UI 不需要区分来源。
import '../models/skin_pack.dart';

/// 皮肤令牌名（与 `ThemeEngine._kSkinTokenAliases` 的别名表对应）。
///
/// 这里只列内核认识的部分；未列出的令牌会被 `AppTheme.fromJson` 忽略。
/// 皮肤作者写的是这套"通用令牌"，内核映射到语义化字段名。
const String kTokenPrimary = 'primary';
const String kTokenSecondary = 'secondary';
const String kTokenBackground = 'background';
const String kTokenSurface = 'surface'; // 别名 card
const String kTokenOnBackground = 'onBackground'; // 别名 textPrimary
const String kTokenError = 'error';
const String kTokenSuccess = 'success';
const String kTokenWarning = 'warning';

/// 内置皮肤的固定安装时间。
///
/// 用常量而不是 `DateTime.now()`：内置皮肤是 App 的一部分，不是"某次安装"，
/// 每次启动都变会让"最近安装"之类的排序结果不稳定。
final DateTime _kBuiltinInstalledAt = DateTime(2026, 1, 1);

/// 全部内置皮肤（顺序即创意工坊的展示顺序）。
///
/// 第一项「默认蓝」与 `AppTheme.defaultTheme()` 完全一致，
/// 作用是给用户一个"回到原样"的选择，同时作为"皮肤能表达什么"的基准。
List<SkinPack> builtinSkins() => <SkinPack>[
      _defaultBlue(),
      _matcha(),
      _sakura(),
      _nightPurple(),
    ];

/// 按 id 查内置皮肤；找不到返回 `null`。
SkinPack? builtinSkinById(String id) {
  for (final SkinPack skin in builtinSkins()) {
    if (skin.id == id) return skin;
  }
  return null;
}

/// 默认蓝：与内置默认主题一致。
SkinPack _defaultBlue() => SkinPack(
      id: 'builtin-default-blue',
      name: '默认蓝',
      version: '1.0.0',
      author: 'MySchedule',
      description: '应用自带的默认配色，清亮克制。',
      lightColors: const <String, int>{
        kTokenPrimary: 0xFF1E88E5,
        kTokenSecondary: 0xFF42A5F5,
        kTokenBackground: 0xFFF5F7FA,
        kTokenSurface: 0xFFFFFFFF,
        kTokenOnBackground: 0xFF212121,
      },
      darkColors: const <String, int>{
        kTokenPrimary: 0xFF64B5F6,
        kTokenSecondary: 0xFF90CAF9,
        kTokenBackground: 0xFF0F1419,
        kTokenSurface: 0xFF1A2027,
        kTokenOnBackground: 0xFFECEFF1,
      },
      courseColors: const <int>[
        0xFFE3F2FD, 0xFFFCE4EC, 0xFFE8F5E9, 0xFFFFF3E0,
        0xFFF3E5F5, 0xFFE0F7FA, 0xFFFFF9C4, 0xFFFFEBEE,
      ],
      borderRadius: 12,
      installedAt: _kBuiltinInstalledAt,
      source: 'builtin',
    );

/// 抹茶：低饱和绿，长时间看课表不刺眼。
SkinPack _matcha() => SkinPack(
      id: 'builtin-matcha',
      name: '抹茶',
      version: '1.0.0',
      author: 'MySchedule',
      description: '低饱和绿调，柔和耐看。',
      lightColors: const <String, int>{
        kTokenPrimary: 0xFF558B2F,
        kTokenSecondary: 0xFF7CB342,
        kTokenBackground: 0xFFF6F8F3,
        kTokenSurface: 0xFFFFFFFF,
        kTokenOnBackground: 0xFF1F2A1A,
        kTokenSuccess: 0xFF2E7D32,
        kTokenWarning: 0xFFEF6C00,
      },
      darkColors: const <String, int>{
        kTokenPrimary: 0xFF9CCC65,
        kTokenSecondary: 0xFFAED581,
        kTokenBackground: 0xFF11150E,
        kTokenSurface: 0xFF1B2117,
        kTokenOnBackground: 0xFFE8F0E3,
      },
      courseColors: const <int>[
        0xFFDCEDC8, 0xFFF0F4C3, 0xFFC8E6C9, 0xFFDCE775,
        0xFFF1F8E9, 0xFFE6EE9C, 0xFFCCFF90, 0xFFF9FBE7,
      ],
      borderRadius: 14,
      installedAt: _kBuiltinInstalledAt,
      source: 'builtin',
    );

/// 樱花：暖粉调，圆角更大。
SkinPack _sakura() => SkinPack(
      id: 'builtin-sakura',
      name: '樱花',
      version: '1.0.0',
      author: 'MySchedule',
      description: '暖粉色调，圆角更柔和。',
      lightColors: const <String, int>{
        kTokenPrimary: 0xFFD81B60,
        kTokenSecondary: 0xFFF06292,
        kTokenBackground: 0xFFFDF6F8,
        kTokenSurface: 0xFFFFFFFF,
        kTokenOnBackground: 0xFF3A1F28,
        kTokenWarning: 0xFFF57C00,
      },
      darkColors: const <String, int>{
        kTokenPrimary: 0xFFF48FB1,
        kTokenSecondary: 0xFFF8BBD0,
        kTokenBackground: 0xFF181114,
        kTokenSurface: 0xFF231A1E,
        kTokenOnBackground: 0xFFF7E9EE,
      },
      courseColors: const <int>[
        0xFFFCE4EC, 0xFFF8BBD0, 0xFFF3E5F5, 0xFFFFE0B2,
        0xFFFFF3E0, 0xFFFCE4EC, 0xFFEDE7F6, 0xFFFFEBEE,
      ],
      borderRadius: 18,
      installedAt: _kBuiltinInstalledAt,
      source: 'builtin',
    );

/// 暗夜紫：本身就是暗色皮肤，`mode: 'dark'` 时**强制**用暗色表
/// （不跟随系统——皮肤作者的意图是"这套就是暗的"）。
SkinPack _nightPurple() => SkinPack(
      id: 'builtin-night-purple',
      name: '暗夜紫',
      version: '1.0.0',
      author: 'MySchedule',
      description: '深紫夜色，夜间看课表不刺眼。',
      mode: 'dark',
      lightColors: const <String, int>{
        kTokenPrimary: 0xFF7E57C2,
        kTokenSecondary: 0xFF9575CD,
        kTokenBackground: 0xFFF7F5FB,
        kTokenSurface: 0xFFFFFFFF,
        kTokenOnBackground: 0xFF241B36,
      },
      darkColors: const <String, int>{
        kTokenPrimary: 0xFFB39DDB,
        kTokenSecondary: 0xFF9575CD,
        kTokenBackground: 0xFF100C1A,
        kTokenSurface: 0xFF1B1528,
        kTokenOnBackground: 0xFFEDE7F6,
      },
      courseColors: const <int>[
        0xFF311B92, 0xFF4527A0, 0xFF512DA8, 0xFF5E35B1,
        0xFF673AB7, 0xFF7E57C2, 0xFF4527A0, 0xFF4A148C,
      ],
      borderRadius: 16,
      installedAt: _kBuiltinInstalledAt,
      source: 'builtin',
    );

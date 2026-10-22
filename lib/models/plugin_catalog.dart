// 创意工坊「插件市场」的可安装目录。
//
// 为什么需要这份目录：插件**未安装**时磁盘上没有任何文件，读不到
// `__plugin` 声明（那是插件 JS 里才有的东西）。市场要展示"有哪些插件
// 可以装"，就必须有一份独立于插件文件的数据源。
//
// 当前是**随 App 打包的静态目录**（只有内置的两个插件）。将来接远端插件源时，
// 只需把 [kPluginCatalog] 换成网络拉取的列表，UI 层不用改。
//
// ⚠️ 这里与 `assets/plugins/*.js` 里的 `__plugin` 存在字段重复（name /
// description / capabilities）。这是"目录"与"插件自述"的固有分工，不是疏忽：
// 安装后以插件自述为准（`PluginMeta` 由 manifest 补齐能力），
// 这里只负责"装之前给用户看什么"。改插件元信息时两边都要动。

/// 内置 NCST 教务插件的 id。
const String kNcstPluginId = 'ncst-jwxt';

/// 内置 NCST 教务插件的 asset 路径。
///
/// 注意：`pubspec.yaml` 里声明的是**目录** `assets/plugins/`，
/// 所以新增插件文件**不需要**改 pubspec。
const String kNcstPluginAssetPath = 'assets/plugins/ncst-jwxt.js';

/// 内置学习通（超星）插件的 id。
const String kChaoxingPluginId = 'chaoxing';

/// 内置学习通插件的 asset 路径（同 [kNcstPluginAssetPath]，不必改 pubspec）。
const String kChaoxingPluginAssetPath = 'assets/plugins/chaoxing.js';

/// 内置「大物实验」插件的 id。
///
/// 与教务系统插件是**两个独立数据源**：教务给的是理论课表，实验系统给的是
/// 已经约好的实验场次。两者都声明 `timetable` 能力，课程靠
/// `sourcePluginId` 区分，同步时互不覆盖（`CourseSyncService` 按 id 增量落盘）。
const String kPhylabPluginId = 'ncst-phylab';

/// 内置「大物实验」插件的 asset 路径。
const String kPhylabPluginAssetPath = 'assets/plugins/ncst-phylab.js';

/// 市场里的一个可安装插件。
///
/// 字段与 `PluginProvider.installBuiltinPlugin` 的参数一一对应——
/// 目录条目的唯一用途就是"喂给安装函数"，不需要额外的转换层。
class PluginCatalogEntry {
  const PluginCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.school,
    required this.capabilities,
    required this.assetPath,
    this.author = 'MySchedule',
  });

  /// 插件 id，与安装后的 `PluginMeta.id` 一致（用于判断"是否已安装"）。
  final String id;

  /// 展示名。
  final String name;

  /// 一句话说明（市场卡片正文）。
  final String description;

  /// 适用学校 / 平台，便于用户判断是否与自己相关。
  final String school;

  /// 声明的数据能力（决定市场卡片的标签与安装后的模块可用性）。
  final List<String> capabilities;

  /// 随 App 打包的 asset 路径。
  final String assetPath;

  /// 作者。
  final String author;

  /// 市场卡片上的能力标签（中文）。
  List<String> get capabilityLabels => capabilities
      .map(pluginCapabilityLabel)
      .toList(growable: false);
}

/// 能力 id → 中文短标签。查不到时原样返回（插件自定义能力就显示原始 id）。
///
/// 放在这里而不是某个页面里：能力 id 是插件协议的一部分，
/// 市场卡片、插件管理卡片、详情页都需要同一套中文说法。
String pluginCapabilityLabel(String capability) {
  switch (capability) {
    case 'timetable':
      return '课表';
    case 'courseList':
      return '课程';
    case 'exam':
      return '考试';
    case 'homework':
      return '作业';
    case 'message':
      return '消息';
    case 'settings':
      return '设置';
    default:
      return capability;
  }
}

/// 全部可安装插件（顺序即市场展示顺序）。
const List<PluginCatalogEntry> kPluginCatalog = <PluginCatalogEntry>[
  PluginCatalogEntry(
    id: kNcstPluginId,
    name: '华北理工大学教务系统',
    description: '从 NCST 教务系统拉取本学期课表（需先登录）',
    school: '华北理工大学',
    capabilities: <String>['timetable'],
    assetPath: kNcstPluginAssetPath,
  ),
  PluginCatalogEntry(
    id: kChaoxingPluginId,
    name: '学习通（超星）',
    description: '从学习通拉取课程、作业（含正文）与考试安排（需先登录）',
    school: '通用（超星学习通）',
    capabilities: <String>['homework', 'exam'],
    assetPath: kChaoxingPluginAssetPath,
  ),
  PluginCatalogEntry(
    id: kPhylabPluginId,
    name: '华北理工大学大物实验',
    description: '从物理实验中心系统拉取你已选好的实验场次，按实验日期排进课表（需先登录）',
    school: '华北理工大学',
    capabilities: <String>['timetable'],
    assetPath: kPhylabPluginAssetPath,
  ),
];

/// 按 id 查目录条目；不存在返回 `null`。
PluginCatalogEntry? pluginCatalogEntry(String id) {
  for (final PluginCatalogEntry entry in kPluginCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}

class ReleaseInfoManifest {
  const ReleaseInfoManifest._();

  static const fallbackAppName = 'Nolive';
  static const fallbackVersion = '0.3.1+4';
  static const fallbackBundleId = 'app.nolive.mobile';
  static const primaryPlatform = 'Android mobile';
  static const flutterBaseline = 'Flutter 3.35+ stable / Dart 3.6+';
  static const androidMinSdk = '23';
  static const playerDefault = 'MPV';
  static const deferredPlatforms = <String>[
    'iOS',
    'Linux',
    'macOS',
    'Windows',
    'TV'
  ];

  static const targetPlatforms = <String>[
    'Android mobile',
    'Android APK',
    'Android App Bundle',
  ];

  static const releaseScope = <String>[
    'Android mobile first release：四平台 live provider runtime',
    '首页 / 分类发现 / 搜索 / 关注 / 我的 五段式 Android 主壳',
    '房间详情、真全屏、播放器内弹幕、线路与清晰度切换',
    '关注直播流、历史、标签、本地快照、WebDAV 与局域网同步入口',
    '账号设置、哔哩哔哩扫码登录、主页编排与本地持久化 bootstrap',
    '播放器设置支持 MPV / MDK / Memory 运行时切换，Android live runtime 启用真实 MPV / MDK',
  ];

  static const highlights = <String>[
    '文件仓储驱动的 settings / follows / history / tags 持久化链路',
    '首页、分类发现、搜索、关注、我的 已按 Android 内容流重新设计',
    '关注页现已支持直播中 / 未开播筛选、直播卡片优先展示与长按快捷操作',
    '搜索结果与分类详情现已统一成房间内容卡片网格，交互更一致',
    '房间解析页现已支持真实房间检查，可直接验证房间标题、主播和可开状态',
    'Huya 长链接 / Douyu topic 链接解析已补齐，Douyu 签名改为内置 QuickJS 不再依赖 Node',
    'Bilibili 二维码登录与 Bilibili / 抖音账号校验面板',
    'Android live runtime 现已通过 media_kit / fvp 渲染真实 MPV / MDK 视频画面',
    '设置中心现已支持 MPV 硬解 / 兼容模式、MDK 低延迟 / Android Tunnel 与 Force HTTPS',
    '房间页现已支持真全屏、播放器内弹幕 overlay、下拉刷新与快捷操作面板',
    'Bilibili / Douyu / Huya / Douyin live runtime 已切到真实实时弹幕 session，预览环境继续保留 deterministic ticker',
    '新增 `integration_test` + `scripts/run_main_app_android_smoke.sh`，可在连接 Android 设备时执行观看主链路与设置入口 smoke',
  ];

  static const releaseChecks = <String>[
    '更新 `apps/main_app/pubspec.yaml` 版本并确认目标平台列表',
    '确认 `CHANGELOG.md` 与 `docs/release-checklist.md` 已同步',
    '运行 `scripts/build_main_app.sh verify` 与 `scripts/build_main_app.sh android-release-ready`',
    '如已连接 Android 设备 / 模拟器，再运行 `scripts/run_main_app_android_smoke.sh`',
    '执行 Android 实机 / 模拟器 smoke 与手工检查搜索、房间、MPV/MDK 播放、关注、快照、账号、布局编排',
  ];
}

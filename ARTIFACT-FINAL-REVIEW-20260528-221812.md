# Pill 项目最终复盘 — 2026-05-28

## 项目概况

| 项目 | 值 |
|------|-----|
| 名称 | Pill（灵动岛 macOS 应用） |
| 语言 | Swift 6.3 + SwiftUI |
| 构建 | Swift PM（无 Xcode） |
| 目标 | macOS 14+ / Apple Silicon |
| 代码量 | 3,232 行（3,114 Swift + 118 C），19 个源文件 |
| 二进制 | Release 1.5MB，zip 374KB |
| GitHub | https://github.com/MedSageYu/Pill |
| Release | https://github.com/MedSageYu/Pill/releases |

## 功能清单

| 面板 | 功能 | 实现方式 |
|------|------|---------|
| 🏠 主页 | 音乐 + 镜子 + 日历 三栏 | `HomePanelView` |
| 📡 隔空 | AirDrop 拖拽 + 文件托盘 | `AirDropFilePanel` |
| 📋 剪贴板 | 最近 20 条复制历史 | `ClipboardPanelView` |
| ··· 更多 | 设置 | `MorePanelView` → `SettingsPanel` |
| 🎵 折叠态 | 播放时显示封面+波形 | `CollapsedMusicView` |
| 🔔 通知 | iMessage/邮件上岛 | `CollapsedNotificationView` / `NotificationManager` |

## 源码架构

### 入口层
```
main.swift (6)     → NSApplicationMain
AppDelegate.swift (15) → 创建 NotchWindowController
Info.plist (19)    → Bundle 配置 + 权限声明
```

### 窗口层
```
NotchWindow.swift (37)         → NSWindow(level: .statusBar+8, borderless)
NotchWindowController.swift (165) → TrackingView + sendEvent过滤 + hover自动展开
```

### 状态层
```
NotchViewModel.swift (502)     → ObservableObject 全局状态
  - 展开/收起动画
  - activeTab 切换
  - 自动收起计时器
  - 音乐播放状态同步
  - 摄像头帧同步
```

### 数据层
```
AppSettings.swift (64)         → @AppStorage 持久化设置
ClipboardManager.swift (107)   → NSPasteboard 轮询
EventMonitor.swift (57)        → NSEvent 全局监控
NotificationManager.swift (133)→ DistributedNotificationCenter
FileTrayPanel.swift (184)      → FileTrayManager + TrayFileItem
```

### 视图层
```
NotchView.swift (490)          → 主视图（胶囊 + tabBar + 内容）
  - unifiedPill: 统一胶囊背景（展开/收起共用）
  - tabBar: 左 2 + 右 2 分栏（避开刘海）
  - tabContent: 4 个面板切换
  
NotchTab.swift (26)            → Tab 枚举（home/airdrop/clipboard/more）
MusicControlView.swift (325)   → AppleScript 音乐控制 + Artwork
MirrorPanel.swift (361)        → 摄像头预览（AVCaptureSession）
ContentViews.swift (237)       → CompactCalendarView + FileTrayView
ClipboardPanelView.swift (254) → 剪贴板历史视图
AirDropPanel.swift (109)       → AirDrop 支持（NSSharingService + .startAirDrop 扩展）
WaveformView.swift (42)        → Canvas 波形动画
```

### C 辅助
```
mrhelper.c (118)               → MediaRemote CLI fallback 工具
  - 编译: clang -O2 -o mrhelper mrhelper.c -framework CoreFoundation -framework Foundation
  - 用途: AppleScript 失败时的备选音乐信息查询
  - 打包: 放在 Pill.app/Contents/MacOS/mrhelper
```

## 关键设计决策

1. **统一胶囊** — 展开和收起共用同一个 Pill 形状，动画连续无拼接缝
2. **左右分栏 tabBar** — 左边 2 个、右边 2 个，中间 Spacer 穿过刘海区域
3. **AppleScript 主 + mrhelper 备** — 音乐控制主用 AppleScript，失败才 fallback 到 MediaRemote CLI
4. **悬停自动展开** — TrackingView + sendEvent 过滤
5. **仅一次右键** — Ad-hoc 签名，首次需右键打开，之后正常

## 发布状态

- ✅ 源码：19 文件，零警告零错误
- ✅ Release：374KB zip，包含 Release 构建 + Ad-hoc 签名
- ✅ README：简洁通用，顶部分享下载链接 + 首次打开说明
- ✅ GitHub 仓库：6 个条目（.gitignore LICENSE Package.swift README.md Sources mrhelper.c）
- ✅ 死代码已清理：删除 MediaRemoteWrapper.c

## 用户操作

1. 打开 https://github.com/MedSageYu/Pill/releases
2. 下载 Pill.zip
3. 解压，右键 Pill.app → 打开（仅第一次）
4. 之后正常双击使用

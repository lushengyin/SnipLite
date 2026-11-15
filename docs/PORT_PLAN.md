# SnipLite macOS 移植方案

> **当前状态（2026-11-15）**：P0–P6 主体已完成。截图/标注/贴图/OCR 划词/二维码/四家翻译/首选项/历史/图标/dmg 打包均已落地。
> 剩余：Developer ID 签名 + 公证（需要 Apple 开发者账号）；元素级（AX）框选仍降级为窗口级。

决定于 2026-11-15：**原生 Swift + AppKit**、**完整对齐、分阶段交付**、**默认快捷键按 Mac 习惯**（⌃⌥A 截图 / ⌃⌥S 贴图 / ⌃⌥O OCR / ⌃⌥Q 二维码）。

Windows 版行为细节见 [exploration/](exploration/)。本文只写"怎么搬"。

---

## 1. 架构分层

```
SnipLiteCore   (framework, 无 UI)
  ├─ Model     设置、历史、贴图、标注的数据结构与编解码
  ├─ Capture   屏幕几何换算、选区运算
  ├─ Recognition OcrDocument、字符框分配、翻译 provider、分块与覆盖层算法
  └─ Support   路径、日志、文件命名、JSON 存储

SnipLite       (app, LSUIElement)
  ├─ App        启动、状态栏、菜单、权限、热键、Toast
  ├─ Capture    遮罩窗口、选区交互、放大镜、工具栏
  ├─ Annotation Shape 渲染、撤销重做、文字输入
  ├─ Pin        贴图窗口、阴影、分组、拖放
  └─ Settings   首选项 8 页
```

拆 framework 的理由：纯逻辑（字符框、翻译分段、覆盖层分块、文件名模板、撤销栈）可以在 XCTest 里毫秒级回归，不用起 UI——对应 Windows 版的 `SnipLite.SelfTest`。

**构建**：XcodeGen（`macos/project.yml`）生成 `.xcodeproj`。菜单栏应用必须有 `.app` 包、Info.plist、签名，SwiftPM 裸可执行文件做不了 TCC 权限。

---

## 2. 关键设计决定

### 2.1 坐标系统（最容易错的地方）

三套坐标必须在边界处显式转换，绝不混用：

| 坐标 | 原点 | 单位 | 用在哪 |
|---|---|---|---|
| 全局物理像素 | 主屏左上，可负 | px | **模型唯一坐标**：选区、Shape、OCR 框、马赛克网格、历史区域 |
| NSScreen.frame | 左下，主屏左下 | pt | 窗口布局、遮罩铺屏 |
| CGEvent / CGWindowList | 左上 | pt（全局） | 鼠标位置、窗口命中 |

规则：

- 模型层只存"全局物理像素"；`ScreenGeometry.snapshot()` 在截屏时冻结一次屏幕布局，之后所有换算用它，不实时读 NSScreen。
- 每个屏幕有独立 `scale`，换算按"点落在哪块屏"选 scale，不能用主屏的。
- 遮罩视图 `isFlipped = true`，内部统一左上原点。
- 1 物理像素的线在 Retina 上必须画成 `1 / scale` pt。

### 2.2 冻结截图

- `SCScreenshotManager.captureImage(contentFilter:configuration:)` 一次性抓所有显示器，合成到一张虚拟屏画布（原点与虚拟屏并集一致）。
- **遮罩显示前完成抓屏**；同时用 `SCContentFilter(display:excludingWindows:)` 排除自身窗口，双保险。
- `SCStreamConfiguration.showsCursor` 控制是否捕获光标。

### 2.3 设置存储

- `~/Library/Application Support/SnipLite/settings.json`，`Codable`，**新增 `schemaVersion`**（Windows 版没有，是历史包袱）。
- 枚举存字符串、颜色存 `{"r","g","b","a"}`、热键存 `{"key":"A","modifiers":["control","option"]}`——不复用 Windows 的 `Keys` 整数位域。
- 即时保存（无确定/取消），写 `.tmp` 后原子替换，`AutoBackup` 时留 `.bak`。
- 微软翻译密钥改 Keychain（`kSecClassGenericPassword`）。

### 2.4 权限

三种，分别引导，缺权限时**无损降级**而不是报错退出：

| 权限 | 用途 | 缺失时 |
|---|---|---|
| 屏幕录制 | ScreenCaptureKit | 无法截图，引导去系统设置，提供"重新检测" |
| 辅助功能 | 控件级框选（AX） | 降级为窗口级框选（CGWindowList），首选项里提示 |
| 输入监控 | 仅当启用"屏蔽 ⌘ 键" | 该开关置灰并说明 |

Carbon `RegisterEventHotKey` 不需要任何权限，优先用它做全局热键。

### 2.5 移植时保留的"怪"行为

这些是产品语义，不是 bug，不要"顺手优化"：

- 右键 = 取消截图，不是菜单。
- 重新框选清空全部标注和撤销栈。
- 只有文字可选中/移动/删除，其他标注画完即固化。
- 马赛克从**冻结截图**采样，不从合成图。
- 橡皮只清标注层 alpha，不改截图。
- 贴图没有旋转。
- 贴图键在遮罩可见时一律交给遮罩，绝不放旧剪贴板内容。
- 贴图优先于复制；自动保存可与任意分支叠加。
- 缩略图会把小图放大。
- "恢复默认"只重置当前页。

---

## 3. 阶段划分

| 阶段 | 范围 | 验收 |
|---|---|---|
| **P0 骨架** | XcodeGen 工程、菜单栏应用、设置/日志/路径、权限检测、Core 单测骨架 | 无 Dock 图标启动；菜单可打开、关于面板显示权限状态、退出可用；`xcodebuild test` 通过 |
| **P1 截图核心** | 冻结抓屏、全屏遮罩、选框/8 锚点/平移、尺寸徽标、放大镜、窗口级命中、Esc/右键/Enter、复制/保存/快速保存、剪贴板 | ⌃⌥A 多屏框选，复制出的像素与选区一致；尺寸/坐标正确；Esc 层级正确 |
| **P2 标注** | Shape 模型与渲染、工具栏像素级布局、11×2 调色板、7 种箭头、马赛克、马克笔、橡皮、撤销/重做、文字编辑含中文输入法 | 八个工具全可用；撤销语义与原版一致；中文/emoji 光标位置正确 |
| **P3 贴图** | PinWindow + 阴影、拖动/滚轮缩放/透明度、分组 1–3、缩略图、鼠标穿透、可恢复贴图、右键菜单、Alt 拖出、文字转图片 | ⌃⌥S 贴图；分组切换/恢复/穿透行为对齐 |
| **P4 识别** | Vision OCR + 字符级 OcrDocument、划词选字、二维码、四个翻译 provider、原位覆盖层、翻译面板 | 划词复制；二维码复制；译文原位覆盖且标注在上层；切原文像素完全还原 |
| **P5 首选项** | 8 页设置全量控件、热键录制与注册、开机启动、托盘菜单增强项、截图历史 | 设置即时生效并持久化；热键冲突提示 |
| **P6 发布** | 更新检查、应用图标、dmg 打包、Developer ID 签名 + 公证 | 可分发安装包 |

每阶段结束都要能独立跑起来，不做"半截编译不过"的中间态。

---

## 4. 模块映射

| Windows | Swift | 阶段 |
|---|---|---|
| `Program.cs` / `TrayContext.cs` | `App/AppDelegate.swift`、`StatusItemController.swift` | P0 |
| `AppSettings.cs` / `PreferenceSettings.cs` | `Core/Model/AppSettings.swift` | P0 |
| `AppLog.cs` / `AppInfo.cs` | `Core/Support/AppLog.swift`、`AppInfo.swift` | P0 |
| `CaptureForm.cs`（2200 行） | `Capture/CaptureOverlayWindow.swift` + `CaptureSession.swift` + `SelectionController.swift` + `MagnifierView.swift` | P1/P2 |
| `DesktopTargets.cs` | `Capture/TargetResolver.swift`（CGWindowList + AX） | P1 |
| `Annotation.cs` | `Annotation/Shape.swift` + `ShapeRenderer.swift` | P2 |
| `AnnotationBar.cs` | `Capture/AnnotationBarView.swift` | P2 |
| `TextEditLayout.cs` / `ImeSink.cs` | `Annotation/TextEditor.swift`（`NSTextInputClient`） | P2 |
| `PinForm.cs` / `PinShadowWindow.cs` | `Pin/PinWindow.swift` + `PinController.swift` | P3 |
| `SimdOcr.cs` / `OcrSelection.cs` | `Core/Recognition/OcrDocument.swift` + `VisionOcrEngine.swift` | P4 |
| `Services.cs`（QR/OCR） | `Core/Recognition/BarcodeScanner.swift` | P4 |
| `TranslationService.cs` 及 4 个 provider | `Core/Recognition/Translation/` | P4 |
| `TranslationOverlay.cs` | `Core/Recognition/TranslationOverlay.swift` + CG 渲染 | P4 |
| `TranslationPanel.cs` | `Capture/TranslationPanelView.swift` | P4 |
| `PreferencesForm.cs` / `PreferencesPages.cs` | `Settings/PreferencesWindow.swift` + 分页 | P5 |
| `HotkeyHost.cs` / `HotkeyBox.cs` | `App/HotkeyCenter.swift`（Carbon）+ 录制控件 | P5 |
| `CaptureHistory.cs` | `Core/Model/CaptureHistory.swift` | P5 |
| `ReleaseUpdates.cs` | `App/UpdateChecker.swift` | P6 |

---

## 5. 主要风险

1. **文字排版差异**：GDI+ `MeasureString(GenericTypographic)` 与 Core Text 在行高、字距、尾随空格上不同，文字光标/点击落点会整体偏移。对策：文字编辑的测量统一走 `CTLine`，视觉回归用截图对比。
2. **Vision 字符框精度**：没有 Paddle 的 CTC 对齐。对策：先用 `VNRecognizedText.boundingBox(for:)`，明显过粗时回退到按 CoreText 宽度比例分配（复用原版降级路径）。
3. **AX 元素框选**：`AXUIElementCopyElementAtPosition` 会命中自己的全屏遮罩。对策：先用 CGWindowList 找到指针下的目标进程，再对该 app 做最小包含矩形遍历；未授权直接降级窗口级。
4. **多 Space / 全屏应用**：遮罩窗口需要 `[.canJoinAllSpaces, .fullScreenAuxiliary]`，但在别的 Space 全屏时行为仍可能与 Windows 不同，需实测。
5. **翻译 provider 存活**：Google 公共接口、必应网页会话都无 SLA，参数会变。对策：provider 与解析逻辑分离开，单测用录制响应，坏掉只修解析。

---

## 6. 目录结构

```
macos/
├── project.yml
├── Sources/
│   ├── SnipLiteCore/
│   └── SnipLite/
├── Tests/
│   └── SnipLiteCoreTests/
└── README.md
```

C# 源码保持不动，Windows 版继续可用。

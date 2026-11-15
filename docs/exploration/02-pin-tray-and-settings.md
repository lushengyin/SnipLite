# SnipLite 只读探索报告

仓库根：`/Users/lusheng/Documents/开源工具/SnipLite`

## 1. 托盘 / 菜单栏应用生命周期

### 1.1 启动、单实例与参数

- 入口为 `Program.Main`，先初始化 WinForms、系统颜色模式和主题；随后优先处理 `--startup-admin:on/off`，调用 `Startup.ConfigureAdminTask` 后直接退出，不进入托盘逻辑。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Program.cs:8`、`Program.cs:12`。
- 单实例通过命名互斥体 `Global\SnipLite.SingleInstance` 实现。普通启动不等待；带 `--wait-for-instance` 时最多等待 5000ms。拿不到互斥体时弹出 MessageBox，显示“已有实例”、版本和 exe 路径后退出。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Program.cs:18`。
- 未处理异常模式设为 `CatchException`，线程异常和 AppDomain 异常统一写入 `%TEMP%\SnipLite\error.log`，并弹出 4 秒错误 Toast，避免截图遮罩后面弹模态异常框。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Program.cs:31`、`Program.cs:59`。
- 支持参数：
  - `--capture`：启动后立即截屏。
  - `--prefs` 或 `--prefs:N`：打开首选项，N 被夹在 0–7；无冒号时为 0。
  - `--menu`：启动后在屏幕坐标 `(200,200)` 弹出托盘菜单。
  - `--wait-for-instance`：用于“重新启动”时等待旧实例释放互斥体。
  - `--startup-admin:on/off`：开机启动提权辅助入口，在互斥体之前处理。
  - 参数解析见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Program.cs:40`；文档见 `/Users/lusheng/Documents/开源工具/SnipLite/docs/DEVELOPMENT.md:16`。
- 没有主窗口。`TrayContext` 继承 `ApplicationContext`，构造 `NotifyIcon` 后即进入消息循环；截图窗口、首选项窗口、贴图窗口都按需创建。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:17`。
- 启动参数通过一个 250ms 单次 WinForms Timer 延后执行，确保消息循环已启动。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:24`。
- `KeepResponsive` 为 true 时，后台预热 Windows OCR 引擎（当前版本仅 Windows OCR 预热）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:32`。
- 托盘图标双击默认开始普通截屏。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:22`。
- 首选项是单实例、非模态窗口：已打开则 `Activate()` 并切页，否则新建并 `Show()`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:82`。
- 退出顺序：解除主题事件、释放主题监视器、隐藏并释放托盘图标、关闭截图遮罩和首选项、释放热键、关闭全部贴图（不保存可恢复贴图）、`ExitThread()`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:241`。
- “重新启动”先以 `--wait-for-instance` 启动自身，再退出当前实例。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:236`。

### 1.2 托盘图标与主题

- Auto 模式跟随任务栏明暗（注册表 `SystemUsesLightTheme`），而不是应用窗口明暗；深色任务栏用近白色 `(245,245,245)`，浅色用 `(40,40,43)`；高对比度用 `WindowText`。Color 模式使用主题色。Custom 模式读取 `.ico`（32×32）或普通图片缩放到 32×32；失败写日志并回退默认。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayIcons.cs:5`、`TrayIcons.cs:14`。
- 应用图标来自嵌入资源 `SnipLite.AppIcon.ico`；窗口共用 32px 图标。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppIcon.cs:6`。
- 托盘 Tooltip 形如 `SnipLite 0.3.11 | F1 截图 | F3 贴图`，截断到 63 字符。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:95`。
- 主题变化时只重建托盘图标并重绘遮罩，不重建菜单。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:248`。
- 主题来源：注册表 `AppsUseLightTheme` / `SystemUsesLightTheme`，并监听 `WM_SETTINGCHANGE`、`WM_THEMECHANGED`、`WM_SYSCOLORCHANGE`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppTheme.cs:35`、`AppTheme.cs:119`。

### 1.3 托盘右键菜单完整层级

构建逻辑见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:39`。`EnhancedTrayMenu` 默认 true，因此默认菜单包含标 `[增强]` 的条目：

```
截屏                                      F1
截屏并自动复制                            [增强] 未设置
自定义截屏…                               [增强] 未设置
贴图 / 恢复贴图                           F3
隐藏 / 显示所有贴图                       未设置
切换到另一贴图分组                        [增强] 未设置
恢复最近关闭的贴图                        [增强]
关闭全部贴图                              [增强]
截屏历史 ▸                                [增强，动态子菜单]
清空截屏历史                              [增强]
────────
禁用快捷键                                [可勾选；勾选=快捷键已禁用]
文字识别                                  Ctrl+Alt+O
二维码识别                                Ctrl+Alt+Q
────────
首选项…                                   打开页 0
帮助                                      打开页 7（关于）
重新启动
退出
```

细节：

- 未设置快捷键的菜单项显示“未设置”，因为 `HotkeyDefinitions.Format(Keys.None)` 返回该文本。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyBox.cs:19`。
- “截屏历史”子菜单每次展开时清空并重建：列出最近截图的时间与尺寸，点击后直接贴图；为空时显示禁用的“暂无截屏历史”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:55`。
- “清空截屏历史”同时清空 `RecentRegions` 并保存设置。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:65`。
- 菜单字体使用设置中的界面字体；菜单重建条件是 `EnhancedTrayMenu|DisplayLanguage|InterfaceFont|InterfaceFontSize|所有快捷键值` 的签名变化。主题色、托盘图标样式变化不会触发菜单重建。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:97`。
- `UiText.Apply` 只翻译固定词典中的英文；动态文本（历史标签、Toast）保持中文。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/UiText.cs:5`。

### 1.4 开机启动

- 默认 `StartWithWindows=false`、`StartAsAdministrator=false`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:48`。
- 普通开机启动写入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，值为带引号的 exe 路径；关闭时删除该值。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Startup.cs:47`。
- “以管理员身份开机启动”使用任务计划程序 COM：登录触发、当前用户交互令牌、`HighestAvailable`、无电池限制、`PT0S` 时限；注册/删除需要以 `runas` 启动自身辅助进程。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Startup.cs:33`、`Startup.cs:77`。
- 若已存在管理员任务，任何开关操作都会先提权调用辅助进程删除/重建任务。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Startup.cs:37`。
- 注意：`Startup.IsEnabled` 实际未被生产代码调用；程序启动时不会用注册表真实状态校正 `StartWithWindows`，外部删除 Run 项后设置仍可能显示勾选。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Startup.cs:12`。

## 2. 贴图（Pin）功能

### 2.1 窗口创建与层级、阴影

- `PinForm` 是无边框、无任务栏、手动定位、`TopMost=true`、双缓冲、黑色背景、`KeyPreview=true` 的 WinForms 窗体；标题“SnipLite 贴图”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:36`。
- 初始锚点：默认鼠标位置，或截屏选区的中心（`PinAtCapturePosition=true`）。初始缩放为 `min(1, PinMaxSize / max(宽,高))`，窗口尺寸按缩放后取整，然后夹入虚拟屏幕。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:42`、`PinForm.cs:152`。
- 每次布局用 `SetWindowPos(HWND_TOPMOST, ..., SWP_NOACTIVATE)` 强制置顶并设置位置/尺寸。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:131`。
- 阴影是独立的 `PinShadowWindow`，不是贴图窗口绘制的一部分，也不包含在导出的图片中。它无边框、无任务栏、置顶、`ShowWithoutActivation`，扩展样式为 `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinShadowWindow.cs:11`、`PinShadowWindow.cs:15`。
- 阴影算法：以图片矩形外区域计算高斯衰减，`sigma = max(2, 5*scale)`，阴影偏移 `(3,5)*scale`，最大 alpha 68，RGB 乘以 alpha 预乘；通过 `UpdateLayeredWindow` 输出 32bpp 预乘 alpha。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinShadowWindow.cs:19`、`PinShadowWindow.cs:41`。
- 阴影边距约 `16 * DPI/96`，与虚拟屏幕求交；完全在屏外则隐藏。拖动过程中只移动阴影，鼠标松开后重新渲染。贴图隐藏时阴影随之隐藏。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:139`、`PinForm.cs:53`。
- 阴影颜色默认黑色（`PinShadowColor`），但算法会用该颜色给 alpha 着色。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:63`。

### 2.2 拖动、缩放、透明度、旋转

- 拖动：左键按下记录绝对屏幕光标位置，移动时按光标增量移动窗口；不使用窗口内鼠标坐标，因此鼠标移出窗口仍可拖。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:175`、`PinForm.cs:182`。
- 缩放：
  - 滚轮缩放需 `PinWheelZoom=true` 且当前修饰键精确等于 `PinZoomModifiers`（默认 `None`，即普通滚轮缩放）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:208`。
  - 缩放步长 1.1×；默认以鼠标指针为中心（`PinZoomAtCursor=true`），否则以窗口中心。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:214`。
  - 缩放范围 `0.02` 到 `min(8, PinMaxSize / 图片最大边)`。初始只缩小不放大。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:133`。
  - 键盘 `+/-` 也可缩放，要求修饰键精确匹配 `PinZoomModifiers`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:221`。
  - 缩放采用 `PinSmoothScaling=true` 时高质量双三次，否则最近邻。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:158`。
- 透明度：
  - 默认打开不透明度 100%，夹在 10–100。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:26`。
  - `Ctrl + 滚轮` 调整，步长 0.1，夹在 0.1–1.0；`PinOpacityModifiers` 默认 `Control`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:107`。
  - 键盘 `+/-` 在匹配 `PinOpacityModifiers` 时调整透明度。优先级高于缩放。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:210`。
  - 右键菜单“恢复 100% 不透明度”只改当前贴图，不改设置默认值。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:296`。
  - 每张贴图的透明度、缩放、位置、分组、缩略图、鼠标穿透状态均不持久化。
- 旋转：原实现没有任何旋转功能，`PinForm` 中不存在旋转字段或变换。移植时不应臆造。

### 2.3 缩略图、鼠标穿透、隐藏/恢复、分组

- 快速缩略图不是预览窗，而是把贴图缩放到 `ThumbnailWidth × ThumbnailHeight`（默认 75×75）以内；小图可能被放大。再次切换恢复 1.0 倍。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:237`。
- `Ctrl+0` 或菜单“原始大小”恢复 1.0；若当前是缩略图且 `ThumbnailAcceptReset=false`，重置被忽略。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:236`。
- 鼠标穿透：切换 `GWL_EXSTYLE` 的 `WS_EX_TRANSPARENT (0x20)`；开启后贴图不再接收鼠标事件，只能用全局快捷键关闭。每张贴图独立，运行期有效，不持久化。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:243`。
- 隐藏/显示全部：
  - `HideAll()` 隐藏所有组的全部贴图。
  - `ShowAll()` 只显示当前组，并激活该组最后一张。
  - `ToggleAll()`：只要有任何可见贴图就全部隐藏；否则只显示当前组。
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:67`。
- 分组：
  - 全局静态当前组 `_group`，默认 1，只有 1–3 三组；新贴图继承当前组。
  - `SwitchGroup()` 按 `1→2→3→1` 循环，显示目标组、隐藏其他组，并对目标组每张贴图触发闪烁（`FlashOnGroupSwitch=true`），最后 Toast “贴图分组 N”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:74`。
  - 单张贴图右键“移动到分组 1/2/3”：赋给其他组后立即隐藏；赋给当前组无动作。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:293`。
  - 关闭的贴图会记录所属组，恢复时切回该组。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:101`。
- 可恢复贴图：
  - 关闭时若 `RecoverablePins > 0`，把原图 PNG、左上角位置、组号存入内存链表；超过数量从最旧删除。默认 1 张，最大 20。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:119`、`PreferenceSettings.cs:79`。
  - 程序退出时 `_exiting=true`，关闭所有贴图且清空可恢复列表。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:66`。
  - `RestoreLast()` 取最后关闭的一张，解码 PNG，重建贴图；丢失缩放、透明度、缩略图、鼠标穿透状态。位置按“保存的左上角 + 原图宽高/2”作为中心，再按当前缩放窗口居中。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:101`。
- 闪烁：
  - 新贴图默认闪烁（`FlashNewPin=true`），6 个 120ms tick，偶数 tick 降低透明度到 `min(0.65, 当前)`（`PinTranslucentFlash=true`），并在图片边缘绘制主题色边框。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:47`、`PinForm.cs:163`。
  - `HidePinsDuringFlash=true` 时，闪烁期间按贴图键会隐藏全部贴图并消费该次按键。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:90`。
- 多显示器：
  - 初始位置夹入 `SystemInformation.VirtualScreen`（所有显示器并集，物理像素）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:152`。
  - 阴影与虚拟屏幕求交，避免绘制到屏幕外。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinShadowWindow.cs:45`。
  - 拖动/缩放只按物理像素处理，没有按显示器 DPI 重算；混合 DPI 下可能有细节偏差。
  - 贴图是真实置顶窗口，会出现在后续桌面截图中（截图遮罩冻结桌面时可能包含贴图和阴影）。

### 2.4 鼠标手势与右键菜单

默认鼠标手势见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:108`：

| 手势 | 默认行为 |
|---|---|
| 左键双击 | 关闭贴图 |
| 中键单击 | 重置为原始大小 |
| Shift + 左键双击 | 切换快速缩略图 |
| Shift + 右键单击 | OCR 识别并复制文字 |

- 手势匹配要求修饰键完全相等；匹配顺序为：关闭 → 重置 → 缩略图 → 复制文本。匹配右键手势时会抑制随后的 `WM_CONTEXTMENU`，避免同时弹菜单。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:166`、`PinForm.cs:203`。
- 普通右键（未匹配手势）弹出贴图菜单。完整条目：
  - 复制图像（Ctrl+C）
  - 另存为…（Ctrl+S）
  - 识别文字
  - 识别二维码
  - 分隔线
  - 原始大小（Ctrl+0）
  - 快速缩略图
  - 鼠标穿透开关
  - 移动到分组 ▸ 分组 1 / 分组 2 / 分组 3
  - 关闭（Esc）
  - 关闭全部贴图
  - 隐藏 / 显示所有贴图
  - 恢复 100% 不透明度
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:285`。
- 菜单快捷键文本只在 `PinMenuShortcuts=true` 时显示（默认 true）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:288`。
- 键盘：Esc 关闭；Ctrl+C 复制图像；Ctrl+S 另存为；Ctrl+0 原始大小；`+/-` 缩放或透明度。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:221`。
- Alt + 拖动（移动超过 6px）会把**原始全分辨率图片**写入 `%TEMP%\SnipLite\drag\<guid>.png`，然后发起文件拖放；拖放成功且 `KeepOriginalOnDrag=false` 时关闭原贴图。默认 `KeepOriginalOnDrag=true`，即保留原贴图。临时文件不会被清理。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:186`。

### 2.5 贴图与剪贴板文字转图片的关系

`F3` / 托盘“贴图 / 恢复贴图”共用 `PasteFromClipboard()`，逻辑见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:198`：

1. 若截图遮罩正在显示：把这次按键交给遮罩，贴出当前选区；即使尚未框选也消费按键，绝不贴旧剪贴板内容。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:228`、`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1651`。
2. 若存在隐藏贴图或正在闪烁的贴图，按 `HidePinsDuringFlash` 规则先隐藏/恢复，并结束本次操作。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:90`。
3. 读取剪贴板序列号 `GetClipboardSequenceNumber`。若与上次相同，说明用户连续按贴图键而非复制了新内容：优先恢复最近关闭的贴图，其次激活当前组已有贴图。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:202`。
4. 剪贴板有图片：直接贴出。
5. 没有图片且 `TextToImage=true`（默认）且剪贴板有文本：
   - 若 `IgnoreFilePaths=true`（默认），检测到文件路径则跳过。路径检测包括存在的文件/目录、Windows 盘符、UNC、`file://`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TextImageRenderer.cs:10`。
   - 若 `IgnoreHtml=false` 且剪贴板有 HTML，则解析 HTML 的粗体/斜体/下划线/换行等基础格式。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TextImageRenderer.cs:15`。
   - 使用 `TextImageFont`（默认 Microsoft YaHei UI，11pt）、背景/前景色、页边距 15、最大宽度 900 渲染为位图，然后贴出。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:83`。
   - 文字转图片只用于本次贴图，不写入剪贴板、不加入截图历史、不触发自动保存。
6. 若以上都没有：恢复最近关闭的贴图；再退而使用截图历史最新一条；最后提示“剪贴板中没有可贴出的内容”。
7. 异常写日志并 Toast“贴图失败”。

另外，截屏遮罩内本身也直接处理贴图键和 `Ctrl+T`，不依赖全局热键注册；`Ctrl+T` 是固定备用键。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:863`、`CaptureForm.cs:948`。

## 3. 全局快捷键

### 3.1 默认键位

定义与默认值见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:95`，列表顺序见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyBox.cs:5`。

| 功能 | 字段 | 默认值 | 是否全局注册 |
|---|---|---|---|
| 截屏 | `CaptureHotkey` | `F1` | 是 |
| 截屏并自动复制 | `CopyCaptureHotkey` | `None` | 是（设置后） |
| 自定义截屏 | `CustomCaptureHotkey` | `None` | 是（设置后） |
| 贴图 / 恢复贴图 | `PinHotkey` | `F3` | 是 |
| 隐藏 / 显示所有贴图 | `TogglePinsHotkey` | `None` | 是（设置后） |
| 切换到另一贴图分组 | `SwitchGroupHotkey` | `None` | 是（设置后） |
| 鼠标穿透开关 | `MouseThroughHotkey` | `None` | 是（设置后） |
| 文字识别 | `OcrHotkey` | `Ctrl+Alt+O` | 是 |
| 截图翻译 | `TranslationHotkey` | `Ctrl+Alt+T` | 是 |
| 二维码识别 | `QrHotkey` | `Ctrl+Alt+Q` | 是 |
| 复制坐标（截图中） | `CopyCoordinatesHotkey` | `Ctrl+Shift+C` | **否**，只在截图遮罩内处理 |
| 贴图缩放修饰键 | `PinZoomModifiers` | `None` | 修饰键，不注册 |
| 调透明度修饰键 | `PinOpacityModifiers` | `Ctrl` | 修饰键，不注册 |

鼠标绑定默认值：

| 绑定 | 默认 |
|---|---|
| `PinCloseMouse` | 无修饰 + 左键双击 |
| `PinResetMouse` | 无修饰 + 中键单击 |
| `PinThumbnailMouse` | Shift + 左键双击 |
| `PinCopyTextMouse` | Shift + 右键单击 |

### 3.2 注册方式与冲突检测

- 使用隐藏的 message-only 窗口（`HWND_MESSAGE = -3`）承载 `RegisterHotKey`，每个热键分配自增 id，并始终带 `MOD_NOREPEAT`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyHost.cs:19`、`HotkeyHost.cs:28`。
- `WM_HOTKEY (0x0312)` 在窗口过程里查表执行；异常被吞掉，避免热键打断消息循环。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyHost.cs:47`。
- 设置应用时先 `UnregisterAll()`、清空 `HotkeyErrors`，再逐个注册；禁用快捷键或正在编辑热键时全部不注册，保留窗口以便恢复。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:107`。
- 注册失败（被其他程序占用）记录 `HotkeyErrors[name] = "已被其他程序占用"`，并弹出 Toast；其他热键仍继续尝试注册，属于部分成功。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:135`。
- `CopyCoordinatesHotkey` 被显式跳过，不做全局注册。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:129`。
- 内部重复检测在设置 UI 中完成：新值与任何其他功能的完整 `Keys` 值相同即拒绝保存，并显示“与其他功能重复”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:358`。
- 热键输入框获得焦点时通过 `HotkeyEditing` 暂停所有全局注册，失焦后重新注册；因此编辑过程中不会抢键。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:87`、`PreferencesPages.cs:351`。
- 失焦后状态显示“可用”或“已被其他程序占用”；新值保存后先显示“移开焦点后生效”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:355`。

### 3.3 用户自定义的存储格式与合法性校验

- 存储为 `System.Windows.Forms.Keys` 枚举的数值（`System.Text.Json` 默认枚举序列化为数字），Windows 键额外使用自定义标志位 `0x80000`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyBox.cs:12`。
- 显示格式：`KeysConverter` 输出 `Ctrl+Alt+O` 等；若带自定义 Windows 标志则加 `Win+` 前缀；`None` 显示“未设置”。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyBox.cs:19`。
- 输入规则：
  - `Tab` 不捕获，用于切换焦点。
  - 单独的 Shift/Ctrl/Alt/Win 键被吞掉，不形成绑定。
  - Backspace/Delete 清空为 `None`。
  - 捕获时若物理 Win 键按下，通过 `GetAsyncKeyState(LWin/RWin)` 加上 `WindowsModifier` 标志。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/HotkeyBox.cs:30`、`HotkeyBox.cs:13`。
  - 没有强制要求必须带修饰键，因此 F1/F3 这类单键是合法的。
- 合法性校验只有：非 `None` 时不得与其他功能完全相同；实际系统占用由注册结果判断。没有黑名单、没有系统保留键检测、没有“至少一个修饰键”的约束。
- 复制坐标热键在截图遮罩的 `ProcessCmdKey` 中与 `HotkeyDefinitions.WithWindowsKey(keyData)` 比较；不依赖全局注册。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:854`。
- `HotkeyErrors` 只存在内存中，不写入 JSON。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:112`。

## 4. 设置模型

### 4.1 存储位置、JSON 结构、迁移与保存

- 默认设置：`%APPDATA%\SnipLite\settings.json`。`AppSettings.FilePath` 会优先读取 `%APPDATA%\SnipLite\settings-location.txt` 中记录的自定义路径。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:57`。
- JSON 使用 `System.Text.Json`，仅设置 `WriteIndented=true`；属性名保持 PascalCase，枚举写数字，没有自定义转换器。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:79`。
- `Accent` 是计算属性，`HotkeyErrors` 是内存字典，二者标 `JsonIgnore`，不落盘。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:50`、`PreferenceSettings.cs:112`。
- `MouseBinding` 是 record，序列化为 `{"Modifiers":<数字>,"Gesture":<数字>}`；`CaptureRegion` 序列化为 `{"X":..,"Y":..,"Width":..,"Height":..}`，`Bounds` 标 `JsonIgnore`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:7`、`PreferenceSettings.cs:8`。
- 没有 `schemaVersion`，没有按版本迁移，没有旧字段名兼容逻辑。缺失字段使用属性初始值；未知字段被忽略；损坏文件静默回退默认值，不备份损坏文件。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:81`。
- 加载后会 `Normalized()`：夹取数值范围、校验枚举、规范化翻译语言、清理/截断最近选区、补齐空路径和字体、修复透明主题色。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:100`、`PreferenceSettings.cs:121`。
- 保存：若 `AutoBackup=true` 且旧文件存在，先复制为 `.bak`；写入 `.tmp` 后原子替换目标文件。失败写日志并 Toast。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:142`。
- 迁移配置位置：`MoveConfiguration(path)` 把当前内存设置写到新路径，再写 `settings-location.txt` 指向新路径；旧文件不删除。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:71`。
- `CopyFrom` 可整体复制所有可写且非 JsonIgnore 属性，但当前首选项“恢复默认”并未使用它。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:117`。
- 文件名模板展开支持 `$yyyy-MM-dd_HH-mm-ss$`、`$yyyy$`、`$MM$`（月）、`$dd$`、`$HH$`、`$mm$`（分）、`$ss$`；Windows 非法文件名字符替换为 `_`；空结果回退 `SnipLite`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:125`。

### 4.2 AppSettings 全部字段与默认值

以下字段分散在两个 partial 文件中。

**基础、语言、截屏外观、输出基础**

- `SaveDirectory` = `我的图片\SnipLite`（`AppSettings.cs:7`）
- `OcrLanguage` = `"zh-Hans"`（`:10`）
- `OcrEngine` = `SimdPaddle`（`:11`）
- `TranslationSourceLanguage` = `"en"`（`:12`）
- `TranslationTargetLanguage` = `"zh-CN"`（`:13`）
- `TranslationProvider` = `Bing`（`:14`）
- `MaskOpacity` = `110`（0–200，`:17`）
- `MagnifierZoom` = `6`（2–16，`:20`）
- `ShowCrosshair` = `true`（`:23`）
- `PinOpacityPercent` = `100`（10–100，`:26`）
- `CopyAfterCapture` = `true`（`:29`）
- `AutoSave` = `false`（`:32`）
- `HotkeysEnabled` = `true`（`:34`）
- `FileNamePattern` = `"SnipLite_$yyyy-MM-dd_HH-mm-ss$"`（`:37`）
- `JpegQuality` = `92`（30–100，`:39`）
- `AccentArgb` = 注解栏主题色 `#0091EA`（`AnnotationBar.cs:55`、`AppSettings.cs:42`）
- `ShowToast` = `true`（`:45`）
- `StartWithWindows` = `false`（`:48`）

**界面、托盘、放大镜**

- `DisplayLanguage` = `"zh-CN"`（`PreferenceSettings.cs:15`）
- `StartAsAdministrator` = `false`（`:16`）
- `AutoBackup` = `true`（`:17`）
- `KeepResponsive` = `true`（`:18`）
- `EnhancedTrayMenu` = `true`（`:19`）
- `LogLevel` = `"Normal"`（`:20`）
- `InterfaceFont` = `"Microsoft YaHei UI"`（`:21`）
- `InterfaceFontSize` = `9`（7–24，`:22`）
- `TrayIconStyle` = `"Auto"`（`Auto` / `Color` / `Custom`，`:23`）
- `CustomTrayIcon` = `""`（`:24`）
- `ColorHex` = `false`（`:25`）
- `ColorHideHash` = `false`（`:26`）
- `ColorUppercase` = `true`（`:27`）
- `MagnifierHints` = `true`（`:28`）
- `AutoMagnifier` = `true`（`:29`）
- `CaptureBorderWidth` = `1`（1–10，`:30`）
- `CaptureMaskColor` = 黑色 ARGB（`:31`）
- `CaptureAnchors` = `true`（`:32`）
- `CaptureAnchorColor` = 白色 ARGB（`:33`）
- `MagnifierMask` = `true`（`:34`）
- `MagnifierBorder` = `true`（`:35`）
- `MagnifierAnchors` = `false`（`:36`）
- `CaptureShortcutHints` = `true`（`:37`）

**截屏行为、历史、音效、按键动作**

- `DetectWindows` = `true`（`:38`）
- `DetectElements` = `true`（`:39`）
- `HideOnePixelHint` = `true`（`:40`）
- `CaptureCursor` = `false`（`:41`）
- `DisableCursorCapture` = `false`（`:42`）
- `ExitCaptureOnDeactivate` = `false`（`:43`）
- `HistoryRegionLimit` = `8`（0–100，`:44`）
- `CycleHistoryRegions` = `false`（`:45`）
- `HistoryImageLimit` = `20`（0–100，`:46`）
- `RecentRegions` = 空列表（`:47`）
- `CaptureSound` = `""`（`:48`）
- `SoundOnCopy` = `false`（`:49`）
- `SoundOnSave` = `false`（`:50`）
- `DisableCaptureWheel` = `false`（`:51`）
- `ConfirmEscape` = `false`（`:52`）
- `IgnoreInjectedCopy` = `true`（`:53`）
- `BlockLeftWindows` = `false`（`:54`）
- `BlockRightWindows` = `false`（`:55`）
- `DoubleClickAction` = `Copy`（`:56`）
- `DoubleClickExit` = `true`（`:57`）
- `MiddleClickAction` = `Pin`（`:58`）
- `MiddleClickExit` = `true`（`:59`）
- `EnterAction` = `Copy`（`:60`）
- `EnterExit` = `true`（`:61`）

**贴图**

- `PinShadow` = `true`（`:62`）
- `PinShadowColor` = 黑色 ARGB（`:63`）
- `PinMenuShortcuts` = `true`（`:64`）
- `PinMaxSize` = `12000`（100–20000，`:65`）
- `ThumbnailWidth` = `75`（20–1000，`:66`）
- `ThumbnailHeight` = `75`（20–1000，`:67`）
- `PinAtCapturePosition` = `true`（`:68`）
- `PinWheelZoom` = `true`（`:69`）
- `PinZoomAtCursor` = `true`（`:70`）
- `PinSmoothScaling` = `true`（`:71`）
- `ThumbnailAcceptReset` = `true`（`:72`）
- `PinTranslucentFlash` = `true`（`:73`）
- `FlashOnGroupSwitch` = `true`（`:74`）
- `HidePinsDuringFlash` = `false`（`:75`）
- `KeepOriginalOnDrag` = `true`（`:76`）
- `FlashNewPin` = `true`（`:77`）
- `ActivateNewPin` = `true`（`:78`）
- `RecoverablePins` = `1`（0–20，`:79`）

**文字转图片、输出、剪贴板**

- `TextToImage` = `true`（`:80`）
- `IgnoreHtml` = `false`（`:81`）
- `IgnoreFilePaths` = `true`（`:82`）
- `TextImageMargin` = `15`（0–200，`:83`）
- `TextImageMaxWidth` = `900`（100–12000，`:84`）
- `TextImageFont` = `"Microsoft YaHei UI"`（`:85`）
- `TextImageFontSize` = `11`（6–100，`:86`）
- `TextImageBackground` = 白色 ARGB（`:87`）
- `TextImageForeground` = 黑色 ARGB（`:88`）
- `RememberImageExtension` = `true`（`:89`）
- `LastImageExtension` = `".png"`（`:90`）
- `QuickSaveDirectory` = `桌面\SnipLite`（`:91`）
- `QuickSaveToast` = `true`（`:92`）
- `CaptureBitmapClipboard` = `true`（截屏复制时同时放 Windows Bitmap；`:93`）
- `PinBitmapClipboard` = `false`（贴图复制默认只放 PNG；`:94`）

**快捷键与鼠标绑定**

- `CaptureHotkey` = `F1`（`:95`）
- `CopyCaptureHotkey` = `None`（`:96`）
- `CustomCaptureHotkey` = `None`（`:97`）
- `PinHotkey` = `F3`（`:98`）
- `TogglePinsHotkey` = `None`（`:99`）
- `SwitchGroupHotkey` = `None`（`:100`）
- `MouseThroughHotkey` = `None`（`:101`）
- `CopyCoordinatesHotkey` = `Ctrl+Shift+C`（`:102`）
- `TranslationHotkey` = `Ctrl+Alt+T`（`:103`）
- `OcrHotkey` = `Ctrl+Alt+O`（`:104`）
- `QrHotkey` = `Ctrl+Alt+Q`（`:105`）
- `PinZoomModifiers` = `None`（`:106`）
- `PinOpacityModifiers` = `Control`（`:107`）
- `PinCloseMouse` = `None + LeftDoubleClick`（`:108`）
- `PinResetMouse` = `None + MiddleClick`（`:109`）
- `PinThumbnailMouse` = `Shift + LeftDoubleClick`（`:110`）
- `PinCopyTextMouse` = `Shift + RightClick`（`:111`）

### 4.3 首选项窗口页面与控件

窗口为自绘 Windows 11 风格，设计尺寸 960×720，侧栏 182px，固定边框、不可最大化/最小化、不显示在任务栏；Esc 关闭，Ctrl+Tab 循环切页；打开时清空焦点。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesForm.cs:10`、`PreferencesForm.cs:122`、`PreferencesForm.cs:170`。

| 顶级页 | 子页 | 控件与含义 |
|---|---|---|
| 0 常规 | 无 | 显示语言（简体中文/English）；识别引擎（本地增强 SimdPaddle / Windows 系统 OCR）；系统识别语言（zh-Hans / en-US / 跟随系统）；翻译服务（必应/Google/MyMemory/Microsoft Azure）+ 配置微软密钥；开机启动；以管理员身份开机启动；自动备份配置文件；保持快速响应；增强版托盘菜单；日志级别（Off/Error/Normal/Debug）；打开日志文件；配置文件路径 + 打开所在文件夹/打开/更改。`PreferencesPages.cs:87` |
| 1 界面 | 常规 | 界面字体与字号；主题颜色；托盘图标（自动/彩色/自定义）；选择图标文件（ico/png/bmp）并预览。`PreferencesPages.cs:213` |
| 1 界面 | 放大镜 | 颜色值格式 RGB/HEX；隐藏 #；HEX 大写；显示操作提示；选区前自动显示放大镜；放大镜倍数 2–16。`PreferencesPages.cs:233` |
| 2 截屏 | 显示 | 边框宽度 1–10；遮罩颜色；遮罩不透明度 0–200；显示锚点；锚点描边颜色；放大镜中显示遮罩/边框/锚点；全屏十字线；快捷键提示。`PreferencesPages.cs:242` |
| 2 截屏 | 行为 | 自动检测窗口；隐藏 1×1 提示；自动检测界面元素；捕捉鼠标指针；完全禁用指针捕捉；其他程序窗口激活时退出截屏；最大历史截屏区域数 0–100；循环历史区域；最大历史记录数 0–100；截图后自动复制；WAV 音效文件 + 试听；复制时播放音效；快速保存时播放音效。`PreferencesPages.cs:252` |
| 2 截屏 | 按键 | 禁用鼠标滚轮；Esc 确认对话框；忽略其他程序模拟的复制；屏蔽左/右 Win 键；左键双击/中键单击/回车键各自动作（复制/贴图/快速保存/无操作）+ 是否随后退出截屏。`PreferencesPages.cs:281` |
| 3 贴图 | 显示 | 窗口阴影；阴影颜色；右键菜单显示助记键；默认不透明度 10–100%；最大窗口尺寸；快速缩略图宽/高。`PreferencesPages.cs:291` |
| 3 贴图 | 行为 | 使用截屏位置；滚轮缩放；以指针为中心缩放；平滑缩放；缩略图接受重置；闪烁时半透明；切换分组时闪烁；闪烁时贴图键隐藏全部；拖放时保留原始图；新贴图闪烁；新贴图激活；可恢复贴图数 0–20。`PreferencesPages.cs:300` |
| 3 贴图 | 转换 | 文字转图片；总是忽略 HTML；不把文件路径转成贴图；页边距；最大宽度；字体；背景色；文本色；预览文字贴图。`PreferencesPages.cs:312` |
| 4 输出 | 文件 | JPEG 质量 30–100；文件名模板 + 实时预览；记住上一次扩展名；快速保存通知；快速保存路径；自动保存；自动保存路径。`PreferencesPages.cs:326` |
| 4 输出 | 剪贴板 | 截屏时同时复制 Windows Bitmap；贴图时同时复制 Windows Bitmap。`PreferencesPages.cs:338` |
| 5 控制 | 全局快捷键 | 启用全局快捷键；11 个热键输入框 + 状态提示。`PreferencesPages.cs:344` |
| 5 控制 | 鼠标 | 贴图缩放修饰键（无/Ctrl/Alt/Shift/Ctrl+Shift/Ctrl+Alt）；透明度修饰键；关闭/重置/缩略图/复制文本四组“修饰键 + 手势”绑定。`PreferencesPages.cs:383` |
| 6 更新 | 无 | 当前版本；发布版本链接；检查更新；下载安装包（检查到新版本后才可用）；更新状态。`PreferencesForm.cs:372` |
| 7 关于 | 无 | 程序版本；程序文件路径；运行环境 `.NET 10 · WinForms`；识别引擎；GitHub 项目；问题反馈；开源许可证（打开 LicenseNotices）；本地处理说明。`PreferencesForm.cs:431` |

- 修改即时保存，没有“确定/取消”：`Change/Set` 调用 `_s.Save()` 并触发 `Applied`，托盘据此重建图标/菜单/热键/贴图菜单。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesForm.cs:498`、`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:28`。
- 首选项窗口是 `Show()` 的非模态窗口；`Applied` 事件驱动托盘即时应用。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:85`。
- “恢复默认”只重置当前页/当前子页实际创建过的字段（`_sectionProperties`），不是全部设置；在“常规”页时还会尝试应用默认的开机启动状态。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesForm.cs:522`。
- 字体/颜色/文件夹/下拉框均为自绘控件；文件夹选择使用 `FolderBrowserDialog`，配置迁移使用 `SaveFileDialog`，颜色使用 `ColorDialog`，字体使用 `FontDialog`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:41`、`PreferencesPages.cs:74`。
- 微软翻译密钥使用 Windows DPAPI（当前用户）加密保存到 `%LOCALAPPDATA%\SnipLite\microsoft-translator.dat`；留空密钥保存会删除文件。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/MicrosoftTranslatorCredentials.cs:11`、`MicrosoftTranslatorCredentials.cs:35`。

## 5. 输出与历史、日志、更新

### 5.1 剪贴板

- 复制图像时构造 `DataObject`：自定义格式 `"PNG"`（`MemoryStream`）始终存在；`CaptureBitmapClipboard=true` 时额外放 `DataFormats.Bitmap`。贴图复制则由 `PinBitmapClipboard` 控制，默认只放 PNG。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:7`。
- `Clipboard.SetDataObject(data, true, 5, 80)`：复制=true，最多重试 5 次、间隔 80ms。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:15`。
- 从剪贴板取图优先读 `"PNG"` 流，再退回 `Clipboard.GetImage()`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:21`。
- 文字转图片只在贴图流程中生成位图，不写回剪贴板。

### 5.2 保存文件

- 保存目录：
  - 自动保存：`SaveDirectory`，默认 `图片\SnipLite`。
  - 快速保存：`QuickSaveDirectory`，默认 `桌面\SnipLite`。
- 文件名：`Services.ImageFileName` 先展开模板；若模板本身已带 `.png/.jpg/.jpeg`，用目标扩展名替换，否则追加扩展名。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:28`。
- 同名冲突：从 `(2)` 开始递增，形如 `name (2).png`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:34`。
- PNG 直接保存；JPEG 使用 `JpegQuality` 夹在 30–100；默认 GDI+ 编码器质量是 75，但这里显式指定。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Services.cs:103`。
- 截屏结果处理顺序：先加入历史、更新并保存最近选区；若 `AutoSave=true` 先写入自动保存目录；然后按结果执行贴图 / 快速保存 / 复制。因此“自动保存 + 贴图”“自动保存 + 快速保存”“自动保存 + 复制”可以同时发生。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:165`。
- 贴图结果优先于复制；`--capture` 的普通截屏默认 `CopyAfterCapture=true`，所以按 Enter/复制会复制；快速保存分支不会再复制。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:174`。
- 保存音效只在快速保存且 `SoundOnSave`、或复制且 `SoundOnCopy` 时播放；WAV 通过 `SoundPlayer.PlaySync` 在后台任务播放。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OutputServices.cs:43`。

### 5.3 截图历史

- `CaptureHistory` 是会话内内存列表，元素为 `PNG 字节 + Rectangle Bounds + DateTime`，最新在前；标签格式 `HH:mm:ss  W × H`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureHistory.cs:7`。
- 每次截屏结果（包括贴图/快速保存/复制）都会先加入历史。`HistoryImageLimit=0` 时清空并停止记录；默认 20，最大 100。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureHistory.cs:14`、`PreferenceSettings.cs:46`。
- 最近截屏区域 `RecentRegions` 会持久化到设置 JSON，默认最多 8 个；每次截屏去重后插到最前。用于“自定义截屏”初始值和截屏中 Tab/Shift+Tab 循环。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:171`、`CaptureForm.cs:1263`。
- `CycleHistoryRegions=true` 时循环，否则到两端停止。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1267`。
- 从托盘历史子菜单点击某条会直接贴图，并保留原截屏区域位置（若 `PinAtCapturePosition=true`）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:61`。
- 截图图片历史、已关闭贴图、贴图分组均只在当前会话有效；退出不恢复。README 也明确说明。`/Users/lusheng/Documents/开源工具/SnipLite/README.md:114`。

### 5.4 日志与异常

- 应用日志：`%LOCALAPPDATA%\SnipLite\app.log`；超过 2,000,000 字节轮转为 `app.log.old`（覆盖旧 .old）。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppLog.cs:6`。
- 级别：`Off` 全关；`Error` 只记录带异常；`Normal` 记录普通消息和异常；`Debug` 记录带 `debug:true` 的消息。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppLog.cs:9`。
- 未处理异常日志：`%TEMP%\SnipLite\error.log`，包含时间、版本、exe 路径和完整异常；同时错误 Toast 4 秒。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Program.cs:59`。
- `AppLog.Level` 由设置应用时同步；Toast 总开关由 `ShowToast` 控制，但 `Toast.Error` 不受通知开关影响。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:93`、`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Toast.cs:84`。

### 5.5 更新检查

- 不使用 GitHub API，而是 `GET <仓库>/releases/latest`，依赖重定向后的最终 URL 形如 `.../releases/tag/vX.Y.Z`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/ReleaseUpdates.cs:10`、`AppInfo.cs:7`。
- 版本解析要求 tag 以 `v` 开头、`Version.TryParse` 成功且 `Build >= 0`；否则抛 `InvalidDataException`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/ReleaseUpdates.cs:19`。
- 比较逻辑：当前版本取程序集信息版本并按 `-` 截断；`latest > current`，或 `latest == current && 当前版本含 '-'`（预发布）时认为有新版本。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesForm.cs:396`。
- 下载：`releases/download/{tag}/SHA256SUMS.txt`，按空格分成两段找到目标文件名，校验 64 位 SHA-256；下载到 `.part`，校验后移动到目标；10 分钟超时。目标文件名固定为 `SnipLite-{tag 去掉 v}-win-x64-setup.exe`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/ReleaseUpdates.cs:24`、`PreferencesForm.cs:412`。
- 版本号来自 `AssemblyInformationalVersion`，当前 csproj 为 `0.3.11`。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppInfo.cs:11`、`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SnipLite.csproj:16`。

## 6. Windows 特有 API / 依赖与 macOS 原生方案

### 6.1 平台 API 对照

| Windows 实现 | 关键位置 | macOS 原生方案 |
|---|---|---|
| WinForms `ApplicationContext` + `NotifyIcon` | `TrayContext.cs:3`、`:17` | `NSApplication` + `NSStatusItem`；`LSUIElement=YES` / `setActivationPolicy(.accessory)` 实现无 Dock 图标的菜单栏应用 |
| 命名互斥体 `Global\...` | `Program.cs:18` | `NSRunningApplication` 检测、`flock` 文件锁、`NSDistributedNotificationCenter`；普通 `.app` 双击通常天然单实例，但 `open -n` 仍可多开，需要自行加锁 |
| `--capture/--prefs/--menu` 命令行参数 | `Program.cs:40` | `CommandLine.arguments`；二次启动传参可用 URL Scheme（`CFBundleURLTypes`）或 Distributed Notification |
| `HKCU\...\Run` + 任务计划 COM | `Startup.cs:6`、`Startup.cs:77` | `SMAppService.mainApp.register()/unregister()`（macOS 13+）；旧系统用 LaunchAgent；不需要也不应模拟“管理员开机启动” |
| `RegisterHotKey` / `WM_HOTKEY` | `HotkeyHost.cs:28`、`:47` | Carbon `RegisterEventHotKey` + `InstallEventHandler`（无需辅助功能权限，最接近原行为）；或 `NSEvent.addGlobalMonitorForEvents`（需要输入监控/辅助功能权限，且不能吞键） |
| `Keys` 枚举 / Win 键 | `PreferenceSettings.cs:95`、`HotkeyBox.cs:12` | 建议存逻辑键名和修饰键集合；Win → Command。F1/F3 在 Mac 常被系统占用且需按 Fn，应迁移默认键或让用户改 |
| `Form.TopMost`、`SetWindowPos(HWND_TOPMOST)` | `PinForm.cs:40`、`:136` | `NSWindow.level = .floating` 或 `.statusBar`；设置 `collectionBehavior` |
| 无边框、无任务栏、`ShowWithoutActivation` | `PinForm.cs:39`、`:55` | `.borderless` 或 `NSPanel` + `.nonactivatingPanel`；`canBecomeKey` 按交互需要设置 |
| `WS_EX_TRANSPARENT` 鼠标穿透 | `PinForm.cs:243` | `NSWindow.ignoresMouseEvents = true`（同时处理 content view） |
| `Form.Opacity` | `PinForm.cs:41`、`:213` | `NSWindow.alphaValue` |
| 独立 `UpdateLayeredWindow` 阴影窗口 | `PinShadowWindow.cs:41` | 不需要独立窗口；用单窗口 `hasShadow=true` 或 `CALayer.shadowColor/Opacity/Radius/Offset/Path`。若追求原逐像素高斯阴影，可自绘 `CALayer` |
| `GetWindowLongPtr/SetWindowLongPtr` 扩展样式 | `PinForm.cs:243` | 对应 `NSWindow` 属性，无需 Win32 位操作 |
| GDI+ `Bitmap` / `Graphics` | `PinForm.cs:158`、`Services.cs:103` | Core Graphics / Core Image / ImageIO；`CGImage`、`NSBitmapImageRep`、`CGImageDestination` |
| `Clipboard` + 自定义 `"PNG"` / `DataFormats.Bitmap` | `OutputServices.cs:7` | `NSPasteboard.general`；`UTType.png`、`UTType.tiff`；`clearContents()` 后写数据；用 `changeCount` 代替剪贴板序列号 |
| `GetClipboardSequenceNumber` | `TrayContext.cs:255` | `NSPasteboard.general.changeCount` |
| `DoDragDrop(FileDrop)` | `PinForm.cs:193` | `NSDraggingSession` + `NSPasteboardItem` 的 `.fileURL`；临时文件放 `NSTemporaryDirectory()` |
| `SystemInformation.VirtualScreen`、`GetCursorPos` | `PinForm.cs:154`、`Win32.cs:31` | `NSScreen.screens` 并集 + `NSEvent.mouseLocation` / `CGEvent`；注意 Cocoa 全局坐标原点与 y 轴方向 |
| `DeviceDpi/96` 手动缩放 | `PreferencesForm.cs:126`、`PinForm.cs:144` | `backingScaleFactor`；Swift 使用 points，截图像素用 `convertToBacking` |
| `SaveFileDialog/OpenFileDialog/FolderBrowserDialog/ColorDialog/FontDialog` | `PreferencesPages.cs:41`、`:74`、`PreferencesForm.cs:412` | `NSSavePanel`、`NSOpenPanel`、`NSColorPanel`、`NSFontPanel`；用 `UTType` 限制类型 |
| `SoundPlayer` WAV | `OutputServices.cs:43` | `NSSound(contentsOf:byReference:)` 或 AVAudioPlayer |
| 注册表主题 + `DwmSetWindowAttribute` + 主题广播 | `AppTheme.cs:35`、`:103`、`:119` | `NSApp.effectiveAppearance` / `NSAppearance`；KVO 监听外观变化；`NSColor` 语义色；状态栏使用 template image 自动适配 |
| `explorer.exe /select`、`Process.Start(url)` | `PreferencesForm.cs:775`、`:455` | `NSWorkspace.shared.activateFileViewerSelecting([url])`；`NSWorkspace.shared.open(url)` |
| `Windows.Media.Ocr` | `Services.cs:42` | Vision `VNRecognizeTextRequest`（本地、支持 zh-Hans/en-US，返回 bounding box） |
| SimdPaddleOCR + PP-OCRv6 | `SimdOcr.cs:11` | 转 Core ML / ONNX Runtime；或直接用 Vision，行为需重新验收 |
| ZXing.Net.Windows.Compatibility | `Services.cs:81` | Vision `VNDetectBarcodesRequest`；或 ZXing-Cpp Swift 包 |
| Windows 截图 `CopyFromScreen` | `CaptureForm.cs:141` | ScreenCaptureKit（macOS 12.3+）/ CGWindowList；首次需“屏幕录制”TCC 权限 |
| Win32 `EnumWindows`、MSAA `oleacc`、UIA | `DesktopTargets.cs:149` 起 | Accessibility API（`AXUIElement`）+ `CGWindowListCopyWindowInfo`；需要“辅助功能”权限，窗口内容/元素层级和 Windows 差异很大 |
| IME `imm32` | `ImeSink.cs:26` | `NSTextInputClient` / 系统输入法 |
| DPAPI `ProtectedData` | `MicrosoftTranslatorCredentials.cs:25` | Keychain（`SecItemAdd` / `kSecClassGenericPassword`） |
| Inno Setup + `.exe` 更新 | `ReleaseUpdates.cs`、`docs/DEVELOPMENT.md:74` | `.app`/`.dmg`/`.pkg` + Developer ID 签名 + 公证；更新建议 Sparkle 2（appcast + EdDSA）或自行下载 DMG + CryptoKit SHA-256 |
| `app.manifest` supportedOS / PerMonitorV2 | `app.manifest:5`、`SnipLite.csproj:10` | `Info.plist` 的 `LSMinimumSystemVersion`、`NSHighResolutionCapable`、`LSUIElement`、`CFBundleURLTypes` |

### 6.2 依赖层面的迁移

- 原项目依赖：.NET 10 Windows、WinForms、WPF（`UseWPF=true`）、GDI+、WinRT `Windows.Media.Ocr`、Sdcb.SimdPaddleOCR（原生 x64 模型）、ZXing.Net Windows Compatibility。`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SnipLite.csproj:4`、`:28`。
- macOS 建议栈：Swift + AppKit/SwiftUI；截图 ScreenCaptureKit；OCR Vision；条码 Vision；图像 Core Graphics/ImageIO；全局热键 Carbon；开机启动 SMAppService；更新 Sparkle 2；设置 Codable + JSON（或 UserDefaults）。
- 权限是移植的主要差异：屏幕录制、辅助功能、输入监控、桌面/图片文件夹访问都可能触发 TCC 授权。若做 App Sandbox，还需要为用户选择的保存目录保存 security-scoped bookmark；原 Windows 程序无此概念。
- 不建议照搬“管理员开机启动”；macOS 没有等价的、无需用户交互的 Run-as-admin 登录项，强行实现会引入 privileged helper 和签名/公证复杂度。

## 7. 移植时最容易遗漏的行为细节

1. **F3 的“遮罩优先”语义**：只要截图遮罩可见，F3 一律交给遮罩贴当前选区，即使尚未框选也消费按键，绝不贴旧剪贴板。`TrayContext.cs:228`、`CaptureForm.cs:1651`。
2. **剪贴板序列号去重**：连续按 F3 时，若剪贴板没变化，不重复贴同一内容，而是恢复隐藏贴图、激活已有贴图或恢复最近关闭的贴图。`TrayContext.cs:202`。
3. **恢复优先级**：隐藏/闪烁贴图 → 剪贴板序列检查 → 剪贴板图片 → 文字转图片 → 最近关闭贴图 → 截图历史最新 → Toast。顺序改变会显著改变用户体验。
4. **文字转图片是贴图专用回退**：不写剪贴板、不进截图历史、不自动保存；HTML 格式可保留基础样式；文件路径默认忽略。`TrayContext.cs:210`、`TextImageRenderer.cs:10`。
5. **分组是全局静态的 1–3 三组**：新贴图继承当前组；“移动到分组”不是移动窗口位置，而是改变可见性并可能立即隐藏。`PinForm.cs:74`、`:293`。
6. **隐藏贴图仍留在 `Open` 列表**：`OpenCount` 包含隐藏项；`ToggleAll` 的“隐藏”会隐藏所有组，但“显示”只显示当前组。`PinForm.cs:32`、`:67`。
7. **恢复最近关闭的贴图会丢失状态**：只保留 PNG、左上角、组号；缩放、透明度、缩略图、鼠标穿透全部丢失；恢复后的中心计算使用原图尺寸而不是当前窗口尺寸，可能有偏移。`PinForm.cs:101`。
8. **闪烁与隐藏的交互**：新贴图默认闪烁；`PinTranslucentFlash` 降低透明度；`HidePinsDuringFlash` 打开时，闪烁期间按贴图键会隐藏全部贴图而不是贴新图。`PinForm.cs:47`、`:90`。
9. **阴影是独立置顶窗口**：不在导出图片中，但会进入后续桌面截图；贴图隐藏时阴影隐藏；拖动时只移动阴影，松开才重算。`PinShadowWindow.cs:41`、`PinForm.cs:139`。
10. **鼠标穿透只能靠全局快捷键关闭**：开启后窗口不再接收鼠标事件；状态不持久化；菜单项没有勾选状态，仅 Toast 提示。`PinForm.cs:243`。
11. **默认鼠标手势不是“右键关闭”**：左键双击关闭、中键重置、Shift+左键双击缩略图、Shift+右键 OCR；修饰键要求完全相等。`PreferenceSettings.cs:108`、`PinForm.cs:166`。
12. **Alt+拖动导出原始全分辨率 PNG**：不是当前缩放后的画面；临时文件不清理；默认 `KeepOriginalOnDrag=true`，拖放成功后原贴图保留。`PinForm.cs:186`。
13. **贴图没有旋转**：不要因为“贴图工具常见功能”而误加；原实现只支持缩放/透明度/位置。
14. **缩略图可能放大图片**：`min(75/w, 75/h)` 对小图大于 1；`Ctrl+0` 重置受 `ThumbnailAcceptReset` 控制。`PinForm.cs:237`。
15. **截屏输出链可以叠加**：自动保存先执行；贴图/快速保存/复制按分支互斥，但自动保存可与任一分支叠加；最近选区每次截屏都会保存。`TrayContext.cs:165`。
16. **贴图优先于复制**：如果结果要求贴图，即使 `CopyAfterCapture=true` 也不会再复制；快速保存分支也不会再复制。`TrayContext.cs:175`。
17. **“恢复默认”只重置当前页/子页**：不是全局重置；`CopyFrom` 未被使用；在常规页还会尝试改开机启动。`PreferencesForm.cs:522`。
18. **设置即时保存、无确定按钮**：每次控件变化都写盘并通知托盘；字体/文件夹/下拉框/颜色都是即时生效。端口若改成“确定/取消”会改变交互模型。
19. **开机启动设置只是镜像**：启动时不查询真实注册表状态；`Startup.IsEnabled` 未使用；管理员任务存在时任何开关都会提权重建任务。`Startup.cs:12`、`Startup.cs:33`。
20. **热键冲突是部分成功**：逐个注册，失败的记录错误并 Toast，其他键仍可用；内部重复只在 UI 精确比较完整 `Keys` 值时拒绝；`CopyCoordinatesHotkey` 从不全局注册。`TrayContext.cs:129`、`PreferencesPages.cs:358`。
21. **热键编辑期间暂停所有注册**：获得焦点即禁用全局热键，失焦才重新注册；因此“移开焦点后生效”。`TrayContext.cs:87`。
22. **菜单重建签名不含主题色/托盘样式**：换主题色不会重建菜单，只更新图标；语言/字体/增强菜单/热键变化才重建；Tooltip 截断 63 字符。`TrayContext.cs:97`。
23. **“帮助”不是帮助文档**：托盘“帮助”打开首选项第 7 页“关于”；“首选项…”打开第 0 页；`--prefs:N` 夹在 0–7。`TrayContext.cs:74`。
24. **异常处理刻意避免模态框**：截图遮罩期间弹模态异常框会破坏交互；改为写临时错误日志 + 非激活 Toast。端口应保留“绝不阻塞截图”的原则。`Program.cs:31`。
25. **主题分两套**：应用窗口跟随 `AppsUseLightTheme`，托盘 Auto 图标跟随任务栏 `SystemUsesLightTheme`；Mac 菜单栏与窗口外观也可能不同，template image 应自动适配。`AppTheme.cs:41`、`TrayIcons.cs:24`。
26. **英文界面是部分翻译**：`UiText` 只覆盖固定词典，动态文本和大量控件仍是中文；不要指望现有英文模式完整。`UiText.cs:5`。
27. **历史/贴图/恢复数据不落盘**：只有 `RecentRegions` 和设置持久化；截图图片历史、已关闭贴图、当前打开贴图都在内存。`README.md:114`、`CaptureHistory.cs:5`。
28. **默认快捷键在 macOS 上的冲突**：F1/F3 常被系统功能占用且需要 Fn；`Ctrl+Alt+O/Q/T` 对应 Control+Option；Cmd 才是 Windows 键的对应物。建议默认改为 `⌥⌘1/⌥⌘2/⌥⌘O/⌥⌘Q`，同时提供旧键位迁移，否则首启热键注册大概率失败。`PreferenceSettings.cs:95`。
29. **多显示器/Retina 坐标**：原实现全程用物理像素和虚拟屏幕并集；Mac 的 `NSScreen.frame` 是 points，`CGEvent` 是全局像素坐标，必须做 y 轴翻转和 per-screen 转换，否则贴图会落在错误的显示器/位置。`PinForm.cs:152`、`Win32.cs:27`。
30. **文件系统权限**：默认保存到 `~/Pictures/SnipLite` 和 `~/Desktop/SnipLite`，macOS 会触发“文件与文件夹”TCC 授权；应保留用户可改目录，并在沙盒模式下使用 security-scoped bookmark。`AppSettings.cs:7`、`PreferenceSettings.cs:91`。
31. **翻译密钥与设置编码**：Windows 设置 JSON 直接带枚举数字和 ARGB 整数，不能原样当 macOS 设置格式；建议新增 `schemaVersion`、字符串枚举/逻辑键名，并把 DPAPI 换成 Keychain。`AppSettings.cs:79`、`MicrosoftTranslatorCredentials.cs:25`。
32. **更新链路完全不同**：不要复用 GitHub `releases/latest` 重定向 + Windows installer + SHA256SUMS 的逻辑；Mac 应使用 Sparkle appcast 或 GitHub Releases 的 dmg/pkg，并做签名/公证校验。`ReleaseUpdates.cs:10`、`PreferencesForm.cs:412`。
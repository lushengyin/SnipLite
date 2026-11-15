# SnipLite 截图核心代码探索报告

范围说明：除指定文件外，还读了 `TrayContext.cs`、`CaptureTranslation.cs`、`TranslationOverlay.cs`、`Services.cs`、`OcrSelection.cs`、`PinForm.cs`、`AppSettings.cs`、`PreferenceSettings.cs`、`HotkeyHost.cs`，因为输出、OCR、贴图、全局快捷键不在 CaptureForm 内。

---

## 1. 截图会话的完整交互流程

### 1.1 启动链路

- 托盘/热键触发 `TrayContext.StartCapture` (`src/SnipLite/TrayContext.cs:148`)：取 `SystemInformation.VirtualScreen`（把所有显示器合并成一个矩形，允许负坐标），构造 `CaptureForm(virtual, mode, settings, preset)`，`Show()` 非模态。
- 四种模式：`Snip / Ocr / Translation / Qr` (`src/SnipLite/CaptureForm.cs:6-12`)。
- 全局热键默认：截屏 `F1`、贴图 `F3`、截图翻译 `Ctrl+Alt+T`、OCR `Ctrl+Alt+O`、二维码 `Ctrl+Alt+Q` (`src/SnipLite/PreferenceSettings.cs:95-105`)，通过 `RegisterHotKey` 注册 (`src/SnipLite/HotkeyHost.cs:28-36`)。
- 命令行 `--capture` 可绕过全局热键直接开截 (`src/SnipLite/Program.cs:53-56`)。

### 1.2 冻结桌面 + 全屏遮罩

- 构造时先抓屏：新建 `Format32bppPArgb` 的虚拟屏大位图，`Graphics.CopyFromScreen` 一次性复制整个虚拟桌面；若开启“截图包含光标”，再用 `Win32.DrawCursor` 把系统光标画进去 (`CaptureForm.cs:137-143`, `Win32.cs:43-50`)。注意抓屏发生在窗口显示之前，避免拍到自己。
- 窗口无边框、`TopMost`、`ShowInTaskbar=false`，`OnShown` 里用 `SetWindowPos` 强制铺满虚拟屏 (`CaptureForm.cs:145-153, 168-174`)。
- 绘制：先 1:1 画冻结截图，再画半透明遮罩，但把“选区或 hover 目标”挖空。挖空不是用 Region，而是画四条边带，减少 4K 下的开销 (`CaptureForm.cs:229-254`)。
- 无选区时：可画整屏十字线 + 鼠标处窗口/控件高亮框 + 底部快捷键提示条 (`CaptureForm.cs:298-321`)。
- 十字线有两种实现：设置项 `ShowCrosshair` 为真时先用两个“细条窗口”做真正的系统级十字线（避免每帧重绘 4K 遮罩，`CaptureCrosshair.cs:4-80`）；否则直接在 overlay 里画 1px 线 (`CaptureForm.cs:302-307`)。`CaptureCrosshair` 用 `Region` 把顶层窗口裁成 1 物理像素，并取消 DPI 变化 (`CaptureCrosshair.cs:17-40`)。

### 1.3 十字线 / 自动选区

- 鼠标未按下时，`UpdateTarget()` 每 60ms 解析一次指针下的窗口/控件，绘制 `_hoverTarget` 高亮框 (`CaptureForm.cs:73, 156-159, 1193-1227, 308-312`)。
- 鼠标按下左键且当前无选区：
  - 先立刻重新解析一次目标（防止点击早于下一次 timer），记录 `_pressTarget = _hoverTarget`（仅当指针在目标内）；
  - 进入 `_dragging=true`、`_dragMode=1`，清空选区、所有标注、撤销/重做栈，并把工具复位为 `None` (`CaptureForm.cs:618-635`)。
  - 注意这是一条重要规则：**重新开始框选会丢弃此前所有标注**。
- 拖动期间 `_selection = Normalize(anchor, cursor)`，只重绘受影响区域 (`CaptureForm.cs:695-699, 2065-2093`)。
- 松开时 (`CaptureForm.cs:782-803`)：
  - 若宽或高 < 3px，视为“单击选择目标”，`_selection = _pressTarget`；目标为空则没有选区；
  - 否则 `_hasSelection=true`，进入标注阶段；
  - 若当前是 OCR / 翻译 / 二维码模式，立即自动执行对应识别/翻译。
- 预设区域：`CaptureForm` 收到 `preset`（自定义区域对话框或托盘自定义区域）时直接形成选区并偏移到虚拟屏局部坐标 (`CaptureForm.cs:178-183`, `CaptureRegionForm.cs:6`, `TrayContext.cs:140-147`)。
- `Tab` / `Shift+Tab` 循环最近使用过的选区 (`CaptureForm.cs:944, 1261-1272`)，历史来自 `settings.RecentRegions`。
- `Ctrl+A` 选择整个虚拟屏 (`CaptureForm.cs:978-985`)。

### 1.4 选区确定后的调整

- 8 个控制点：四角 + 四边中点；命中半径 `8*Ui` (`CaptureForm.cs:166, 466-479, 2015-2028`)。`_dragMode >= 3` 表示正在拖第 `_dragMode-3` 个锚点 (`CaptureForm.cs:598-607, 2030-2059`)。
- 选区内部拖动：`_dragMode=2`，整体平移且被夹在虚拟屏内 (`CaptureForm.cs:609-615, 700-712`)。
- 鼠标在选区外左键按下：等同于开始一个新选区，并清空标注 (`CaptureForm.cs:618-635`)。
- 右键：**立即取消整个截图**，没有右键菜单 (`CaptureForm.cs:486-491`)。
- 中键：执行 `MiddleClickAction`（默认贴图），`MiddleClickExit` 默认 true (`CaptureForm.cs:492`, `PreferenceSettings.cs:58-59`)。
- 双击选区内部（非工具栏、非文字编辑）：执行 `DoubleClickAction`（默认复制）(`CaptureForm.cs:833-850`, `PreferenceSettings.cs:56-57`)。

### 1.5 标注编辑阶段

- 工具通过工具栏或单键 `R/E/A/P/H/X/T/M` 切换；再次按同一工具会关闭工具 (`CaptureForm.cs:987-994, 1039-1047`)。
- 在选区内按下左键且工具有效：创建 `Shape`，`Shape.Create` 后按工具补 `Fill / ArrowStyle / MosaicBlock / Rectangular / Opacity`，宽度乘以 `Ui`，进入 `_dragMode=1` (`CaptureForm.cs:566-596`)。
- 文字工具：按下即创建 1x1 隐藏 `ImeSink`，真实文字、光标、IME 组字串全部由 overlay 自己绘制 (`CaptureForm.cs:1686-1760`，详见第 4、7 节)。
- 文字对象可再次点击编辑、拖动移动、拖右下角把手改字号；这些操作各自用快照实现撤销 (`CaptureForm.cs:527-564, 651-674, 741-759`)。
- `Esc` 的层级顺序 (`CaptureForm.cs:902-935`)：先取消文字缩放的临时状态 → 取消文字移动 → 取消正在画/未提交的形状 → 取消选中文字 → 关闭当前工具 → （可选确认后）取消整次截图。
- `Enter` 默认执行 `EnterAction`（默认复制）并退出；翻译/OCR/QR 模式下改为执行识别 (`CaptureForm.cs:937-943`)。
- `Ctrl+Z` 撤销、`Ctrl+Y` / `Ctrl+Shift+Z` 重做 (`CaptureForm.cs:954-964`)。
- `Ctrl+C` 复制输出、`Ctrl+S` 另存为、`Ctrl+Shift+S` 快速保存（不退出）、`Ctrl+T` 贴图 (`CaptureForm.cs:945-953, 966-976`)。
- `Alt` 按住强制显示放大镜 (`CaptureForm.cs:1016-1021, 1026-1032`)；`Shift` 在放大镜可见时切换 RGB/HEX (`CaptureForm.cs:1009-1015`)；`C` 复制光标处颜色 (`CaptureForm.cs:996-1002`)。
- 滚轮：放大镜可见时改放大倍率 2–16；否则文字工具下改字号 4–200 (`CaptureForm.cs:1273-1284`)。
- 失焦：设置 `ExitCaptureOnDeactivate` 为真时退出，但会先排除工具栏菜单/子窗口仍打开的情况 (`CaptureForm.cs:1285-1294`)。

### 1.6 输出路径

- `Copy()`：渲染合成图 → `CaptureResult{Image, Bounds(屏幕物理坐标), Pin}` → `Finish` → `Done` 事件 (`CaptureForm.cs:1586-1600, 1661-1665`)。
- `ExecuteAction` 支持 `KeepOpen=!exit`：某些出图动作可以复制后**不关闭遮罩**继续标注 (`CaptureForm.cs:1295-1306`)。
- 实际输出在 `TrayContext.HandleResult` (`TrayContext.cs:165-192`)：
  1. 写入内存截图历史（PNG 字节 + 区域 + 时间，`CaptureHistory.cs:14-21`）；
  2. 更新最近选区并保存设置；
  3. 可选自动保存到目录；
  4. Pin → 打开 `PinForm`；
  5. QuickSave → 保存到快速保存目录；
  6. Copy → 写剪贴板 + Toast + 可选音效。
- 剪贴板同时写 `"PNG"` 流和（可选）`DataFormats.Bitmap`，并用重试参数 `Clipboard.SetDataObject(data, true, 5, 80)` (`OutputServices.cs:7-20`)。

### 1.7 状态机速览

核心不是一个枚举，而是多个布尔/整数组合 (`CaptureForm.cs:87-105`)：

| 状态 | 代表字段 | 含义 |
|---|---|---|
| 未选区 | `_hasSelection=false`, `_dragging=false` | hover 检测、十字线、放大镜 |
| 正在拉选区 | `_dragging=true`, `_dragMode=1` | 橡皮筋框选 |
| 已有选区空闲 | `_hasSelection=true`, `_dragMode=0` | 工具栏、锚点、工具绘制 |
| 平移选区 | `_dragMode=2` | 选区整体移动 |
| 缩放选区 | `_dragMode>=3` | 8 个锚点 |
| 画形状 | `_current!=null && _dragMode==1` | 尚未提交的 Shape |
| 文字编辑 | `_ime!=null` | 隐藏输入框 + 自绘文字 |
| OCR 结果模式 | `_ocrMode=true` / `_recognitionBusy` | 拦截绝大多数按键，只允许选字/复制/Esc |
| 翻译面板 | `_translationPanel.Visible` | 附加在工具栏下方 |

---

## 2. 标注数据模型

### 2.1 类型与字段

- 工具枚举 `ToolKind`：`None/Rectangle/Ellipse/Arrow/Pen/Marker/Text/Mosaic/Eraser` (`Annotation.cs:7-18`)。
- 箭头样式枚举 7 种：`Solid/Open/Outline/Double/Line/TaperedSolid/TaperedOutline` (`Annotation.cs:20`)。
- 抽象基类 `Shape`：`Color`（默认红）、`Width`、`Fill`；抽象 `Render(Graphics, Bitmap screen)`、`DragTo(Point)`、`SetStart(Point)`、`IsEmpty`、`Clone()` (`Annotation.cs:22-56`)。
- 子类字段：
  - `RectShape/EllipseShape`：`Rect` + 私有 `_start` (`Annotation.cs:58-110`)。
  - `ArrowShape`：`Start/End/Style` (`Annotation.cs:112-126`)。
  - `PenShape`：`List<Point> Points`，相邻点距离 <2px 不记录 (`Annotation.cs:204-223`)。
  - `TextShape`：`At/Text/FontSize/FontFamily/Bold/Italic` (`Annotation.cs:240-247`)。
  - `MosaicShape`：`Block`（物理像素块大小），继承 `StrokeAreaShape` (`Annotation.cs:286-288`)。
  - `StrokeAreaShape`：`Rect/Rectangular/Points`，矩形或涂抹路径 (`Annotation.cs:346-376`)。
  - `EraserShape`、`MarkerShape`（`Opacity` 默认 50）(`Annotation.cs:378-404`)。
- **没有任何序列化**：Shape 只存在于内存列表 `_shapes` (`CaptureForm.cs:44`)。历史/最近区域只持久化 PNG 字节和矩形 (`CaptureHistory.cs:5-11`, `PreferenceSettings.cs:8`)；若要移植成 Swift，建议给 Shape 加 `Codable` 判别联合。

### 2.2 绘制与命中测试

- 统一渲染入口 `AnnotationRenderer.RenderLayer`：创建与选区 crop 等大的透明 `PArgb` 位图，清空透明，`TranslateTransform(-crop)` + `SetClip(crop)`，再逐个 `Render` (`Annotation.cs:406-418`)。
- 矩形/椭圆：`Fill` 为真则实心填充，否则描边；矩形 `LineJoin=Round` (`Annotation.cs:69-109`)。
- 箭头：普通样式按线段 + 三角箭头；`Open` 是两笔 V 形；`Double` 两端都有头；`Tapered*` 用 6 点多边形（宽头、细颈），实心或细描边 (`Annotation.cs:128-201`)。
- 铅笔：`DrawLines`，圆头圆角 (`Annotation.cs:225-237`)。
- 马克笔：把笔画路径 `Widen(pen)` 成面，再用 1–100% 透明度填充 (`Annotation.cs:393-404, 359-375`)。默认 50%。
- 马赛克：路径裁剪区域，从**冻结的截图位图**按固定网格采样平均色，然后画色块。网格以整张截图的绝对坐标对齐（`floor(bounds/block)*block`），因此相邻笔画不会错位；块大小限制 2–256 (`Annotation.cs:290-342`)。因为源是冻结截图，撤销只需恢复形状列表，不需要保存像素。
- 橡皮擦：只对**透明标注层**执行 `SourceCopy` + 透明刷，清掉 alpha，露出下方冻结截图，不修改截图 (`Annotation.cs:378-391`)。
- 命中测试非常简单：只有文字有命中（取最后一个包含点的 `TextShape`，`CaptureForm.cs:1174-1178`）。矩形/箭头/马赛克等**不可单独选中、移动、删除**，只能靠撤销或橡皮擦。选区锚点、工具栏、文字把手/移动框是独立命中逻辑。

### 2.3 撤销 / 重做

- 两套 `Stack<List<Shape>>` (`CaptureForm.cs:45-46`)。
- 快照 = 所有 shape 深拷贝（`Clone`；`PenShape`/`StrokeAreaShape` 显式复制 Points 列表）(`CaptureForm.cs:1145`)。
- 每次真正变更前 `SaveUndo()`：把当前快照压入 undo 并清空 redo (`CaptureForm.cs:1146`)。
  - 提交一笔新形状（鼠标松开且非空）(`CaptureForm.cs:767-773`)；
  - 提交/修改文字 (`CaptureForm.cs:1901-1947`)；
  - 移动文字、缩放文字（用 `_beforeTextDrag` 快照，结束时才压栈）(`CaptureForm.cs:741-759`)；
  - 修改已有文字的字体/颜色/粗细 (`CaptureForm.cs:1762-1780`)。
- `Undo()`：redo 压入当前快照，恢复 undo 弹出快照 (`CaptureForm.cs:1129-1135`)；`Redo()` 对称 (`CaptureForm.cs:1137-1143`)。
- 选区变化、工具切换、颜色/线宽调整不入栈；重新框选会直接清空 undo/redo (`CaptureForm.cs:628-631`)。

---

## 3. 工具栏 AnnotationBar

### 3.1 布局

完全手写布局与命中，不是 WinForms 控件 (`AnnotationBar.cs:5-10`)。

- 调色板 11 列 × 2 行，饱和色 + 粉彩色；默认选中 `Palette[3]` 红色 (`AnnotationBar.cs:13-38, 75`)。
- 基准尺寸（96dpi）：按钮 34、间距 2、内边距 5、色块 17、分组间隔 9；所有尺寸乘 `Scale`（= `DeviceDpi/96`）(`AnnotationBar.cs:42-47, 104-114`)。
- 第一行工具/动作顺序 (`AnnotationBar.cs:146-195`)：
  `rect, ellipse, arrow, pen, marker, mosaic, text, eraser` → 分隔 → `undo, redo` → 分隔 → `ocr, translate, qr` → 分隔 → `close, pin, save, copy`。
- 第二行仅在“非 OCR 模式且当前有工具”时出现 (`AnnotationBar.cs:144, 198-269`)：
  - 非文字工具：`width`（线宽/笔刷圆点，点击弹滑杆）；
  - 马克笔/马赛克/橡皮：`modebrush`（涂抹）+ `moderect`（框选）；
  - 马克笔：`opacity` 滑杆；马赛克：`strength` 滑杆；箭头：`arrowstyle`；
  - 矩形/椭圆：`fill`（实心/空心）；
  - 文字：`bold, italic, fontfamily(156px), fontsize(58px)`；
  - 非橡皮/马赛克：当前色 `colorcur` + 11x2 调色板网格；
  - 状态消息行 `_message`，可带 `resultcopy`（二维码内容复制）和 `ocrtextcopy`（复制 OCR 文字）按钮 (`AnnotationBar.cs:275-285`)。
- 定位：优先选区下方 10*Scale；下方空间不足则翻到选区上方；再夹到屏幕内；翻译面板高度通过 `AttachedPanelHeight` 计入 (`AnnotationBar.cs:287-306`)。注意它只按整块虚拟屏计算，不按单个显示器。

### 3.2 状态与交互

- 公开状态：`OcrMode/TranslationMode/CanUndo/CanRedo/Status/ResultCopyVisible/ResultCopied`，工具属性 `Tool/Color/StrokeWidth/FontFamily/FontSize/ArrowStyle/MarkerWidth/BrushWidth/MarkerOpacity/MosaicBlock/…/Fill/Bold/Italic/Accent/Scale` (`AnnotationBar.cs:64-105`)。
- 命中 `HitTest` 返回按钮 id (`AnnotationBar.cs:324-331`)；`Command(id)` 在 CaptureForm 里集中分发 (`CaptureForm.cs:1049-1127`)。
- 滑杆：把点击 X 映射为比例，`opacity` → 5–100%，`strength` → 块大小 2–40 (`AnnotationBar.cs:335-341`)；拖动时 `_slider` 锁定鼠标捕获 (`CaptureForm.cs:659-664, 1094-1098`)。
- 宽度选择器是弹出 `ContextMenuStrip` 内嵌 `TrackBar`（1–100）(`CaptureForm.cs:1382-1397`)；字号选择器是 `NumericUpDown` + 预设字号列表 (`CaptureForm.cs:1325-1334`)；字体选择器是自绘 `ListBox`，动态计算向上/向下展开与可见行数 (`CaptureForm.cs:1336-1380`)；箭头选择器是固定行高画廊 `ArrowStyleGallery` (`ArrowStyleGallery.cs:4-55`)。
- OCR 模式下：除 `ocr` 外所有工具按钮都不显示选中态，第二行选项隐藏，点击其他按钮会先退出识别再执行 (`AnnotationBar.cs:144, 464`, `CaptureForm.cs:498-513`)。
- 工具栏悬停提示通过 `Hint(id, ocrMode)` 给出中文快捷键文案 (`AnnotationBar.cs:343-362`)；`UpdateHint` 还会把二维码内容作为提示 (`CaptureForm.cs:1553-1566`)。
- 所有按钮图标手绘：部分用 24 单位 `FluentIcons` 矢量线稿 (`FluentIcons.cs:8-59`)，其余在 `DrawIcon` 里用 GDI+ 路径绘制 (`AnnotationBar.cs:637-820`)；撤销/重做带禁用态 (`AnnotationBar.cs:642-644`)。
- 当前色块有马克笔半透明棋盘格背景 + 彩虹角标 (`AnnotationBar.cs:524-570`)。

---

## 4. 选区 UI 细节

### 4.1 窗口/控件自动框选 DesktopTargets

- 构造时 `EnumWindows` 枚举所有顶层窗口，过滤：
  - 不可见、最小化；
  - `WS_EX_TRANSPARENT (0x20)`（透明点击穿透 overlay，常见于桌面工具的 CEF 覆盖层）；
  - DWM cloaked（属性 14）；
  - 宽高 >1 (`DesktopTargets.cs:9-23`)。
- `At(point, elements, includeAutomation)` 找到包含点的第一个窗口（按 Z 序） (`DesktopTargets.cs:24-34`)。
- `elements=false`：直接返回窗口矩形。
- `elements=true` 取以下三者中**面积最小且包含点**的矩形：
  1. 原生子窗口：`ScreenToClient` + `ChildWindowFromPointEx(..., 0x0001)` 逐层下降最多 32 层，忽略禁用控件、允许穿过透明容器 (`DesktopTargets.cs:127-145`)；
  2. MSAA/IAccessible：`AccessibleObjectFromWindow` + `accHitTest` 逐层最多 16 次 (`DesktopTargets.cs:67-95`)；
  3. UI Automation：`AutomationElement.FromHandle` + RawViewWalker 深度优先，深度上限 30、预算 800 个节点，空矩形容器继续下钻 (`DesktopTargets.cs:96-126`)。
- 性能/稳定性设计 (`CaptureForm.cs:1193-1260`)：
  - 60ms timer 触发 hover 解析；
  - 原生/MSAA 查询至少间隔 80ms，同一点 350ms 内不重复；
  - UIA 查询独立限流 120ms、最多 2 个在途、同一点 750ms 内不重复；
  - 线程池异步，回主线程前校验指针未移动、未开始选区；
  - 迟到的大矩形不能覆盖已经解析出的更小目标；
  - 元素检测开启时，如果当前 hover 仍包含指针，则优先保持（防止闪跳）。
- hover 高亮只用于“单击选中”，不是自动选区；真正选中发生在 mouse down/up 的 `_pressTarget` 逻辑。

### 4.2 放大镜

- 尺寸基数 168 * Ui，源区域为 `size/Zoom`，强制**奇数**源尺寸以保证正中央像素唯一；`size = sourceSize * Zoom` (`CaptureForm.cs:400-410, 2214-2227`)。
- 默认位置在光标右下方 24*Ui，越界翻到左/上 (`CaptureForm.cs:412-415`)。
- `NearestNeighbor` + `PixelOffsetMode.Half`，无平滑 (`CaptureForm.cs:417-423`)。
- 若已有选区：在放大镜里叠加遮罩、选区边框（线宽 `1/Zoom`）、可选锚点 (`CaptureForm.cs:424-441`)。
- 中心像素用 3 物理像素“深色 3px + 亮色 1px”十字准星，并套 1px 环 (`MagnifierReticle.cs:5-42`)；准星用 `CompositingMode.SourceCopy`，保证在任何背景上都是精确像素。
- 标签显示屏幕坐标、选区相对坐标、颜色值、快捷键提示 (`CaptureForm.cs:454-463, 1185-1191`)。
- 可见性：`Alt` 按住、正在缩放/移动文字、或“无选区且 AutoMagnifier 开启”时显示 (`CaptureForm.cs:120`)。
- 取色：放大镜标签与 `C` 键都直接 `_screenshot.GetPixel(_cursor)`，不受遮罩/标注影响 (`CaptureForm.cs:454, 998`)。
- 颜色格式由 `AppSettings.FormatColor` + `_hexColor` 控制；`Shift` 实时切换 RGB/HEX (`CaptureForm.cs:1007-1015, 1191`)。

### 4.3 标尺 / 尺寸提示

- 没有真正标尺。尺寸提示是选区左上角外的徽标 `"W × H"`，并避开工具栏和翻译面板；优先放选区左上外侧，放不下改放内侧、工具栏下方、工具栏右侧 (`CaptureForm.cs:356-398`)。
- 1x1 选区可隐藏徽标 (`CaptureForm.cs:359`, `PreferenceSettings.cs:40`)。
- 徽标视口取选区所在显示器，而不是整个虚拟屏 (`CaptureForm.cs:364-367`)。

### 4.4 DPI 处理

- 项目声明 `ApplicationHighDpiMode=PerMonitorV2` (`SnipLite.csproj`)。
- 数学全部按“物理像素”设计：`_virtual`、`_selection`、Shape 坐标都是像素；UI 尺寸统一乘 `Ui = DeviceDpi/96` (`CaptureForm.cs:162-166`)。
- 光标位置用 `GetCursorPos` 原始物理屏幕坐标，不用 WinForms 事件坐标做关键换算 (`CaptureForm.cs:2002-2006`, `Win32.cs:27-35`)。
- 标注层为每个 DPI 设置分辨率 `SetResolution(DeviceDpi, DeviceDpi)` (`CaptureForm.cs:1155-1164`)。
- 跨屏拖动时，窗口的 `OnDpiChanged` 被取消，十字线窗口用 Region 裁到 1px (`CaptureCrosshair.cs:17-39`)，因为 WinForms 会强制顶层窗口有最小厚度。

---

## 5. Windows 特有 API / 依赖 与 macOS 对应能力

### 5.1 截图与屏幕

| Windows | 用途 | macOS 对应 |
|---|---|---|
| `Graphics.CopyFromScreen`、`SystemInformation.VirtualScreen` | 冻结整个虚拟桌面 | ScreenCaptureKit：`SCShareableContent` + `SCScreenshotManager.captureImage`（macOS 14+）或单帧 `SCStream`；`SCContentFilter(display:excludingWindows:)` 排除自身窗口；`NSScreen.screens` + `CGDisplayBounds` 合并坐标；`SCStreamConfiguration.showsCursor` 捕获光标 |
| `GetCursorPos` / `DrawCursor` | 物理光标坐标、把光标画进截图 | `CGEvent(source:nil)?.location`（全局、左上原点）或 `NSEvent.mouseLocation`（左下原点）；光标位图不能直接取系统当前光标，需用 `NSCursor.current`/自定义图片或 SCK 的 showsCursor |
| `Screen.FromRectangle` / 多显示器 WorkingArea | 徽标取所在屏、Toast 定位 | `NSScreen.screens.first { $0.frame.contains(point) }` |
| 每显示器 DPI (`DeviceDpi`) | UI 缩放 | `NSScreen.backingScaleFactor`（通常 2.0）；注意 points vs pixels |

### 5.2 窗口 / 置顶 / 主题

| Windows | 用途 | macOS 对应 |
|---|---|---|
| `FormBorderStyle.None` + `TopMost` + `SetWindowPos(HWND_TOPMOST)` | 全屏遮罩 | `NSWindow` borderless，`level = .screenSaver`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`；`isOpaque=false`、`backgroundColor=.clear` |
| `CaptureCrosshair` 两个 1px 顶层窗口 | 不重绘冻结层也能移动十字线 | 用 `CALayer`/`NSView` 子层，`setNeedsDisplay(_ rect:)`；不需要 1px 最小窗口 hack |
| `Win32.SetForegroundWindow` / `Activate()` | 焦点 | `NSApp.activate(ignoringOtherApps:)` / `makeKeyAndOrderFront` |
| `DwmSetWindowAttribute(20/33)`、`SetWindowTheme`、注册表 `AppsUseLightTheme` | 深色标题栏/圆角/控件主题 | `NSApp.effectiveAppearance`、`NSAppearance(named: .darkAqua)`；`NSVisualEffectView`；窗圆角由 AppKit 处理 |
| `ShowWithoutActivation` / `WS_EX_NOACTIVATE` | Toast、十字线不抢焦点 | `NSPanel(styleMask: [.nonactivatingPanel, .borderless])` 或 `NSWindow` `canBecomeKey=false` |
| `WS_EX_TRANSPARENT`、`SetWindowLongPtr(GWL_EXSTYLE)` | 鼠标穿透贴图 | `NSWindow.ignoresMouseEvents = true` |
| `GetWindowLongPtr/EnumWindows/GetWindowRect/IsWindowVisible/IsIconic/DwmGetWindowAttribute(cloaked)` | 窗口枚举与过滤 | `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`；过滤 `kCGWindowAlpha==0`、`kCGWindowLayer` 异常层；用 `CGWindowListCreateImage`（已弃用）或 SCK 逐窗口 |
| `ChildWindowFromPointEx`、`ScreenToClient` | 原生子控件矩形 | 无 HWND 子控件；改用 Accessibility 层级 |
| MSAA `AccessibleObjectFromWindow/accHitTest` + UI Automation | 控件级框选 | Accessibility API：`AXUIElementCreateSystemWide()` / `AXUIElementCreateApplication(pid)`，`AXUIElementCopyElementAtPosition`，`kAXPositionAttribute`/`kAXSizeAttribute`（AXValue），`kAXChildrenAttribute` 遍历，取包含点的最小矩形 |
| `DwmGetWindowAttribute(14)` cloaked | 排除 UWP 幽灵窗口 | `CGWindowList` 的 `kCGWindowIsOnscreen` 与 alpha/layer 过滤 |

重要：macOS 的 `AXUIElementCopyElementAtPosition` 是系统级命中，会命中我们自己的全屏遮罩。需要先用 CGWindowList 找到指针下最上层、非本进程的窗口/pid，再对该 app 的 AX 树做“最小包含矩形”遍历，或暂时让遮罩不参与 AX。这是 Windows 版用 `AccessibleObjectFromWindow(指定 HWND)` 天然规避、macOS 必须显式处理的问题。

### 5.3 输入 / 热键 / IME

| Windows | 用途 | macOS 对应 |
|---|---|---|
| `RegisterHotKey` (`HotkeyHost.cs:28-36`) | 全局热键 | Carbon `RegisterEventHotKey`（无需辅助功能权限）或 `NSEvent.addGlobalMonitorForEvents`；快捷键录制可自行实现 |
| `SetWindowsHookEx(WH_KEYBOARD_LL)` + `GetAsyncKeyState` (`DesktopTargets.cs:162-193`) | 屏蔽 Win 键、屏蔽注入的 Ctrl+C | `CGEventTap`（需要辅助功能权限）过滤 `.keyDown`；判断合成事件用 `CGEvent.getIntegerValueField(.eventSourceUnixProcessID)`/`.sourceStateID`；macOS 无 Win 键，改为可选屏蔽 Command |
| WinForms `ProcessCmdKey/OnKeyDown/OnMouseWheel` | 会话快捷键 | `NSResponder.keyDown(with:)`、`flagsChanged`、`scrollWheel(with:)`；区分左右修饰键需 `NSEvent.modifierFlags` 之外的 keyCode |
| `ImeSink` + imm32 (`ImmGetContext/ImmGetCompositionStringW`) | 隐藏 1x1 输入框接收键盘和 IME，自绘组字串 | `NSView` 实现 `NSTextInputClient`：`insertText(_:replacementRange:)`、`setMarkedText(_:selectedRange:replacementRange:)`、`unmarkText`、`markedRange`、`firstRect(forCharacterRange:actualRange:)`（候选窗锚点）、`doCommandBySelector`；直接用 `markedTextRange` 绘制下划线，不再需要 1x1 隐藏控件 |
| 自定义光标 `CreateIconIndirect` / `DrawIconEx` (`TextIBeamCursor.cs:13-46`) | 与文字行高一致的 I 形光标 | `NSCursor(image:hotSpot:)` + `NSTrackingArea` / `cursorUpdate(with:)`；光标尺寸以 points 为单位 |
| `Cursors.Cross/SizeAll/SizeNWSE/...` | 鼠标形态 | `NSCursor.crosshair/openHand/closedHand/resizeUpDown/...`，自定义 `resizeDiagonal` |

### 5.4 剪贴板 / 文件 / 系统集成

| Windows | macOS |
|---|---|
| `Clipboard.SetDataObject`、`"PNG"`、`DataFormats.Bitmap`、`Clipboard.SetText` | `NSPasteboard.general.clearContents()` + `writeObjects([NSImage/NSBitmapImageRep])`；PNG 用 `.png`，文本用 `.string`；可同时写 `.tiff` |
| `SaveFileDialog` | `NSSavePanel`（`allowedContentTypes = [.png, .jpeg]`） |
| `ColorDialog` | `NSColorPanel` / `NSColorWell` |
| `MessageBox.Show` 确认 | `NSAlert` |
| `ToolTip` | `NSView.toolTip` 或自绘 |
| `ContextMenuStrip` + 自定义 renderer (`SnipMenu.cs`) | `NSMenu` + 自定义 `NSMenuItem.view`，或完全自绘弹层 |
| `TrackBar/NumericUpDown/ListBox` | `NSSlider` / `NSStepper`+`NSTextField` / `NSTableView` / 自绘列表 |
| `Toast` 顶层非激活窗口 | 非激活 `NSPanel`，`level=.statusBar`，自动消失 |
| `NotifyIcon` 托盘 | `NSStatusItem` + `NSMenu` |
| `Registry Run` / 任务计划 (`Startup.cs`) | `SMAppService.mainApp.register()`（macOS 13+） |
| `Mutex Global\...` 单实例 (`Program.cs:18`) | macOS 默认单实例；需要多实例管理时用 `NSRunningApplication` 或 DistributedNotification |
| `SoundPlayer` | `NSSound(named:)` / `NSSound(contentsOf:byReference:)` |
| `DoDragDrop(FileDrop)` 贴图拖出 (`PinForm.cs:186-197`) | `NSDraggingSession` / `NSFilePromiseProvider` |
| `Opacity` (`Form.Opacity`) | `NSWindow.alphaValue` |
| 置顶贴图 | `NSWindow.level = .floating/.statusBar`、`isMovableByWindowBackground`、`hasShadow`、自定义 `NSShadow`/阴影窗口 |

### 5.5 识别 / 翻译 / 音视频

| Windows | macOS |
|---|---|
| `Windows.Media.Ocr.OcrEngine` + WinRT `BitmapDecoder` (`Services.cs:42-79`) | Vision `VNRecognizeTextRequest`（支持 `zh-Hans`、`en` 等），`VNRecognizedTextObservation` 只有行/词级框；要逐字框需自己按字体宽度切分，或用 `RecognizeDocumentsRequest`（新系统）/CoreML PaddleOCR |
| `Sdcb.SimdPaddleOCR` | CoreML 版 PaddleOCR，或直接使用 Vision |
| ZXing.Net (`Services.cs:81-101`) | Vision `VNDetectBarcodesRequest`（QR/EAN/Code128/PDF417/DataMatrix 等），`VNBarcodeObservation.payloadStringValue` |
| 翻译 Provider（Bing/MyMemory/Microsoft，`TranslationService.cs` 等） | `URLSession` + 相同 HTTP API；也可用系统 Translation framework（macOS 15+） |
| 本地音效 | `NSSound` |
| `System.Drawing` 全部绘制 | Core Graphics / Core Text / AppKit；位图用 `NSBitmapImageRep` / `CGImage` / `CVPixelBuffer` |

---

## 6. 图片渲染、缩放与像素级操作

### 6.1 最终合成

`RenderComposite(crop)` (`CaptureForm.cs:1571-1584`)：

1. 新建 `crop.Width × crop.Height` 的 `Format32bppArgb`；
2. `InterpolationMode = NearestNeighbor`、`PixelOffsetMode.Half`，从冻结截图 1:1 裁剪；
3. 叠加翻译图层（不修改截图）；
4. 若存在标注，把与 crop 等大的透明标注层 `DrawImageUnscaled` 贴上去。

顺序很关键：翻译层在标注层之下，所以翻译后仍可在上面画标注 (`CaptureTranslation.cs:162-166`, `CaptureForm.cs:261-264`)。

### 6.2 缩放

- 放大镜：最近邻、整数倍、源尺寸为奇数、`size=sourceSize*Zoom`，避免半像素偏移 (`CaptureForm.cs:400-423`)。
- 贴图窗口：可在高质量双三次与最近邻之间切换 (`PinForm.cs:158-165`)；缩放围绕光标或窗口中心，并夹到 0.02–8 倍及最大尺寸 (`PinForm.cs:214-220`)。拖出/缩略图也走同一缩放模型。
- 标注层不做缩放：始终与 crop 同尺寸、同物理像素，避免重采样导致线条发虚。

### 6.3 马赛克像素操作

- `LockBits(area, ReadOnly, screen.PixelFormat)`，整块复制到 `int[]`，按 BGR 通道累加求平均，再逐块 `FillRectangle` (`Annotation.cs:309-336`)。
- 网格按整张截图的绝对坐标对齐，跨笔画一致；块大小在创建形状时乘 `Ui`，所以 Retina/高 DPI 下视觉块大小一致 (`CaptureForm.cs:580-584`)。
- 源是冻结截图而非当前合成图：优点是撤销零成本、马赛克不会“吃掉”自己的历史；移植时必须保留这一设计。
- 矩形模式对整个 `Rect` 网格化；涂抹模式先用 `path.Widen` 得到笔画覆盖区域，再裁剪网格 (`Annotation.cs:346-375`)。

### 6.4 取色与坐标

- 取色直接读冻结截图，不读屏幕，也不读遮罩/标注 (`CaptureForm.cs:454, 998`)。
- 坐标提示同时给屏幕绝对坐标和选区相对坐标 (`CaptureForm.cs:1185-1189`)。
- `Crop` 始终与虚拟屏求交 (`CaptureForm.cs:1568-1569`)；输出 `Bounds` 会加回虚拟屏原点，得到屏幕物理坐标 (`CaptureForm.cs:1302-1304, 1596-1597`)。
- 多显示器原点可为负，所有 UI 定位要在“虚拟屏局部坐标”和“全局屏幕坐标”之间显式转换（`_virtual.X/Y` 偏移）。

### 6.5 HiDPI 要点

- 选区、Shape、马赛克块、模糊采样全部以物理像素为单位。
- UI 尺寸（按钮、边距、锚点命中、放大镜、文字光标高度）才乘 `Ui`。
- `CaptureCrosshair` 的 1px 是物理像素，专门取消 WinForms 的 DPI 缩放。
- macOS 上对应的核心转换：`pixel = point * backingScaleFactor`，并且不同显示器可能有不同 scale；全屏遮罩要用 points 铺满 `NSScreen.frame`，内部绘制/命中用像素并统一换算。

### 6.6 文字渲染细节

- TextShape 字体 `GraphicsUnit.Point`，字号夹在 4–200，字体缺省回退 (`Annotation.cs:267-272`)。
- 工具栏文字用像素单位，标注文字用点单位；移植时要明确 NSFont 的 pointSize 与像素关系。
- 输入态使用 `TextEditLayout` 统一测量：
  - 行拆分处理 `\r`、`\n`、`\r\n` (`TextEditLayout.cs:15-27`)；
  - `GenericTypographic` + `MeasureTrailingSpaces`；
  - 光标高度 = `font.GetHeight`；
  - 命中测试按字素簇 (`StringInfo.ParseCombiningCharacters`) 二分，支持代理对/组合字符 (`TextEditLayout.cs:50-67`)；
  - 选区矩形按行给出；
  - 光标画法：白色 3px 底 + 主题色 1px，上下臂长 = 高度的 1/6 夹在 3–8 (`TextEditLayout.cs:85-97`)。
- IME 组字串是“插入到当前选区位置”的预览文本，带下划线，候选窗锚定在 1x1 sink 的位置 (`CaptureForm.cs:1844-1898`)。

---

## 7. 移植到 Swift/AppKit 最容易遗漏 / 出错的地方

1. **坐标系统与 Y 轴**
   - Windows/GDI 原点左上、Y 向下；AppKit 默认左下、Y 向上。建议 overlay 视图 `isFlipped = true`，内部统一左上原点，只在 `NSScreen`/`CGEvent` 边界翻转。
   - 多显示器虚拟原点可负、各屏 scale 可能不同；`NSScreen.frame`（points，左下）与 `CGDisplayBounds`（pixels，左上）是两套坐标，混用必错。
   - 所有选区/标注/历史区域都应存“全局物理像素”，UI 与导出时再转换。

2. **冻结截图的时机与自身窗口排除**
   - 必须在遮罩显示前截图，或显式用 `SCContentFilter(display:excludingWindows:)` 排除自己的窗口；否则会把遮罩/工具栏拍进去。
   - 多屏要一次性合成到同一张像素画布，保持与 `_virtual` 相同的原点定义。

3. **Retina 下的 1 点 ≠ 1 像素**
   - 原代码的 1px 选区边框、1px 十字线、马赛克块、放大镜源尺寸都以物理像素为准；Swift 中 `lineWidth = 1` 是 points，Retina 上会变 2px。要么在像素坐标系绘制，要么除以 scale。
   - `CaptureCrosshair` 的“1px 顶层窗口 + Region 裁剪 + 取消 DPI 变化”是 WinForms 特有 hack，不要照搬；用 `CALayer`/`NSView` 子层即可。

4. **马赛克必须从冻结截图采样**
   - 不能从“当前合成图”采样，否则第二次笔画会采到第一次马赛克，且撤销需要像素快照。
   - 网格必须按整张截图的绝对坐标对齐，否则相邻笔画/重叠笔画会出现接缝。
   - Retina 下块大小乘 scale 的时机要放在“创建形状时”，而不是渲染时重复乘。

5. **橡皮擦语义**
   - 只清透明标注层的 alpha（`CGBlendMode.clear`），绝不能把截图颜色画回去，否则被擦区域无法随缩放/马赛克正确重算。
   - 擦除后撤销必须恢复形状列表，而不是记录像素。

6. **透明层与预乘 Alpha**
   - GDI+ 用 `PArgb`（预乘）加速；Core Graphics 的 bitmap context 也有 premultiplied 选项。混用 `.premultipliedLast` / `.premultipliedFirst`、sRGB / Display P3 会导致颜色或 alpha 偏差。
   - 输出 PNG 要固定 sRGB、非预乘，避免复制到剪贴板和保存文件出现色差。
   - 取色与马赛克平均要在同一色彩空间；P3 屏上不要直接对 8bit 通道求平均后当 sRGB 输出。

7. **工具不可选中**
   - 只有文字有命中测试，其他标注画完即“烧”进标注层；没有对象选择/移动/删除。移植时不要“顺手”加上对象选择，除非产品明确改变交互。
   - 重新框选会清空所有标注和撤销栈，这是原版行为，容易在 Swift 重写时漏掉。

8. **撤销时机**
   - 快照必须在变更**之前**压栈；文字移动/缩放要在鼠标松开时压入“拖动前”快照，而不是开始拖动时立刻压栈。
   - 修改已有文字的字体/颜色/粗斜体也会产生撤销项。
   - 颜色、线宽、工具切换不入栈；选区变化清空历史。

9. **快捷键 / 视图模式键的拦截**
   - OCR/识别模式会拦截 Ctrl+A/C/Esc 并吞掉其余按键，不能落到截图复制/确认逻辑。
   - 二维码结果存在时 Esc 先清除二维码结果，再走后续 Esc 层级。
   - 文字编辑时 Enter 提交、Shift+Enter 换行、Esc 取消；点击别处会提交文字，空文本会删除该文字对象。
   - 右键是取消截图，不是上下文菜单；中键/双击/Enter 的动作和“是否退出”是分开的两个设置。

10. **输入法**
    - macOS 用 `NSTextInputClient` 才能真正处理中文/日文输入、候选窗、marked text；不要用隐藏 `NSTextField` 再读文本，容易丢组字、重复插入、候选窗错位。
    - 候选窗锚点 `firstRect(forCharacterRange:actualRange:)` 必须返回屏幕坐标，且随光标/滚动更新。
    - 组合字符、代理对、emoji 必须按 grapheme cluster 处理，光标/选区/命中测试三者要共用同一套排版结果。

11. **文字度量差异**
    - GDI+ `MeasureString(GenericTypographic)` 与 Core Text 的行高、字距、尾随空格行为不同；移植后光标位置、点击落点、选区高亮可能整体偏移。
    - 原代码用“按字体测宽后按比例分配 OCR 词框宽度”来生成逐字框 (`OcrSelection.cs:22-55`)，Vision 默认只给词/行框，需要复刻这套启发式。
    - 字体族默认是中文 UI 字体，macOS 要回退到 PingFang SC / SF Pro，并处理缺字回退。

12. **自动窗口/控件框选**
    - macOS 的 AX 命中会先命中自己的全屏遮罩，必须排除本进程或用 CGWindowList 找到下层目标进程。
    - 需要“辅助功能”权限；未授权时应无损降级为 CGWindowList 的窗口级框选，并给出引导。
    - AX 树遍历可能很慢/递归很深，要保留原版的预算、深度、超时、去重和“迟到结果不覆盖更小结果”的规则；AX 调用不要在主线程序列化执行。
    - `WS_EX_TRANSPARENT`/cloaked 的过滤在 macOS 对应 `kCGWindowAlpha`、`kCGWindowLayer`、窗口是否 onscreen，不能只取最上层窗口。

13. **全局热键与权限**
    - Carbon `RegisterEventHotKey` 不需要辅助功能权限；`CGEventTap` 做按键屏蔽则需要。首次启动要分别解释“屏幕录制”和“辅助功能”两个权限。
    - 原版默认用 `Ctrl+...`，移植后可保留默认值，但应提供符合 macOS 习惯的 `⌘/⌥` 组合，并检测冲突。

14. **工具栏定位与边界**
    - 选区贴近屏幕底部时工具栏翻到上方；贴顶时再夹回；翻译面板高度要参与计算。
    - 尺寸徽标要避开工具栏、翻译面板，并限制在选区所在显示器视口内。
    - 工具栏是“像素级手绘 + 命中”，Swift 里建议用 AppKit 子视图或 CALayer，但布局参数（34/2/5/17/9、11x2 调色板）要照搬，否则视觉密度会变。

15. **模式化输出的状态收敛**
    - `ExecuteAction(..., exit:false)` 允许复制后遮罩继续存在；`KeepOpen` 与 `Done` 事件要分开处理，不能简单“出图即关窗”。
    - 贴图动作在遮罩内触发后，实际是关闭遮罩再开一个新窗口；macOS 上两个都是 NSWindow，要设计好焦点、层级、选区位置传递。
    - 输出侧还有自动保存、历史、最近区域、剪贴板、Toast、音效等副作用，原版放在 `TrayContext` 而不是 CaptureForm，移植时保持同样的职责分离。

16. **OCR / 翻译会话的并发与失效**
    - 原版用版本号/请求号丢弃迟到结果（`_recognitionVersion`、`_translationRequest`），并在选区移动后自动重跑；Swift 的 async/await 要显式取消旧 Task。
    - 翻译渲染是异步生成一张透明图层，标注在其上继续编辑；不要把翻译文字直接烧进截图。
    - OCR 文档的字符坐标始终相对“识别时的 crop”，选区变化后必须重算或退出模式。

17. **Toast / 菜单不能抢焦点**
    - 原版用 `WS_EX_NOACTIVATE` + 非激活窗口；macOS 必须用非激活 `NSPanel`，否则会打断正在进行的截图/文字输入。

18. **其他容易漏的小行为**
    - 放大镜默认在无选区时就显示（AutoMagnifier 默认开）。
    - 滚轮在“放大镜可见”和“文字工具”之间是两种含义；设置可禁用滚轮。
    - `Shift` 只在放大镜可见时切换 HEX/RGB。
    - 马克笔与普通绘制颜色是两套记忆值，切换工具时互换 (`CaptureForm.cs:1043-1044`)。
    - 线宽三套：普通 3、马克笔 24、马赛克/橡皮 28，且创建时乘 scale (`CaptureForm.cs:575-577`)。
    - Undo/Redo 按钮禁用态、OCR/翻译模式下的按钮置灰逻辑不要漏。
    - 单实例、开机启动、托盘菜单是外围功能，但会影响“第一次启动是否弹权限、是否重复开遮罩”的体验。

---

## 关键文件索引

- 会话与状态机：`src/SnipLite/CaptureForm.cs`（启动 124-194、绘制 229-325、鼠标 483-831、键盘 852-1035、工具栏命令 1039-1127、目标检测 1193-1260、识别 1417-1531、输出 1568-1675、文字 1686-1989、辅助 1993-2227）
- 标注模型：`src/SnipLite/Annotation.cs`（类型 7-56、各形状 58-404、统一渲染 406-418）
- 工具栏：`src/SnipLite/AnnotationBar.cs`（调色板 13-38、布局 129-307、命中/滑杆 324-341、提示 343-362、渲染 364-633、图标 637-851）
- 选区目标：`src/SnipLite/DesktopTargets.cs`（窗口枚举 9-23、At 24-34、MSAA 67-95、UIA 96-126、原生子窗口 127-145、键盘钩子 162-193）
- 放大镜：`src/SnipLite/CaptureForm.cs:400-464`、`src/SnipLite/MagnifierReticle.cs:5-42`
- 文字排版：`src/SnipLite/TextEditLayout.cs`、`src/SnipLite/ImeSink.cs`、`src/SnipLite/TextIBeamCursor.cs`
- DPI 十字线：`src/SnipLite/CaptureCrosshair.cs`
- Win32 封装：`src/SnipLite/Win32.cs`
- 输出/OCR/翻译/贴图：`src/SnipLite/TrayContext.cs:148-192`、`src/SnipLite/Services.cs`、`src/SnipLite/OcrSelection.cs`、`src/SnipLite/TranslationOverlay.cs`、`src/SnipLite/CaptureTranslation.cs`、`src/SnipLite/PinForm.cs`
- 界面基础设施：`src/SnipLite/AppTheme.cs`、`src/SnipLite/FluentIcons.cs`、`src/SnipLite/FluentControls.cs`、`src/SnipLite/SnipMenu.cs`、`src/SnipLite/Toast.cs`、`src/SnipLite/ArrowStyleGallery.cs`
# SnipLite OCR / 翻译 / 二维码 只读探索报告

以下路径均为绝对路径。仓库根：`/Users/lusheng/Documents/开源工具/SnipLite`。

---

## 1. OCR 管线

### 1.1 引擎与依赖

- 依赖固定在 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SnipLite.csproj:28-30`：
  - `Sdcb.SimdPaddleOCR` 2.0.0
  - `Sdcb.SimdPaddleOCR.Models.ChineseV6Small` 1.0.0
  - `ZXing.Net.Bindings.Windows.Compatibility` 0.16.17
- 目标框架 `net10.0-windows10.0.19041.0`，WinForms + WPF，PerMonitorV2（`SnipLite.csproj:5-10`）。
- 主引擎是 PaddleOCR 的 C# 绑定，模型随程序附带，CPU 推理，首次使用时后台加载。
- Windows 系统 OCR 是备选引擎，不是主引擎。

### 1.2 引擎初始化与并发控制

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SimdOcr.cs:11-61`：

- `PaddleOcrAll` 是静态懒加载单例（`_engine`）。
- `SemaphoreSlim(1,1)` 串行化所有 OCR 请求，避免多个贴图/截图同时推理导致内存峰值（`SimdOcr.cs:13-15`）。
- 初始化与推理都在 `Task.Run` 中执行，不占用 UI 线程（`SimdOcr.cs:22-24`）。
- 选项：
  - `LineWorkerCount = 2`
  - `DetIntraOpThreads = min(CPU 核数, 4)`
  - Detector/Classifier/Recognizer 均为 `OcrBackend.Cpu`
  - `MaxPooledSessions` 分别为 1/2/2（`SimdOcr.cs:25-32`）
- 模型入口：`ChineseV6SmallModels.Default`，中英文混合自动识别。

### 1.3 图像预处理与坐标映射

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SimdOcr.cs:34-57`：

- 大图限制：
  - 长边最大 4096
  - 总像素约 1600 万
  - `scale = min(1, 4096/max(w,h), sqrt(16_000_000/(w*h)))`
- 缩放到 32bppArgb 位图，先铺白底再绘制，避免透明像素影响检测。
- 通过 `LockBits` 逐行拷贝为紧凑 BGRA 字节数组，调用：
  - `_engine.Run(pixels, width, height, returnCtcAlignment: true, sourceStride: stride, format: ImagePixelFormat.Bgra32)`
- `returnCtcAlignment: true` 是关键，用于后续估算字符框。
- 识别结果坐标通过 `sx = original.Width / input.Width`、`sy` 映射回原图，并 clamp 到图像边界（`SimdOcr.cs:67-68, 93-100`）。

### 1.4 返回的数据结构

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OcrSelection.cs:6-20`：

- `RecognizedWord(string Text, RectangleF Bounds, int Line)`
- `RecognizedCharacter(string Text, RectangleF Bounds, string Prefix)`
- `OcrDocument`：
  - `IReadOnlyList<RecognizedCharacter> Characters`
  - `IReadOnlyList<RectangleF> LineBounds`
  - `string Text`，即全部字符拼接
  - `GetText(start, end)` 支持正反选区间
  - `HitTest(point, nearest, tolerance)`

要点：

- **数据模型没有置信度字段**。Paddle 的识别分数和 Windows OCR 的 word 结果都没有被保留，只保留文本和几何。
- 每个 `RecognizedCharacter` 是一个字符/文本元素，`Prefix` 表示它前面应插入的换行或空格。
- `LineBounds` 是行级检测框，用于翻译分段和覆盖层区域。
- 几何单位见 `OcrSelection.cs:9` 注释：**相对于原始截图裁剪区域的物理像素**，不是 DIP。

### 1.5 字符框生成

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/SimdOcr.cs:69-91`：

- 直接使用 Paddle 行结果 `line.EstimateCharacterBoxes()`（基于 CTC 对齐）生成字符框。
- 每行之间给第一个字符加 `Environment.NewLine` 前缀。
- 如果字符框拼接文本与 `line.Text` 不一致，走降级路径：
  - 把整行做成一个 `RecognizedWord`
  - 由 `OcrDocument(IEnumerable<RecognizedWord>)` 按字体测量宽度比例拆分字符（`OcrSelection.cs:22-55`）
- 降级拆分使用 `Microsoft YaHei UI` 16px 测量，按 `StringInfo` 文本元素比例分配宽度。
- 旋转文字的字符框仍使用轴对齐外接矩形。

### 1.6 排序

代码没有按坐标重新排序：

- Paddle 路径保持 `result.Lines` 的顺序（`SimdOcr.cs:69`）。
- Windows 路径保持 `result.Lines` 的行顺序和 `line.Words` 的词顺序，`index` 作为行号（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Services.cs:75-78`）。
- 换行由 Prefix 插入，空白由 Windows word 的 `RecognizedWord` 拆分逻辑生成；相邻中文之间不加空格，其他词之间加空格（`OcrSelection.cs:37-38`）。

因此阅读顺序取决于引擎输出顺序，不是应用层几何排序。macOS 移植时若 Vision 不保证顺序，需要显式排序。

### 1.7 中英文支持

- Paddle 路径忽略 `language` 参数，始终使用 ChineseV6Small，中英文自动识别。
- Windows 路径使用设置中的 `OcrLanguage`：
  - 默认 `"zh-Hans"`（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AppSettings.cs:10`）
  - 首选项可选 `zh-Hans`、`en-US`、空字符串“跟随系统”（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:91-92`）
  - `OcrEngine.TryCreateFromLanguage(new Language(language))`，失败再 `TryCreateFromUserProfileLanguages()`（`Services.cs:64-70`）
- 因此“系统识别语言”只影响 Windows 引擎，不影响增强引擎。

### 1.8 引擎切换与回退

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Services.cs:27-40`：

- 用户选择 `SimdPaddle` 时：
  - 先尝试 `SimdOcr.RecognizeAsync`
  - 任何异常（模型加载失败、推理失败）都会记录日志，然后自动回退到 Windows OCR
- 用户选择 `Windows` 时：
  - 直接走 Windows OCR，不尝试 Paddle
- 成功但返回空文本时，不会再次尝试 Windows OCR，避免重复推理。
- `Services.OcrAsync` 进一步包了一层：任何异常都记录并返回空字符串（`Services.cs:14-25`），贴图 OCR 使用这个入口。

Windows OCR 实现：

- 将 Bitmap 保存为 PNG 内存流，转 `IRandomAccessStream`
- 按 `OcrEngine.MaxImageDimension` 缩放，再用 `BitmapTransform` 解码
- 坐标按缩放比例映射回原图（`Services.cs:42-78`）
- 需要系统安装对应 OCR 语言包，否则抛出中文提示。

### 1.9 像素 vs DIP

- 截图选区、裁剪、OCR 输入和 OCR 框全部是**物理像素**：
  - `CaptureResult.Bounds` 注释明确为 physical screen coordinates（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:19-20`）
  - `Ui => DeviceDpi / 96f` 只用于 UI 尺寸和命中容差（`CaptureForm.cs:162`）
  - OCR 命中容差 `16 * Ui` 物理像素，在 200% 缩放下约等于 16 DIP（`CaptureForm.cs:506, 2123`）
- 翻译覆盖层同样使用裁剪区域的像素坐标。

### 1.10 文档中的现状与限制

`/Users/lusheng/Documents/开源工具/SnipLite/docs/OCR_TRANSLATION_PLAN.md:7-12`：

- CPU 推理，首次约 325ms（本机 Release）。
- 极大图长边 4096、总像素约 1600 万。
- 字符框是 CTC 估算值，旋转文字使用轴对齐外框。
- 增强引擎异常时回退 Windows OCR；成功空结果不二次识别。
- 截图不上传，识别文本不写入日志。

---

## 2. OCR 划词交互

### 2.1 入口与状态

- 工具栏“OCR”按钮、独立 OCR 快捷键（`CaptureMode.Ocr`）、托盘菜单都进入 OCR 模式：
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1049-1083`
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:71`
- `RecognizeSelectionAsync(ocr: true)`（`CaptureForm.cs:1417-1473`）：
  - 先 `CommitText()`、清二维码结果
  - `crop = Crop`
  - **OCR 输入是 `RenderComposite(crop)`**，即包含标注层和翻译层的合成图（`CaptureForm.cs:1424`）
  - 这点与截图翻译不同：翻译 OCR 使用原始截图 clone，不含标注（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureTranslation.cs:73`）
- 识别期间：
  - `_recognitionBusy = true`
  - `_bar.Status = "正在识别文字…  Esc 返回标注"`
  - 鼠标变为 `AppStarting`，工具栏按钮为手型
- 成功：
  - 有字：`"拖动选字 · Ctrl+A 全选 · Ctrl+C 复制 · Esc 返回编辑"`，显示“复制文字”按钮
  - 无字：`"未识别到文字，按 Esc 返回后调整选区"`
  - 见 `CaptureForm.cs:1442-1449`
- 异常：状态栏显示 `识别失败：...`，同时 Toast 错误提示（`CaptureForm.cs:1458-1464`）。

### 2.2 拖动选字

鼠标按下（`CaptureForm.cs:498-512`）：

- 如果点在工具栏：
  - `ocr`：退出识别
  - `ocrtextcopy`：复制全部或选中文字
  - 其他命令：先 `ExitRecognition()`，再执行该工具命令
- 识别中：不处理选区
- 点在工具栏区域但不在按钮上：忽略
- 否则：
  - `_ocrAnchor = _ocrDocument.HitTest(point - _ocrCrop.Location, tolerance: 16 * Ui)`
  - `_ocrEnd = _ocrAnchor`
  - 只有命中 `>= 0` 才开始拖动
  - `Capture = true`

鼠标移动（`CaptureForm.cs:676-685`）：

- `_ocrEnd = _ocrDocument.HitTest(point - crop, nearest: true)`
- `nearest: true` 会吸附到最近的字符，即使拖到图像外
- 随后重绘选区并更新光标

鼠标抬起（`CaptureForm.cs:761-765`）：

- 只结束拖动，不自动复制。
- 复制必须显式按 Ctrl+C 或点“复制文字”按钮。

没有 Shift 扩选、双击选词或矩形选择；选择模型是字符索引区间。

### 2.3 命中测试与选择算法

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/OcrSelection.cs:73-87`：

- 先遍历所有字符，若 `Bounds.Contains(point)` 直接返回该索引。
- 否则计算点到字符矩形的欧氏距离平方，取最小。
- `nearest == true` 时总是返回最近索引。
- 否则只有距离 `<= tolerance²` 才返回索引，否则 `-1`。
- 容差在截图交互中为 `16 * Ui` 物理像素。

选择文本（`OcrSelection.cs:59-71`）：

- `GetText(start, end)` 自动处理正反选。
- 按索引顺序拼接 `Characters[i].Prefix + Characters[i].Text`。
- 选区是连续的字符索引区间，可以跨行，不存在矩形框选。

`OcrDocument` 的构造也支持从 `RecognizedWord` 生成字符：
- 按行合并 `LineBounds`
- 跨行 Prefix 为换行
- 同一行内相邻中文不加空格，其他加空格
- 按测量宽度比例拆分为字符（`OcrSelection.cs:22-55`）

### 2.4 快捷键与复制

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:874-887`：

- OCR 模式或识别中：
  - `Esc` → `ExitRecognition()`
  - 非忙碌时 `Ctrl+C` → `CopyOcrText(allIfUnselected: true)`
  - 非忙碌时 `Ctrl+A` → `_ocrAnchor = 0`, `_ocrEnd = CharacterCount - 1`, `ResultCopied = false`
  - 其他按键全部吞掉，不落入截图复制/确认/编辑快捷键
- `Ctrl+C` 在没有选区时复制全文；有选区时复制选区。
- `CopyOcrText`（`CaptureForm.cs:1512-1531`）：
  - 无选区且 `allIfUnselected` → `document.Text`
  - 否则 `document.GetText(anchor, end)`
  - 空文本提示“请先拖动选择文字，或按 Ctrl+A 全选”
  - 成功写剪贴板，`ResultCopied = true`，状态“已复制选中文字，可继续划词 · Esc 返回标注”
  - 失败提示“复制失败，请重试”
- 点 `ocrtextcopy` 按钮同样调用 `CopyOcrText(allIfUnselected: true)`（`CaptureForm.cs:502`）。

### 2.5 选区绘制

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1533-1551`：

- 选中字符：用强调色 100 alpha 填充，框稍微外扩
- 未选中字符：在字符框底部画一条强调色下划线
- 字符框偏移 `_ocrCrop.Location` 后绘制
- 选区索引区间 `[min(anchor,end), max(anchor,end)]`
- 没有按行裁剪，也没有文本重排。

### 2.6 状态栏

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/AnnotationBar.cs:64-72, 276-285, 379-392`：

- OCR 模式下状态消息行高度为 `44 * Scale`（普通模式 32）。
- 有文字时在消息行右侧显示 `ocrtextcopy` 按钮，尺寸约 80x34。
- 按钮文字：
  - `ResultCopied` → “已复制”
  - OCR 复制按钮 → “复制文字”
  - 其他 → “复制”
- 工具栏完整保留，但 OCR 模式下隐藏标注选项行（`showOptions = !OcrMode && Tool != ToolKind.None`，`AnnotationBar.cs:144`）。
- OCR 模式下只有 `ocr` 按钮保持选中，其他工具按钮不高亮（`AnnotationBar.cs:456-464`）。

### 2.7 Esc 与退出

- OCR 模式下 Esc 只退出 OCR 划词，不退出截图（`CaptureForm.cs:876`）。
- `ExitRecognition()`（`CaptureForm.cs:1475-1488`）：
  - `_recognitionVersion++`
  - 清空文档、锚点、选区
  - 关闭 `OcrMode` / `OcrCopyVisible`
  - 清空状态栏
  - 光标恢复
- 再次 Esc 才进入普通截图的取消逻辑，可能弹出“退出当前截图？”确认。
- 点击其他工具按钮会先退出 OCR 再切换到该工具；测试验证了“点铅笔恢复编辑工具”（`/Users/lusheng/Documents/开源工具/SnipLite/tests/SnipLite.SelfTest/SelfTest.Translation.cs:288-292`）。

### 2.8 光标

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:2119-2126`：

- 识别中：工具栏按钮上为 `Hand`，其他为 `AppStarting`
- OCR 模式：
  - 工具栏上 `Hand`
  - 字符命中容差内 `IBeam`
  - 其他 `Default`

### 2.9 macOS Vision 如何映射

Vision `VNRecognizeTextRequest` 的能力与差异：

- 观察结果是**行级** `VNRecognizedTextObservation`。
- 每行通过 `topCandidates(_:)` 取候选，得到字符串和 `confidence`。
- 行框是归一化坐标（0..1，左下原点）的 `boundingBox`。
- `VNRecognizedText.boundingBox(for: Range<String.Index>)` 可返回子串/字符范围的矩形，可用于近似字符框。
- Vision 不提供 Paddle 那种 CTC 逐字符对齐；字符框精度依赖 `boundingBox(for:)` 或自行测量。
- 映射建议：
  1. 行框：`x_px = box.minX * W`，`y_px = (1 - box.maxY) * H`，`w_px = box.width * W`，`h_px = box.height * H`。
  2. 行文本拆成 `Character` 数组，对每个字符构造 `Range<String.Index>`，调用 `boundingBox(for:)` 得到字符框。
  3. 如果 `boundingBox(for:)` 返回 nil 或明显过粗，改用 CoreText 在行框内按字形 advance 比例分配宽度，效果类似现有 `OcrDocument(IEnumerable<RecognizedWord>)` 的降级路径。
  4. 行间 Prefix 用换行；行内空格以 Vision 返回字符串为准；中文相邻不加空格。
  5. 观察结果顺序不保证，需要按 `boundingBox` 的 `midY` 从上到下、`minX` 从左到右排序；多栏排版需要按列聚类。
- 能力差异：
  - 有 confidence，可在新模型中增加可选字段（现有模型没有）。
  - 中文和英文可同时放在 `recognitionLanguages = ["zh-Hans", "en-US"]`。
  - `usesLanguageCorrection` 可能改变标点和数字，需按产品取舍。
  - `automaticallyDetectsLanguage`（macOS 13+）可替代固定语言配置。
  - 旋转文字通过 `VNImageRequestHandler` 的 `orientation` 处理；框仍是轴对齐。
  - Vision 是纯本地推理，不需要 Windows 语言包，也不需要 Paddle 模型。
- 现有交互层可以几乎原样复用：只要把 Vision 结果转换为 `OcrDocument` 的 `RecognizedCharacter` + `LineBounds`，命中测试、拖选、Ctrl+A/C、状态栏、Esc 逻辑全部不变。

---

## 3. 二维码 / 条码

### 3.1 库与格式

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/Services.cs:81-101`：

- 使用 ZXing.Net（`ZXing.Net.Bindings.Windows.Compatibility` 0.16.17）。
- `BarcodeReader` 配置：
  - `AutoRotate = true`
  - `Options.TryHarder = true`
  - `Options.TryInverted = true`
  - 没有设置 `PossibleFormats`，即使用 ZXing 默认支持的全部格式。
- 常见支持格式包括 QR Code、Aztec、PDF417、DataMatrix、Code 39/93/128、EAN-8/13、UPC-A/E、ITF、Codabar 等（具体以 ZXing.Net 该版本为准）。
- `reader.Decode(bitmap)?.Text`：
  - 只返回**第一个**成功解码结果
  - 不返回多个码
  - 不返回格式、位置、原始字节
  - 异常被吞掉，返回 null
- 输入是 `System.Drawing.Bitmap`，内部由 ZXing 转亮度源。

### 3.2 截图内识别流程

- 入口：
  - 工具栏 `qr` 命令（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1081`）
  - 独立 `CaptureMode.Qr` 模式（`CaptureForm.cs:10-11, 129`）
  - 托盘“二维码识别”快捷键（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:72`）
  - 普通截图按 Enter 且处于 QR 模式（`CaptureForm.cs:940`）
- `RecognizeSelectionAsync(ocr: false)`：
  - 输入同样是 `RenderComposite(crop)`，包含标注（`CaptureForm.cs:1424`）
  - `Services.DecodeQr(image)`
  - `ShowInlineQr(text)`（`CaptureForm.cs:1490-1498`）
- 结果 UI：
  - 不弹窗，直接在工具栏状态行显示完整内容。
  - 未识别时显示“未检测到二维码 / 条码，请调整选区后重试”。
  - 识别成功时显示 `resultcopy` 按钮，文字为“复制”/“已复制”。
  - 鼠标悬停在消息区域时，提示框显示完整内容（`CaptureForm.cs:1562`）。
  - `Ctrl+C` 复制完整内容（`CaptureForm.cs:869-872`）。
  - `Esc` 清除结果，回到普通截图（`CaptureForm.cs:872`）。
  - 点击“复制”调用 `CopyInlineQr`，写剪贴板并设置 `ResultCopied`（`CaptureForm.cs:1504-1510`）。
- 没有格式筛选、没有多码结果列表、没有在图上框出条码位置。

### 3.3 贴图 OCR / 二维码流程

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PinForm.cs:271-284`：

- 贴图右键菜单“识别文字”：
  - `Services.OcrAsync`
  - 空结果 Toast
  - 否则直接写剪贴板并 Toast“文字已复制”
- 贴图右键菜单“识别二维码”：
  - `Services.DecodeQr`
  - 空结果 Toast
  - 否则打开模态 `RecognitionResultForm`
- 结果窗口（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/RecognitionResultForm.cs:24-180`）：
  - 标题“识别成功”，副标题“二维码 / 条码内容”
  - 通过 `Uri.TryCreate` 判断 http/https，显示“链接”或“文本内容”
  - 显示字符数（`StringInfo.LengthInTextElements`）
  - 只读、自动换行 TextBox，可选中文本
  - “复制内容”按钮必须显式点击；复制后按钮变“已复制”，状态“已复制到剪贴板”
  - “关闭”按钮 / Esc 关闭
  - 初始 560x340，按内容行数扩展到最多约 480 高
  - 居中显示在鼠标所在屏幕工作区
  - 顶部图标为 QR 图标
- 注意：截图内 QR 结果不弹窗，贴图 QR 才弹窗；两者都是单结果。

### 3.4 macOS Vision 对应能力

- `VNDetectBarcodesRequest`：
  - 输入 `CGImage`，可返回多个 `VNBarcodeObservation`。
  - `payloadStringValue` 是字符串载荷。
  - `barcodeDescriptor` 提供更底层的描述（QR 纠错级别、ECI 等），可用于二进制或元数据。
  - `boundingBox` 是归一化坐标，左下原点，可用于在截图上框出条码位置（当前 Windows 版没有此 UI，可新增）。
  - `symbologies` 可指定格式列表。
- Vision 支持的常见格式：
  - QR、Aztec、PDF417、DataMatrix、Code 39/93/128、EAN-8/13、UPC-E、ITF-14、Codabar 等，具体随 macOS 版本略有差异。
- 能力差异：
  - Vision 支持的格式是 ZXing 的子集，不包含 GS1 DataBar/RSS、MaxiCode、MSI、PharmaCode 等 ZXing 格式。
  - 没有 `TryHarder`、`TryInverted` 等价开关；需要自行做反色、放大、锐化等预处理，必要时对反色图再跑一次。
  - `AutoRotate` 由 Vision 的图像方向处理，需正确传入 `CGImagePropertyOrientation`。
  - 可以天然返回多个码，产品上可升级为结果列表。
  - 对极小/模糊码的鲁棒性可能与 ZXing `TryHarder` 不同，需要回归测试。
- 如果必须覆盖 ZXing 全部格式，可引入 ZXing-CPP 的 Swift Package 作为补充；否则 Vision 足够覆盖日常二维码/条形码。

---

## 4. 翻译服务

### 4.1 公共约定

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TranslationService.cs`：

- 接口：`ITranslationProvider.TranslateAsync(text, source, target, cancellationToken)`（第 50-53 行）。
- 语言列表（第 12-17 行）：
  - `auto` 自动检测
  - `en`、`zh-CN`、`zh-TW`、`ja`、`ko`、`fr`、`de`、`es`、`ru`、`it`、`pt`
- `Normalize(code, allowAuto, fallback)`：不在列表中则回退；目标语言不允许 `auto`（第 19-20 行）。
- Provider 选择（第 26-48 行）：
  - 默认/首选项默认：必应网页翻译（`AppSettings.cs:14`）
  - 可选：必应网页翻译、Google、MyMemory、Microsoft Azure
- 所有 provider 的共同行为：
  - 空文本抛“没有识别到可翻译的文字…”
  - 文本超过 12000 字符抛“文字较多…”
  - 源语言 == 目标语言时直接返回原文，不发网络请求（Google/Microsoft/MyMemory/Bing 均有）
  - 错误统一转成中文 `InvalidOperationException`，不泄露密钥或原始请求细节。
- 没有自动重试/退避；重试由 UI 的“重新翻译”按钮触发。

### 4.2 Google 公共网页接口

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TranslationService.cs:55-141`：

| 项目 | 内容 |
|---|---|
| URL | `https://translate.googleapis.com/translate_a/single` |
| 方法 | GET |
| 参数 | `client=gtx&dt=t&ie=UTF-8&oe=UTF-8&sl=<source>&tl=<target>&q=<text>` |
| 鉴权 | 无 |
| 超时 | HttpClient 12s；单次翻译 linked CTS 35s |
| 响应 | `root[0]` 是分段数组，每段 `segment[0]` 是译文文本；`root[2]` 是检测语言 |
| 分段 | `SplitText`：每段最多 600 字符；超过 300 字符后优先在空白处切；不拆 UTF-16 代理对；保留分隔符 |
| 限流/错误 | HTTP 429 → “翻译请求过于频繁”；非 2xx → “翻译服务暂时不可用”；超时/网络/JSON 分别提示 |
| 检测语言 | `root[2]` 字符串，可能为 null |

测试契约：
- 多段拼接与检测语言（`SelfTest.Translation.cs:73-79`）
- query 编码为 `%20`、`%0A`、`%3F`（第 79 行）
- 同语言不发起网络（第 81-82 行）
- 取消不发起请求（第 83-85 行）
- 429、网络错误、非法 JSON（第 86-97 行）
- 分段不破坏 Unicode/空格（第 92-95 行）

### 4.3 必应网页翻译（BingWebTranslationProvider）

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/BingWebTranslationProvider.cs`：

**会话获取**

- 页面：`https://cn.bing.com/translator?setlang=zh-cn`（第 12-13 行）
- GET 页面 HTML，正则提取三部分（第 67-74 行）：
  1. `params_AbusePreventionHelper = [key, "token", lifetimeMs]`
  2. `IG: "十六进制字符串"`
  3. `data-iid="translator.xxx"`
- `key` 是数组第一个元素的原始 JSON（数字），`token` 是第二个字符串，`lifetime` 是第三个数字（毫秒），clamp 到 0..300000（第 76-79 行）。
- `Session(Key, Token, Impression, Instance, Expires)` 缓存在静态字段中，过期前复用（第 20-21、64-65、80 行）。
- `_sessionGate` 串行化会话获取，避免并发重复登录（第 19、61、83 行）。
- HTML 中缺少任一字段 → “必应网页未提供翻译会话…”（第 73-74 行）。

**翻译请求**

- URL：`https://cn.bing.com/ttranslatev3?isVertical=1&IG=<impression>&IID=<instance>`（第 89-90 行）
- 方法：POST
- `FormUrlEncodedContent` 参数（第 93-100 行）：
  - `text`
  - `fromLang`：`auto` → `auto-detect`，否则 `ToMicrosoftCode(source)`
  - `to`：`ToMicrosoftCode(target)`
  - `key`
  - `token`
- 请求头 `Referrer = Page`（第 102 行）。
- 响应解析复用 `MicrosoftTranslationProvider.ParseResult`：
  - `translations[0].text`
  - `detectedLanguage.language`
  - 语言代码归一化（`zh-hans` → `zh-CN` 等）
- 状态处理：
  - HTTP 401/403 → 清除缓存的 session，下次重新获取（第 113-117 行）
  - HTTP 429 → “必应网页翻译请求过于频繁”
  - 非 2xx → 带 HTTP 状态码的提示
  - 响应 JSON 里的 `statusCode` 也会按 HTTP 状态检查（第 107-109 行）
  - 超时/网络/JSON 分别提示
- 分段复用 Google 的 `SplitText`（600 字符）。
- 同一实例 `BingWebTranslationProvider.Shared`，因此会话和 Cookie 可复用。
- Cookie：使用默认 `HttpClientHandler`（AllowAutoRedirect=false），默认启用 CookieContainer；会话很可能依赖 Cookie，macOS 端需用共享 CookieStorage 保持同样行为。
- 测试：
  - 并行两个请求共享会话（`SelfTest.Translation.cs:36-43`）
  - 第二个请求 `auto` 检测为 `en`
  - 默认 provider 是 Bing（第 215 行）

### 4.4 Microsoft Azure Translator

文件：`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/MicrosoftTranslationProvider.cs`

| 项目 | 内容 |
|---|---|
| URL | `https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=<target>`；源语言非 auto 时加 `&from=<source>` |
| 方法 | POST |
| Body | JSON 数组：`[{"Text": "<text>"}]`，UTF-8，`application/json` |
| 鉴权 | Header `Ocp-Apim-Subscription-Key`；可选 `Ocp-Apim-Subscription-Region` |
| 语言映射 | `zh-CN ↔ zh-Hans`，`zh-TW ↔ zh-Hant`；其他代码原样 |
| 响应 | `root[0].translations[0].text`；`root[0].detectedLanguage.language` |
| 检测语言归一化 | `zh-hans → zh-CN`，`zh-hant → zh-TW`，其他小写原样；auto 且无检测 → null |
| 分段 | **不分段**，单次请求；仅做 12000 字符上限检查 |
| 超时 | HttpClient 12s；没有额外的 35s linked timeout |
| 错误 | 401/403 → “检查密钥、资源区域和配额”；429 → “请求过于频繁”；其他非 2xx → 带状态码；超时/网络/JSON |
| 凭据 | `MicrosoftTranslatorCredentials` |

凭据存储（`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/MicrosoftTranslatorCredentials.cs:11-53`）：

- 文件：`%LocalAppData%\SnipLite\microsoft-translator.dat`
- 使用 Windows DPAPI `ProtectedData.Protect/Unprotect`，`DataProtectionScope.CurrentUser`
- JSON 序列化 `{key, region}`
- 保存时先写 `.tmp` 再 `File.Move(overwrite: true)`
- 读取失败抛“无法读取微软翻译密钥，请在首选项中重新配置”
- 空 key 保存会删除文件
- 测试：
  - 请求方法、key/region header、body、URL query（`SelfTest.Translation.cs:44-66`）
  - 无 key 时不发请求（第 59-60 行）
  - 401 错误不泄露密钥（第 69-71 行）
  - `zh-TW → from=zh-Hant`（第 67-68 行）

### 4.5 MyMemory

文件：`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/MyMemoryTranslationProvider.cs`

| 项目 | 内容 |
|---|---|
| URL | `https://api.mymemory.translated.net/get?langpair=<source>|<target>&q=<text>` |
| 方法 | GET |
| 鉴权 | 无（匿名额度） |
| 源语言 | **不支持 auto**，auto 时抛“请在翻译栏选择源语言” |
| 目标语言 | 必须明确，不允许 auto |
| 超时 | HttpClient 12s；linked CTS 35s |
| 分段 | 自定义 `SplitText`：每段最多 500 个 UTF-8 字节；换行是硬边界；超过约 250 字节后优先在空白或中英文标点处切；保留空白段；按 Rune 处理代理对 |
| 响应 | `responseStatus` 必须为 200；`responseData.translatedText`，`WebUtility.HtmlDecode` |
| 额度 | `quotaFinished == true` → “MyMemory 当日匿名额度已用完”；`responseStatus == 429` → “请求受限” |
| 检测语言 | 不检测，返回 source |
| 错误 | 非 200、非 2xx、超时、网络、JSON |

测试：
- UTF-8 500 字节上限、不包含换行、emoji 起始（`SelfTest.Translation.cs:343-349`）
- query 编码 `langpair=en%7Czh-CN`、`q=Hello%20%26%20world`（第 350-358 行）
- auto 报错且不发请求（第 359-360 行）
- 额度错误（第 361-366 行）
- 可选 live 测试（第 367-371 行）

### 4.6 语言代码与分段/限流汇总

- 应用语言代码：`auto/en/zh-CN/zh-TW/ja/ko/fr/de/es/ru/it/pt`。
- Google、MyMemory 直接使用应用代码。
- Microsoft/Bing 将 `zh-CN`、`zh-TW` 映射为 `zh-Hans`、`zh-Hant`。
- Bing 的 auto 映射为 `auto-detect`；Azure 的 auto 是省略 `from`；Google 是 `sl=auto`；MyMemory 禁止 auto。
- 总限制：12000 字符、80 个 block；Google/Bing 单块 600 字符；MyMemory 单块 500 UTF-8 字节。
- 限流：各 provider 都识别 429，但没有自动退避；Capture 层最多 2 个并发 block。
- 错误：任一块失败会取消其余任务，最终显示第一个失败原因；`InvalidOperationException` 的消息直接展示，其他异常显示通用“翻译失败，请检查网络后重试”。

---

## 5. 翻译 UI

### 5.1 进入翻译

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureTranslation.cs:59-93`：

- 前置条件：有选区、非识别中、非 OCR 模式、未完成。
- `CommitText()`、`ClearQrResult()`。
- 创建/显示 `TranslationPanel`。
- 记录 `_translationCrop = Crop`。
- 面板先显示“正在识别…”。
- 设置 `_bar.TranslationMode = true`，隐藏放大镜。
- OCR 输入是 `_screenshot.Clone(crop)`，**只包含原始截图，不包含标注**（第 73 行）。
- OCR 成功后：
  - `_translationInput = document.Text`
  - `_translationBlocks = TranslationOverlay.GetBlocks(document)`
  - `_translationSnapshot = new Bitmap(image)`
  - 面板显示原文
  - 空文本 → “未识别到文字，请调整选区。”
  - 否则开始翻译。
- 失败 → “识别失败，请重试或调整选区。”

### 5.2 面板布局与控件

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TranslationPanel.cs:26-64, 136-150`：

- 单行工具栏，高度 `44 * scale`，初始宽度 `680 * scale`。
- 控件：
  - 源语言下拉
  - 交换按钮
  - 目标语言下拉
  - 原文/译文切换按钮（单个眼睛图标）
  - 复制按钮
  - 重试按钮
  - 翻译服务下拉
  - 状态 Label
- 面板本身不显示译文文本，只用状态行显示进度/结果状态；译文显示在截图的透明覆盖层上。
- 面板附着在工具栏正下方：
  - `x = bar.MainBounds.Left`
  - `y = bar.Bounds.Bottom + 4 * Ui`
  - 宽度 = `bar.MainBounds.Width`
  - 高度 = panel.Height
  - 见 `CaptureTranslation.cs:168-173`
- 语言选择持久化到 `AppSettings.TranslationSourceLanguage` / `TranslationTargetLanguage`，每次变化保存（`CaptureTranslation.cs:23-29`）。

### 5.3 语言选择、自动检测、交换

- 源语言可 `auto`，但 MyMemory 不允许自动（`TranslationPanel.cs:32, 217-223`）。
- 目标语言永远不允许 `auto`（`TranslationPanel.cs:247-251`）。
- 自动检测：
  - Provider 返回 `DetectedLanguage`
  - 面板源语言标签显示“检测到X”（`TranslationPanel.cs:232-241`）
- 交换：
  - 如果源语言是 `auto`，用 `DetectedLanguage` 解析成具体语言，回退 `en`
  - 然后交换源/目标
  - 重置检测语言并触发重新翻译
  - 见 `TranslationPanel.cs:225-230`
- 切换语言不重新 OCR，只重新翻译现有 `_translationInput`（`CaptureTranslation.cs:23-29`）。

### 5.4 原文/译文切换与复制

- `ShowOriginal` 控制：
  - 覆盖层绘制：`DrawTranslationOverlay` 在 `ShowOriginal` 时直接 return（`CaptureTranslation.cs:162-166`）
  - 复制内容：原文或译文（`TranslationPanel.cs:326-331`）
- 切换时状态：
  - 显示原文 → “显示原文”
  - 显示译文 → “已翻译”
  - 见 `TranslationPanel.cs:313-317`
- 复制状态：
  - “原文已复制” / “译文已复制”
  - 失败“复制失败，请重试”
- 复制按钮和眼睛按钮的工具提示会随视图变化（`TranslationPanel.cs:319-325`）。

### 5.5 翻译执行、缓存、并发

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureTranslation.cs:95-160`：

- 每次翻译：
  - 取消旧的 `_translationCancellation`
  - `_translationRequest` 自增，用于丢弃过期结果
  - 读取当前源/目标语言和 provider
  - block 为空时用全文作为一个 block，bounds `(0,0,1,1)`
- 限制：
  - 文本超过 12000 字符或 block 超过 80 → “文字较多，请缩小选区后翻译。”
- 并发：
  - `SemaphoreSlim(2,2)`，最多两个 block 同时翻译
  - `Task.WhenAll`
- 缓存：
  - key `(Text, Source, Target)`
  - 最多 80 条，满了整体清空
  - `force: true` 跳过缓存
- 进度：
  - 每完成一个 block 调用 `SetProgress(completed, total)`
  - 状态“翻译中 n/N”
- 失败：
  - 第一个非取消异常记录到 `firstFailure`
  - 立即 `cancellation.Cancel()`
  - 其余任务取消
  - 最终只显示第一个错误
- 结果：
  - 所有 block 结果按原顺序用换行拼接
  - `DetectedLanguage` 取第一个非空
  - 面板 `SetResult`
- 覆盖层：
  - 仅在成功且请求仍有效时渲染
  - `TranslationOverlay.Render(snapshot, blocks, results, token)`
  - 更新 `_translationLayer`
  - 重绘选区
- 取消：
  - `OperationCanceledException` 且不是失败导致 → 静默
  - 请求版本不匹配 → 丢弃结果

### 5.6 原位覆盖算法

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TranslationOverlay.cs:11-129`：

**分块**

- 先按 OCR 字符的 Prefix 换行拆成逐行 block（第 21-28 行）。
- 再把相邻行合并成段落：
  - 行间距 `gap` 在 `[-0.2 * lineHeight, 0.8 * lineHeight]`
  - 且左边界差 `<= 0.65 * lineHeight`
  - 满足则合并，`LineCount + 1`
  - 否则新建 block
- 目的：把自动换行的段落合并，同时保留独立标签和不同栏位。
- `LineBounds` 优先使用 OCR 行框。

**渲染**

- 创建与截图同尺寸的 `32bppPArgb` 透明层（第 54 行）。
- 对每个 block：
  - 译文为空或 `text.Trim() == block.Text.Trim()` → 跳过（第 64 行）
  - `area = ceil(block.Bounds) ∩ 图像`
  - `padding = clamp(0.18 * lineHeight, 2, 8)`
  - `cover = area` 外扩 padding，并裁剪到图像
  - 背景取色：沿 cover 四边采样，横竖步长约为宽/24、高/16，取 RGB 中位数（第 97-110 行）
  - 前景取色：在 area 内按约 `sqrt(area/1500)` 的步长采样，选择与背景 RGB 绝对差之和 `> 180` 的像素，取中位数；没有则根据背景亮度选白色或深灰（第 112-124 行）
  - 用背景色填充 cover，覆盖原文
  - 字体自适应：在 `[4, clamp(lineHeight, 6, 96)]` 内二分 8 次，用 `MeasureString` 检查宽高是否都不超过 area（第 83-95 行）
  - 使用 `Microsoft YaHei UI`，像素单位
  - `StringFormat` 使用 `Trimming.None`、`LineLimit`，即不省略但可能被区域裁切
  - `DrawString` 绘制到透明层
- 只用 `DrawString`，不用 `TextRenderer`，以保留 PArgb 层的 alpha，避免 GDI 文字产生透明孔洞（第 75-76 行）。

**限制**

- 背景填充是纯色中位数，不做图像修复/inpainting。
- 复杂背景、渐变、纹理、照片背景效果差。
- 旋转文字的 block 仍是轴对齐框。
- 译文过长时字体会缩小到 4px 甚至裁切。
- 强制使用一种字体，不保留原文的粗体/斜体/颜色。
- 覆盖区域可能覆盖相邻非文字内容（padding 导致）。

### 5.7 覆盖层与导出

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureForm.cs:1571-1584`：

- `RenderComposite(crop)` 顺序：
  1. 原始截图
  2. 翻译层（`DrawTranslationOverlay`）
  3. 标注层
- 因此：
  - 标注永远在译文之上
  - 复制截图、保存、贴图都会包含当前显示的翻译层
- 关闭翻译/切回原文：
  - 不绘制翻译层，恢复原始像素
  - 测试验证“切换原文恢复完全相同的像素”（`SelfTest.Translation.cs:250-252, 274-275`）
- 改变选区：
  - `RefreshTranslationSelection` 检测到 `Crop != _translationCrop` 后重新翻译（`CaptureTranslation.cs:175-180`）
- 关闭翻译：
  - 取消请求、释放快照/层、隐藏面板、清空缓存、恢复工具栏（`CaptureTranslation.cs:195-203`）。

### 5.8 Provider 切换

`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/CaptureTranslation.cs:44-57`：

- 仅本次截图会话切换，不修改首选项默认值（测试第 214-215 行）。
- Microsoft 需要已有密钥，否则状态栏提示“请在首选项 → 常规 → 配置微软密钥”。
- 切换后：
  - 创建新 provider
  - 清空本次翻译缓存
  - 复用已有 OCR 文本重新翻译
  - 旧请求通过 `TranslateRecognizedTextAsync` 的取消逻辑取消
- 测试验证旧 provider 的迟到结果不会覆盖新结果（`SelfTest.Translation.cs:199-213`）。

### 5.9 状态与错误

- `SetBusy`：清空结果、关闭原文视图、禁用眼睛/复制/重试、状态文字（`TranslationPanel.cs:289-294`）。
- `SetProgress`：`翻译中 n/N`。
- `SetResult`：启用按钮、状态“已翻译”、更新检测语言。
- `SetError`：
  - 清空结果
  - 禁用眼睛/复制
  - 启用重试
  - 状态文字红色（深色主题 `(255,160,155)`，浅色主题 `(178,48,42)`）
  - 见 `TranslationPanel.cs:303-308`
- 重试：
  - 如果没有识别文本 → 重新识别
  - 否则 `TranslateRecognizedTextAsync(force: true)`
  - 见 `CaptureTranslation.cs:31-35`
- Esc：
  - 如果翻译可见且没有文本输入焦点 → `CloseTranslation()`，返回标注（`CaptureForm.cs:868`）
  - 测试验证 Esc 取消请求且不退出截图（`SelfTest.Translation.cs:184-189`）。

---

## 6. 文本渲染（TextImageRenderer）

文件：`/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TextImageRenderer.cs`

### 6.1 用途

- 剪贴板“文字转图片”贴图：
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/TrayContext.cs:215-218`
- 首选项预览：
  - `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferencesPages.cs:321`
- 判断文件路径：
  - `IsFilePath` 检查文件/目录存在，或用正则匹配盘符、UNC、`file://`（第 10-14 行）。
  - 与 `IgnoreFilePaths` 设置配合，避免把文件路径当文本转图。

### 6.2 HTML 解析

`TextImageRenderer.cs:56-81`：

- 如果剪贴板有 HTML 且未设置“总是忽略 HTML”：
  - 取 `<!--StartFragment-->` 和 `<!--EndFragment-->` 之间的内容
  - 否则从第一个 `<` 开始
  - 删除 `script` / `style`
  - 按标签正则拆分
  - 支持嵌套 `b/strong`、`i/em`、`u`
  - `br`、闭合的 `p/div/li` 产生换行
  - `WebUtility.HtmlDecode` 解码实体
  - 连续空白折叠为一个空格
- 不支持 CSS、颜色、字体、链接、图片、列表编号等。

### 6.3 字体与测量

- 字体来自设置：
  - `TextImageFont`，默认 `Microsoft YaHei UI`
  - `TextImageFontSize`，默认 11，clamp 6..100
  - 见 `/Users/lusheng/Documents/开源工具/SnipLite/src/SnipLite/PreferenceSettings.cs:83-88, 128-130`
- 字体构造函数使用默认单位 Point；位图默认 96 DPI，因此 11pt 约 14.7px。
- 测量：
  - `StringFormat.GenericTypographic`
  - 加 `MeasureTrailingSpaces`
  - 每个文本元素（grapheme）单独 `MeasureString`，宽度向上取整
- 行高：
  - `ceil(font.GetHeight(g) * 1.15)`
- 换行：
  - 显式 `\n` 换行
  - 当 `x > 0 && x + advance > maxWidth` 时换行
  - 没有单词边界判断，可能在单词中间断行
- 最大宽度：
  - `max(20, TextImageMaxWidth - margin * 2)`
  - 默认最大宽度 900，margin 15
- 高度上限：
  - 如果 `y + lineHeight + margin * 2 > 30000`，抛“文字过长，请分段转换为贴图。”
- 输出尺寸：
  - 宽 `maxLineWidth + 2*margin`
  - 高 `y + lineHeight + 2*margin`
- 绘制：
  - 背景 `Color.FromArgb(TextImageBackground)`
  - 前景 `Color.FromArgb(TextImageForeground)`
  - `AntiAliasGridFit`
  - 每个 grapheme 用对应样式字体 `DrawString`
- 常量/默认值见 `PreferenceSettings.cs:83-88`。

### 6.4 HiDPI

- 输出 Bitmap 没有显式 `SetResolution`，使用 GDI+ 默认 96 DPI。
- 字体大小按 Point 解释，布局和边距按像素解释。
- 结果是一张固定像素尺寸的图片，后续在贴图窗口中被系统缩放。
- 应用本身是 PerMonitorV2，但这个渲染器不参与 DPI 感知布局；macOS 移植时需要决定输出是“点尺寸 × 缩放因子”还是固定像素。
- 现有测试 `SelfTest.TextEditing` 测的是截图内标注文字的编辑/光标/命中，不是 `TextImageRenderer`，但其中的 grapheme、CRLF、多行命中契约可以复用。

---

## 7. macOS 可复用方案与需要重写的部分

### 7.1 可直接复用/映射

| Windows 实现 | macOS 方案 |
|---|---|
| Sdcb.SimdPaddleOCR | Vision `VNRecognizeTextRequest`，`.accurate`，`recognitionLanguages = ["zh-Hans", "en-US"]`，本地推理 |
| Windows.Media.Ocr 备选 | Vision 为主即可；可选 VisionKit/Live Text 作为二次路径 |
| 字符框 CTC 对齐 | `VNRecognizedText.boundingBox(for:)` + CoreText 测量回退 |
| ZXing BarcodeReader | Vision `VNDetectBarcodesRequest` |
| HttpClient | `URLSession` + async/await `data(for:)` |
| 35s linked CTS | `URLSessionConfiguration.timeoutIntervalForResource` + Swift `Task` 取消 |
| DPAPI 凭据 | Keychain `kSecClassGenericPassword` |
| GDI+ 透明覆盖层 | CoreGraphics `CGBitmapContext` / `NSBitmapImageRep`，premultiplied alpha |
| GDI+ 字体拟合 | CoreText `CTFramesetter` / `NSLayoutManager` 测量 + 二分字号 |
| 文本转图片 HTML 解析 | `NSAttributedString(data:options:[.documentType: .html])`，比正则更完整 |
| WinForms 工具栏/面板 | AppKit `NSView` / SwiftUI，保留同样的单行 44pt 布局语义 |
| Win32 全局热键 | Carbon `RegisterEventHotKey` 或 KeyboardShortcuts/MASShortcut 库 |
| 屏幕截图 | ScreenCaptureKit（macOS 12.3+）或 CGWindowList，注意 Retina 像素与点的换算 |
| 剪贴板 | `NSPasteboard.general` |

### 7.2 需要重新实现

- PaddleOCR 模型与推理：Vision 是替代品，不是等价物；如果要求同样的中文小字/竖排/特殊字体精度，需要 CoreML 模型或第三方 OCR。
- CTC 字符对齐：Vision 没有；需要用 `boundingBox(for:)` 或 CoreText 自行估算。
- ZXing 全部条码格式：Vision 只覆盖常见子集；缺失格式需 ZXing-CPP 补充。
- Windows OCR 语言包逻辑：完全移除。
- GDI+ 的精确字形拟合、PArgb alpha 行为：用 CoreGraphics 重新实现并做像素回归。
- DPAPI：改 Keychain，并处理“用户拒绝访问/钥匙串锁定”。
- 所有 WinForms 交互：选区、工具栏、状态栏、菜单、Toast、贴图窗口。
- 坐标体系：Windows 版 OCR/覆盖层坐标是物理像素；macOS 需要明确区分屏幕点、Retina 像素和 Vision 归一化坐标。

### 7.3 建议的 macOS 结构

- `OcrDocument` / `RecognizedCharacter` / `RecognizedWord`：保留现有模型，坐标改为 `CGRect`（像素）。
- `VisionOcrEngine`：
  - actor 串行化请求
  - 输出 `OcrDocument`
  - 字符框用 `boundingBox(for:)`，失败时 CoreText 分配
- `VisionBarcodeScanner`：返回 `[BarcodeResult]`，当前 UI 取第一个，未来可列多个。
- `TranslationProvider` 协议：
  - `GooglePublicProvider`
  - `BingWebProvider`（actor 缓存 session）
  - `MyMemoryProvider`
  - `AzureProvider`
- `TranslationCoordinator`：
  - 2 并发
  - 80 条缓存
  - 请求版本号丢弃过期结果
  - 任一失败取消其余
- `TranslationOverlayRenderer`：
  - CoreGraphics 透明层
  - 背景中位数采样
  - 前景对比度采样
  - 二分字号
  - 标注层最后绘制
- `TextImageRenderer`：
  - 用 NSAttributedString 解析 HTML
  - CoreText 排版
  - 保留 margin/maxWidth/30000 高度上限/背景前景色配置

---

## 8. 测试文件体现的行为契约

### 8.1 `SelfTest.Ocr.cs`

`/Users/lusheng/Documents/开源工具/SnipLite/tests/SnipLite.SelfTest/SelfTest.Ocr.cs`

**OCR 数据模型契约**（第 95-118 行）：

- 字符拼接必须保留空格和换行：
  - `"中文" + NewLine + "A B"`
- 反向选择：
  - `GetText(2,1) == "文" + NewLine + "A"`
- 部分选择：
  - `GetText(3,4) == " B"`
- 命中测试：
  - `HitTest(new(31,15)) == 1`
- 引擎设置：
  - `OcrEngineKind.Windows` JSON 往返
  - 默认引擎必须是 `SimdPaddle`

**增强引擎精度契约**（第 16-41 行）：

- 公开样例：
  - `text_rec.jpg` → “韩国小馆”
  - `en_rec.jpg` → 英文长句
  - `short.png` → “中国网络空间安全”
  - `text_cls.jpg` → 倒置“怪我咯”
- 自绘中英混合浅色/深色样例 → 精确匹配
- 空白图 → 空文本，无误报
- 增强引擎必须匹配；Windows 引擎不强制匹配，只检查几何和稳定性

**几何契约**（第 63-89 行）：

- 每个字符框非空
- 左/上 >= 0
- 右 <= 图片宽 + 0.1
- 下 <= 图片高 + 0.1
- 同一图片重复识别文本稳定
- 输出 `ocr-smoke.json`

**可移植性**：

- `CheckOcrGeometry` 可直接移植到 macOS。
- 公开图片测试可改为 Vision 精度回归，但预期文本需要按 Vision 实际能力调整；“增强引擎必须匹配”的严格性不应直接套到 Vision。
- 大图坐标映射、空白图、混合中英文、倒置文字都值得保留为 Mac 回归用例。

### 8.2 `SelfTest.TextEditing.cs`

`/Users/lusheng/Documents/开源工具/SnipLite/tests/SnipLite.SelfTest/SelfTest.TextEditing.cs`

这些是截图内标注文字的编辑契约，不是 `TextImageRenderer`：

- 点击文字按字符位置重新打开编辑（第 50-52 行）
- 编辑期间隐藏已提交的标注层（第 54-56 行）
- 插入文字更新同一个 TextShape（第 57-59 行）
- Undo/Redo 恢复文本（第 60-61 行）
- 鼠标拖动选择字符区间（第 62-64 行）
- 替换选中文本（第 65-67 行）
- 取消编辑保留原文本（第 68-71 行）
- 字号变化时光标和原生 I-Beam 鼠标指针尺寸跟随（第 72-80 行）
- 拖动文字边框保留移动行为（第 89-97 行）
- Unicode 契约（第 98-111 行）：
  - 空格、换行、组合字符（`e\u0301`）、emoji、中文
  - 每个 grapheme 的 caret 位置经过 HitTest 能往返
  - CRLF 被正确处理
- Mac 版若保留截图标注文字，应移植为 CoreText caret/hit-test 测试；对 `TextImageRenderer` 则应单独增加 grapheme/HTML/换行/高度上限测试。

### 8.3 `SelfTest.Translation.cs`

`/Users/lusheng/Documents/开源工具/SnipLite/tests/SnipLite.SelfTest/SelfTest.Translation.cs`

**OCR 命中容差契约**（第 20-31 行）：

- 第一个字符左侧边缘外 8px 可命中
- 最后一个字符右侧边缘外 8px 可命中
- 字符上方 8px 可命中
- 两个字符之间按最近距离选择，不选择第一个扩展框
- 远离所有字符的空白不选择
- `nearest: true` 时可以吸附到最近字符

**本地化**（第 32 行）：

- `文字识别 → OCR`
- `识别引擎 → OCR engine`

**Provider HTTP 契约**：

- MyMemory（第 343-372 行）：
  - 500 UTF-8 字节上限
  - 不跨换行
  - emoji 不拆
  - `langpair` / `q` 编码
  - auto 报错且不发请求
  - `quotaFinished` 报额度错误
- Bing（第 36-43 行，可选 live）：
  - 两个并行请求共享会话
  - `auto` 检测为 `en`
  - 译文包含“世界”“早上”
- Microsoft（第 44-71 行）：
  - POST、key/region header、body `Text`
  - URL query `api-version=3.0&to=zh-Hans`
  - 检测语言 `zh-Hant → zh-TW`
  - 显式 `zh-TW → from=zh-Hant`
  - 无 key 不发请求
  - 401 不泄露密钥
- Google（第 73-97 行）：
  - 多段拼接
  - query 编码
  - 同语言不发网络
  - 取消不发请求
  - 429/网络/非法 JSON
  - 600 字符分段、保留 Unicode、代理对不拆

**UI 布局契约**（第 99-140 行，scale 1/1.5/2）：

- 翻译模式工具栏在屏幕内
- 完整工具栏保留：rect/pen/ocr/qr/undo/save/pin/copy
- OCR 模式完整工具栏保留
- OCR 状态行和复制按钮独立于主工具栏
- 翻译面板只有一行，高度 `44 * scale`，没有 TextBox
- 默认源 `en`、目标 `zh-CN`
- 默认显示译文
- 单个眼睛图标切换原文/译文
- 语言菜单高度 <= 284，首项“自动检测语言”，共 12 项
- auto 源交换时使用检测语言
- 目标语言永远不是 auto

**覆盖层契约**（第 297-324 行）：

- 合并自动换行的两行，不合并不同栏位的独立标签
- 覆盖层外部透明
- 覆盖层文字区域 alpha 不透明，不出现字形透明孔
- 合成后文字区域外的背景像素保持不变
- 深色/浅色背景都要通过

**Capture 集成契约**（第 149-295 行）：

- 新语言/新请求会取消旧请求
- 旧结果迟到不会覆盖最新结果
- Esc 取消请求、关闭面板、返回编辑、不结束截图
- 翻译服务菜单列出首选项中的服务
- 切换 provider 复用 OCR 文本、取消旧结果、不改变首选项默认值
- OCR 文本能传到 provider
- 翻译结果可用于覆盖层
- 导出像素确实改变
- 切换原文恢复完全相同的像素
- 翻译按钮保持选中且完整工具栏可用
- 标注工具在翻译期间仍可操作
- 新标注绘制在译文之上
- 任一块失败会停止剩余 block，并显示错误
- 关闭翻译恢复原始像素
- OCR 边缘悬停显示 I-Beam
- OCR 边缘拖动选中完整文本
- 点击工具栏其他工具退出 OCR 并恢复编辑
- 可选 live：Google、Bing、MyMemory 实际请求

**测试入口**：

`/Users/lusheng/Documents/开源工具/SnipLite/tests/SnipLite.SelfTest/Program.cs:19-21`

- `--text-test`
- `--ocr-smoke <imageDir>`
- `--translation-test [--live] [--bing-live] [--mymemory-live]`

### 8.4 文档中的回归范围

`/Users/lusheng/Documents/开源工具/SnipLite/docs/OCR_TRANSLATION_PLAN.md:32`

- 文档提到现有 123 项桌面回归，覆盖划词逻辑、空白图、大图坐标、扫码和原有编辑交互。
- 这些测试是 Windows/WinForms 专用，不能直接在 macOS 运行；但其中的纯逻辑断言可以迁移为 Swift XCTest：
  - `OcrDocument` 文本/命中测试
  - 分段函数
  - 语言映射
  - 覆盖层分块
  - 背景/前景采样
  - 请求 URL/方法/header/body
  - 取消与过期结果
  - 像素恢复和标注层级
- UI 布局断言可以用 macOS 快照测试或几何断言替代。

---

## 关键结论

1. Windows 版 OCR 的核心是 PaddleOCR + CTC 字符对齐，数据模型是“行框 + 字符框 + Prefix”，坐标是裁剪区域物理像素，不保存置信度，不主动排序。
2. 划词交互完全建立在字符索引区间和 `HitTest` 上；macOS 只需把 Vision 的行级结果转换成同样的字符级 `OcrDocument`，交互层可复用。
3. 二维码使用 ZXing 全格式、单结果；Vision 可直接替代常见格式，但格式覆盖和 `TryHarder/TryInverted` 能力有差距。
4. 四个翻译 provider 都是轻量 HTTP 封装，没有统一 SDK；必应网页翻译的关键是 HTML 正则提取 `params_AbusePreventionHelper`、`IG`、`IID` 并缓存匿名会话。
5. 翻译 UI 的独特价值在“原位覆盖”：按 OCR 行块合并段落、采样背景/前景色、二分字号、透明层叠加，标注始终在上层。这部分在 macOS 上需要用 CoreGraphics/CoreText 重写并做像素级回归。
6. 最适合直接迁移的是纯逻辑层：`OcrDocument`、分块算法、语言映射、provider 请求契约、覆盖层分块启发式；最需要重写的是 UI、渲染、OCR 推理和凭据存储。
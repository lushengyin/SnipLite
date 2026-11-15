# SnipLite macOS

原生 Swift + AppKit 的 macOS 版本。移植方案与阶段划分见 [docs/PORT_PLAN.md](docs/PORT_PLAN.md)。

当前进度：**核心功能完成**——截图、标注、OCR 划词与结果面板、二维码、四家翻译（原位覆盖）、贴图（分组/穿透/拖出）、首选项、历史均已接通；待办只剩 Developer ID 签名与公证。

## 环境

- macOS 15.0+
- Xcode 26 / Swift 6.2
- XcodeGen（`brew install xcodegen`）

## 构建

```bash
xcodegen generate
xcodebuild -project SnipLite.xcodeproj -scheme SnipLite -configuration Debug build
```

产物在 `~/Library/Developer/Xcode/DerivedData/SnipLite-*/Build/Products/Debug/SnipLite.app`。
也可以直接 `open SnipLite.xcodeproj` 用 Xcode 运行。

## 测试

```bash
xcodebuild -project SnipLite.xcodeproj -scheme SnipLiteCore -configuration Debug test
```

纯逻辑（设置、文件名模板、OCR 文档、翻译分段、覆盖层算法）都在 `SnipLiteCore` 里，测试不需要启动 UI。

## 目录

```
Sources/SnipLiteCore/   无 UI 的模型与算法
Sources/SnipLite/       应用本体（菜单栏、截图、贴图、首选项）
Tests/                  XCTest
```

## 签名

开发期使用本地自签名证书 `SnipLite Local Signing`（存放在 `~/Library/Keychains/sniplite-signing.keychain-db`，密码 `sniplite`），
避免每次重新编译后 macOS 把「屏幕录制」权限重置。`run.sh` 会自动解锁该钥匙串。
正式发布需要换成 Developer ID 证书并公证。

## 运行配置

- 设置：`~/Library/Application Support/SnipLite/settings.json`
- 日志：`~/Library/Application Support/SnipLite/app.log`
- 应用为菜单栏应用（`LSUIElement`），无 Dock 图标。若图标没出现，先检查菜单栏管理工具（如 Ice）是否把它收进了隐藏区。

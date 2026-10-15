<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="WallePDFReader logo" />

# WallePDFReader

最简洁的 macOS 原生 PDF / Markdown 阅读器 · 多 Tab · 断点续读

</div>

## 安装

[**↓ 下载最新版 DMG**](https://github.com/sangwf/WallePDFReader/releases/latest)

1. 双击 `.dmg` 挂载
2. 把 `WallePDFReader.app` 拖到 `Applications` 文件夹（旁边的快捷方式）
3. **第一次打开**：在 Finder 里**右键 `WallePDFReader.app` → 打开**，弹窗里再点「打开」
   - macOS Gatekeeper 要求绕过，因为这是开发者本地签名版本（没有付费 Apple Developer 证书）
   - 之后双击就能正常用

## 功能

- **多 Tab** — 类 Chrome 的 tab 栏，`+` 按钮紧跟最后一个 tab
- **多种打开方式** — 拖入 / 点击首页 / `⌘O` / 双击 PDF
- **断点续读** — 关掉再开自动跳到上次的页面与位置（每个文件单独记忆，存在 `~/Library/Application Support/WallePDFReader/`）
- **单窗口** — 双击其它 PDF 自动追加为新 tab，不再开多余窗口
- **全屏演示模式**（v1.2）— 进全屏自动切单页（整页铺满，不会露出上下页），退出全屏自动回连续滚动，当前页码保持不变。翻页：`→` `↓` `Page Down` `空格` `回车` 下一页，`←` `↑` `Page Up` `Delete` 上一页，`Home` / `End` 首末页，滚轮/触控板也能翻。`ESC` 退出演示
- **翻页即时清晰**（v1.2）— PDFKit 单页模式下每翻一页都要先贴低分辨率代理图再后台精修，看着像分辨率慢慢变高。演示模式下改为自己按屏幕实际像素预渲染前 3 后 1 页，翻页直接换上成品位图，没有变清晰的过程
- **区域截图**（v1.1）— `⌘⇧S` 进入截图模式，拖框选区，**双击选区直接复制**（仿微信），或者用 `[Copy] [Save…] [Cancel]` 浮窗操作；`Enter` 也是 Copy、`ESC` 取消。基于 PDF 矢量源渲染，输出永远清晰
- **Markdown 阅读**（v1.4）— `.md` / `.markdown` 文件和 PDF 一样以 tab 打开，GitHub 风格排版并跟随系统深色模式。支持表格、任务列表、代码块、删除线、内嵌 HTML，YAML front matter 自动隐藏。相对路径的图片正常显示；点击指向其它 `.md` / `.pdf` 的链接在新 tab 打开，网页链接交给浏览器。同样记忆滚动位置
- **重复打开即刷新**（v1.3）— 双击一个已经打开的文件，会从磁盘重新加载并保持阅读位置，适合反复导出的文档
- **可设为系统默认 PDF 应用**（见下）

PDF 的渲染、缩放、滚动、文本选择全部交给 macOS 原生 `PDFKit`；Markdown 用系统自带的解析器（`AttributedString(markdown:)`）转成 HTML，再由 `WKWebView` 显示。所有功能零按钮，全部走菜单 + 快捷键，主界面始终干净。

## 设为默认 PDF 应用

```bash
swift Tools/SetDefault.swift
```

或在 Finder 里右键任意 PDF → 显示简介 (⌘I) → 展开「打开方式」→ 选 `WallePDFReader` → 「全部更改…」。

## 从源码构建

需要 Xcode 命令行工具（含 Swift 编译器）。

```bash
./build.sh                    # 编译 Swift + 打包成 WallePDFReader.app
./Tools/MakeDMG.sh            # 上面那步 + 打成可分发的 DMG
```

修改了图标设计想重新生成时：

```bash
rm Build/AppIcon.icns         # 删掉缓存
./build.sh                    # 自动重跑 Tools/MakeIcon.swift
```

## 项目结构

```
Sources/PDFReader.swift     SwiftUI App、tab 管理、PDFKit 阅读/演示/截图
Sources/Markdown.swift      Markdown → HTML 渲染 + WKWebView 阅读视图
Tools/MakeIcon.swift        Core Graphics 程序化生成 AppIcon
Tools/MakeDMG.sh            一键打 DMG
Tools/SetDefault.swift      设为系统默认 PDF 处理程序
Info.plist                  Bundle 元数据
build.sh                    编译 + 打包 .app
```

## 技术栈

SwiftUI + PDFKit + WebKit。零第三方依赖，整个 .app 不到 1 MB。

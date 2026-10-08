# 空当接龙 · FreeCell

使用 Swift 6、SwiftUI 工具栏与 AppKit 牌桌编写的原生 macOS 纸牌游戏，支持 macOS 14 及以上。

## 运行

已构建的应用位于 `build/FreeCell.app`，可直接双击打开。

从源码构建并运行：

```sh
./scripts/build-app.sh
open build/FreeCell.app
```

脚本默认构建 Release，使用本机临时签名。需要 Apple Command Line Tools 或 Xcode；无需第三方依赖。当前已验证环境为 Apple Silicon、Swift 6.3.3、macOS 26 SDK。包声明的最低系统为 macOS 14，但尚未在实际 macOS 14 机器上运行。

在 Xcode 中打开 `Package.swift` 即可浏览、编辑和运行 Swift Package；正式 `.app` 打包使用上述脚本。这里采用 Swift Package 的应用/核心双目标组织，没有另建 `.xcodeproj`。可用 `./scripts/build-app.sh debug` 构建调试版。

## 功能与操作

- 经典 8 个工作列、4 个空当、4 个按花色基础堆，全部明牌。
- 点击选牌后点击目标，或拖动单牌／有序牌组；拖动的牌面完全不透明、来源位置隐藏所拖牌，整组按原重叠间距跟随鼠标。工作列按点数递减、红黑交替。
- 双击按“基础堆 → 非空工作列 → 空当 → 空列”顺序自动移动，同类目标优先最左侧；暂存牌跳过其他空当，优先接牌后转入空列；没有目标时晃动提示。
- 基础堆最上方的一张牌可移回工作列，遵守红黑交替递减或空列规则；取回操作不会立即触发自动收牌，可撤销、重做。
- 整组移动遵守空当及空列容量；空目标列不会被重复计作中转列。
- 新局、同局重开、自有编号复现、撤销与重做。
- 合法动作提示、手动安全收牌、可关闭的保守自动收牌。
- 步数、有效游戏计时、暂停、胜利彩纸动画与自动存档恢复；胜利后直接开始新局。
- 收牌与双击自动移动有牌面飞行过渡，批量收牌依次播放；动画不改变一次撤销的事务边界。
- `Ctrl + Cmd + F` 进入／退出 macOS 原生全屏独立空间。
- 无滚动条：纸牌保持264:384比例，同时受窗口宽、高和最长牌列约束自动缩放；牌桌不显示列号或槽位文字，仍保留中文牌名、VoiceOver标签与减少动态效果支持。

快捷键：`⌘Z` 撤销，`⇧⌘Z` 重做，`⇧⌘H` 提示，`⌘K` 安全收牌，`⌘P` 暂停，`⌃⌘F` 切换原生全屏，`Esc` 取消选择。Tab/Shift-Tab 切换控件焦点；牌桌内使用方向键切换牌，空格选牌或确认目标，回车自动移动；按钮参与 Tab 导航的行为也受 macOS 键盘导航偏好影响。规则按钮提供完整操作说明。

自动收牌默认关闭。一次用户动作及其自动收牌组成一个撤销事务。提示是局部启发式，不保证牌局可解；本游戏编号不兼容 Microsoft 编号。

计时在手动暂停、切到其他应用及胜利时停止；系统睡眠或长调度间隔不计入。撤销不倒转累计时间。

## 验证

```sh
swift run FreeCellChecks
swift run -c release FreeCellChecks
swift build --product FreeCell
./scripts/build-app.sh
codesign --verify --deep --strict build/FreeCell.app
```

规则验证程序位于 `Tests/FreeCellCoreTests`，失败返回非零退出码；覆盖合法／非法移动、容量边界、单牌拆解证明、固定洗牌结果、52张牌完整胜利流程、历史分支、存档往返及损坏数据，以及双击优先级、基础堆取回、窗口布局边界、收牌动画顺序及整组动画坐标，共27组检查。当前机器不包含 Swift Testing/XCTest 模块，因此使用不依赖测试框架的独立验证目标 `FreeCellChecks`，不用 `swift test`。没有为此引入网络依赖或安装 Xcode。

界面验证可在独立临时存档中启动：

```sh
open -n build/FreeCell.app --args --verification
```

该模式使用系统临时目录 `FreeCell-Verification`，不写正常存档。不要同时启动多个使用同一存档的进程。

## 工程结构

```text
Package.swift
Sources/FreeCellCore/          牌、局面、规则、发牌、历史与存档模型
Sources/FreeCellPresentation/  与平台输入无关的牌桌几何与命中计算
Sources/FreeCellApp/           SwiftUI工具栏、AppKit牌桌、会话与存档服务
Sources/FreeCellApp/Resources/ 52张牌面
Tests/FreeCellCoreTests/       独立规则验证程序
App/                          macOS Bundle配置
scripts/build-app.sh          Debug/Release打包与本机签名
docs/                         规则、设计、资源清单与验收记录
```

规则核心不依赖 SwiftUI/AppKit。GameSession 在 MainActor 管理会话；后台 actor 串行原子保存，并用修订号拒绝过期写入。退出时等待最终保存。牌ID由花色和点数生成，拖拽在牌桌内绘制完整牌组，携带局面版本，过期或取消的拖动不执行。单击提交等待系统双击时间以避免第一下误移牌，快速点击不同位置会先完成前一单击。

正常存档：`~/Library/Application Support/FreeCell-Swift/game-v1.json`。存档包括初始局面、当前局面、历史、牌局编号、版本、偏好及累计时长。坏档保留为同目录的 `unreadable-*.json`；无法备份时暂停自动保存，避免覆盖。可通过“牌局 → 打开存档目录”查看。

## 文档与资源

- [规则与算法](docs/01-FreeCell规则与算法.md)
- [Swift工程实践](docs/02-Swift工程最佳实践.md)
- [开发计划](docs/03-开发计划.md)
- [首版实现与验收记录](docs/04-实现与验收记录.md)
- [1.1交互调整与验收记录](docs/05-交互调整与验收记录.md)
- [1.2动画与全屏验收记录](docs/06-动画与全屏验收记录.md)
- [牌面映射清单](docs/card-resources.json)
- [52张牌面预览](docs/previews/deck-contact-sheet.jpg)

牌面取自用户提供的 `Full Deck Solitaire.app/Contents/Resources/1.png` 至 `52.png`，尺寸264×384。顺序：梅花、方块、红桃、黑桃，每种花色A到K。原App未修改。图片属于GRL Games提供的原App资源；工程没有授予这些图片新的再分发许可，公开发行前需确认授权。

动画期间牌桌暂停接收移动，工具栏仍可用于撤销、暂停、重开或新局；这些操作会取消当前播放并显示最新真实局面。调整窗口或切换到其他应用也会结束动画。系统“减少动态效果”开启时跳过飞牌、彩纸与缩放，仍展示胜利提示。

### 1.3.0 布局与焦点调整

纸牌尺寸只由窗口决定，底部预留十三张牌的常规叠放空间。超长列独立压缩叠放间距，不再缩小整桌纸牌。圆角按素材的 16/264 宽度比例绘制。点击空白处取消选择与焦点；移牌后的列焦点落在最后一张牌。

### 应用图标

应用使用 [Lorc 的 Poker Hand 图标](https://game-icons.net/1x1/lorc/poker-hand.html)，许可为 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)，搭配深绿色圆角背景。署名与改动说明见 `App/IconSources/ATTRIBUTION.txt`，也随应用打包。运行 `swift scripts/generate-icon.swift` 可重新生成预览与全部 macOS 图标尺寸。

### Dock 图标（1.3.2）

启动时通过 AppKit 显式设置应用图标。打包应用加载 `FreeCell.icns`，直接运行 SwiftPM 可执行文件时加载其资源包中的 `AppIcon.png`。两种启动方式均携带图标和署名，避免调试程序在 Dock 中显示默认占位图。更新后需退出已有实例，再打开 `build/FreeCell.app`。

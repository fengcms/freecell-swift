# 空当接龙 · FreeCell

默认中文说明文档。游戏支持九种语言，可在设置中切换。

使用 Swift 6、SwiftUI 工具栏与 AppKit 牌桌编写的原生 macOS 纸牌游戏，仅支持搭载 M 系列芯片的 Apple Silicon Mac（arm64），要求 macOS 14 及以上；不提供 Intel Mac 或 Windows 版本。

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
- 双击按“基础堆 → 非空工作列 → 空当/空列（可在设置中选择优先级）”自动移动，同类目标优先最左侧；暂存牌跳过其他空当，优先接牌后转入空列；没有目标时晃动提示。
- 基础堆最上方的一张牌可移回工作列，遵守红黑交替递减或空列规则；取回操作不会立即触发自动收牌，可撤销、重做。
- 整组移动遵守空当及空列容量；空目标列不会被重复计作中转列。
- 新局、同局重开、自有编号复现、撤销与重做。
- 合法动作提示、手动安全收牌、可关闭的保守自动收牌。
- 步数、有效游戏计时、暂停、胜利彩纸动画与自动存档恢复；胜利后锁定牌桌并显示居中的庆祝界面，可点击大按钮、按空格或右击直接开始新局。
- 收牌与双击自动移动有牌面飞行过渡，批量收牌依次播放；动画不改变一次撤销的事务边界。
- `Ctrl + Cmd + F` 进入／退出 macOS 原生全屏独立空间。
- `⇧⌘S` 打开统计窗口：查看胜率、连胜、个人纪录、对局历史与同编号成绩，按周/月浏览趋势；支持本地 JSON 导入、合并、替换和重置。
- 无滚动条：纸牌保持264:384比例，仅随窗口宽、高缩放，长列独立压缩间距；牌桌不显示列号或槽位文字，仍保留中文牌名、VoiceOver标签与减少动态效果支持。

快捷键：`⌘Z` 撤销，`⇧⌘Z` 重做，`⇧⌘H` 提示，`⌘K` 安全收牌，`⌘P` 暂停，`⌃⌘F` 切换原生全屏，`Esc` 取消选择。Tab/Shift-Tab 切换控件焦点；牌桌内使用方向键切换牌，空格选牌或确认目标，回车自动移动；按钮参与 Tab 导航的行为也受 macOS 键盘导航偏好影响。规则按钮提供完整操作说明。

自动安全收牌默认开启，可在设置中关闭。一次用户动作及其自动收牌组成一个撤销事务。提示是局部启发式，不保证牌局可解；本游戏编号不兼容 Microsoft 编号。

计时在手动暂停、切到其他应用及胜利时停止；系统睡眠或长调度间隔不计入。撤销不倒转累计时间。

## 验证

```sh
swift run FreeCellChecks
swift run -c release FreeCellChecks
./scripts/check-localization.sh
swift build --product FreeCell
./scripts/build-app.sh
codesign --verify --deep --strict build/FreeCell.app
```

规则验证程序位于 `Tests/FreeCellCoreTests`，失败返回非零退出码；覆盖合法／非法移动、容量边界、单牌拆解证明、固定洗牌结果、52张牌完整胜利流程、历史分支、存档往返及损坏数据，以及双击优先级、基础堆取回、窗口布局边界、收牌动画顺序及整组动画坐标，共31组检查。当前机器不包含 Swift Testing/XCTest 模块，因此使用不依赖测试框架的独立验证目标 `FreeCellChecks`，不用 `swift test`。没有为此引入网络依赖或安装 Xcode。

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
- [多语言支持与验收](docs/10-多语言支持与验收.md)
- [牌面映射清单](docs/card-resources.json)
- [52张牌面预览](docs/previews/deck-contact-sheet.jpg)

牌面采用 [Vector-Playing-Cards](https://github.com/notpeter/Vector-Playing-Cards) 的 Byron Knoll 公共领域素材，上游允许再分发及商业使用，并提供 WTFPL 备用许可。52 张原始 SVG、上游说明和固定提交版本保存在 `App/CardSources/`；游戏 PNG 为 528×768，顺序仍为梅花、方块、红桃、黑桃，每种花色 A 到 K。完整来源见 [第三方素材说明](THIRD_PARTY_NOTICES.md)。现用牌面和预览图已全部替换，不再使用 Full Deck Solitaire 的图片。

动画期间牌桌暂停接收移动，工具栏仍可用于撤销、暂停、重开或新局；这些操作会取消当前播放并显示最新真实局面。调整窗口或切换到其他应用也会结束动画。系统“减少动态效果”开启时跳过飞牌、彩纸与缩放，仍展示胜利提示。

### 1.3.0 布局与焦点调整

纸牌尺寸只由窗口决定，底部预留十三张牌的常规叠放空间。超长列独立压缩叠放间距，不再缩小整桌纸牌。该版本圆角按当时素材的 16/264 宽度比例绘制；1.5.0 已改为新素材的圆角比例。点击空白处取消选择与焦点；移牌后的列焦点落在最后一张牌。

### 应用图标

应用使用 [Lorc 的 Poker Hand 图标](https://game-icons.net/1x1/lorc/poker-hand.html)，许可为 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)，搭配深绿色圆角背景。署名与改动说明见 `App/IconSources/ATTRIBUTION.txt`，也随应用打包。运行 `swift scripts/generate-icon.swift` 可重新生成预览与全部 macOS 图标尺寸。

### Dock 图标（1.3.2）

启动时通过 AppKit 显式设置应用图标。打包应用加载 `FreeCell.icns`，直接运行 SwiftPM 可执行文件时加载其资源包中的 `AppIcon.png`。两种启动方式均携带图标和署名，避免调试程序在 Dock 中显示默认占位图。更新后需退出已有实例，再打开 `build/FreeCell.app`。

### 设置与声音（1.4.0）

通过应用菜单的 Settings…（设置）、⌘, 或底部齿轮打开标准设置窗口。六项设置即时生效并跨牌局保存：自动安全收牌默认开启，自动移牌默认双击，空位默认优先空当（可切换为优先空列），动画默认中等，背景音乐与移牌音效默认开启，按钮快捷键默认隐藏。自动移牌可改为右击；回车不受此设置影响。动画有无、慢、中等、快四档，系统“减少动态效果”仍优先生效。

底部采用单行设置摘要，例如“自动收 · 双击 · 动画中 · 音乐开 · 音效开 · 快捷键隐”。原操作状态可通过悬停摘要和辅助功能读取；保存错误仍直接显示。按钮快捷键开启后，在足够宽的窗口中保持单行，在窄窗口中自动分两行。

音乐采用 [Dream Culture — Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300046)，许可 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，低音量循环播放。移牌声采用 [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) 的 click_003.wav（CC0）。音频随应用打包，离线可用，署名在设置窗口和 Audio/ATTRIBUTION.txt 中。暂停或切出应用时暂停音乐，继续游戏时从原播放位置恢复。合法移动、收牌、撤销和重做播放一次短音效，非法操作不播放。

偏好通过 UserDefaults 独立保存于 local.fungleo.FreeCell.preferences 域；旧牌局存档继续兼容，偏好中的自动收牌设置优先于旧存档。验证模式使用独立偏好域与存档目录，不修改正常牌局。

### 确认框与关于游戏（1.4.1）

新局和重开的确认框支持回车确认、Esc 或 ⌘C 取消。⌘C 仅在该确认框打开时作为取消操作，不改变其他窗口的复制快捷键。胜利后新局仍直接开始。

应用菜单“关于空当接龙”打开独立窗口，完整显示游戏简介、版本、作者 Fungleo、个人签名“键鼠轻游戏人间 风流谈笑傲江湖”，以及 GitHub 仓库和个人博客的可点击链接。

已使用独立验证实例检查回车确认新局和重开、⌘C 取消新局、Esc 取消重开；取消后原牌局编号保留。关于窗口的文字和链接已完成界面检查，最终 Release 应用已打包并验证签名。

### 发布准备（1.6.1）

源码使用 [MIT 许可证](LICENSE)，第三方素材按各自许可分发。作者：Fungleo；签名：键鼠轻游戏人间 风流谈笑傲江湖；[个人博客](http://fungleo.com)。

可通过 [GitHub Releases](https://github.com/fengcms/freecell-swift/releases) 分发独立应用，无需 Apple 开发者会员。[1.6.1 下载页](https://github.com/fengcms/freecell-swift/releases/tag/v1.6.1)提供 `FreeCell-1.6.1-macOS-AppleSilicon.dmg` 安装镜像、ZIP 备用包和 SHA-256 校验文件。打开 DMG 后将 FreeCell 拖入“应用程序”即可安装；GitHub 的 Source code 压缩包是源码，不能直接运行。

下载后解压，将 FreeCell.app 拖入“应用程序”后打开。应用使用临时签名，未经 Apple Developer ID 签名与公证；若首次打开被阻止，在确认下载自本仓库正式 Release 后，进入“系统设置 → 隐私与安全性”，点击“仍要打开”，按系统提示确认。详见 [Apple 首次打开说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)。不需要关闭 Gatekeeper。

发布前检查、安装说明和版本发布文案见 [GitHub 发布准备](docs/09-GitHub发布准备.md)。胜利后的结束状态与快捷操作见[胜利界面说明](docs/15-胜利状态与庆祝界面.md)。牌面采用已确认的浅暖渐变纸色、加粗留白角标；数字牌中央图案相对原版缩小12%，A及人物牌使用独立比例，J/Q/K居中放大并去掉人物外围黑框，以兼顾完整牌面和正常叠放时的头部可见性；角标梅花采用标准三瓣形。重新生成牌面仅开发时需要 Python 3、Node.js 与 sharp：`npm install --prefix /tmp/freecell-card-tools sharp`，然后依次运行 `SHARP_MODULE=/tmp/freecell-card-tools/node_modules/sharp python3 scripts/style-cards.py` 和 `SHARP_MODULE=/tmp/freecell-card-tools/node_modules/sharp node scripts/generate-cards.cjs`。正常构建和运行不依赖 Node.js。

### 多语言（1.6.0）

支持 English、简体中文、繁體中文、Français、Deutsch、Español、العربية、日本語、한국어。通过 ⌘, 打开设置，在“界面 → 语言”选择；默认跟随系统首选语言，不受支持时使用英语。选择立即生效并在重启后保留，已有牌局存档继续兼容。

主界面、菜单、对话框、规则、状态、错误提示、关于游戏和辅助功能牌名均提供翻译。阿拉伯语使用从右向左的文字布局，牌桌列顺序保持一致。README 默认使用简体中文。1.6.0 在此版本加入九种界面语言；版本包提供 Apple Silicon Mac 下载。

### 统计

通过工具栏“统计”或“牌局 → 统计…”（`⇧⌘S`）打开独立窗口。统计只在第一次有效操作后开始，覆盖对局胜负、胜率、连胜、最少步数、最快与平均用时、累计时间、活跃天数、辅助操作、同编号挑战和最近 8 周／12 个月趋势。对局历史支持结果、无辅助及日期筛选，并可从记录重新挑战。

“无辅助”纪录按本应用公开的资格条件单独计算。统计保存在本机 `statistics-v1.json`，不包含牌桌存档；可导出、导入合并或替换。重置统计不会删除当前牌局或游戏偏好，当前牌局在本轮统计周期内排除，下一局或重开后重新记录。详细口径、迁移与数据边界见[统计产品方案](docs/13-游戏统计产品设计方案.md)和[开发验收记录](docs/14-游戏统计开发与验收记录.md)。

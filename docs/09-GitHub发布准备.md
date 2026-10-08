# FreeCell 1.6.0 GitHub 发布准备

## 发行方式

通过 [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) 上传可直接运行的 macOS 应用附件，不要求 Apple 开发者会员。GitHub 提供下载托管，不提供 Apple Developer ID 签名或公证。本项目暂用 ad-hoc 临时签名，因此首次下载打开可能需要用户在系统设置中允许。

当前发布版本为 v1.6.0，附件为 FreeCell-1.6.0-macOS-AppleSilicon.zip 和 SHA256SUMS.txt。使用 scripts/package-release.sh 可重新构建、打包并生成校验值。

## 支持范围与安装说明

- 仅支持搭载 M 系列芯片的 Apple Silicon Mac（arm64）。不支持 Intel Mac、Windows。
- 要求 macOS 14 或更新版本；最低版本来自工程配置，尚未在 macOS 14 实机验收，应在正式发布说明中保留该信息，或将最低版本调整为实测版本。
- 从 https://github.com/fengcms/freecell-swift/releases 下载正式版本的应用附件；不要把 Source code 压缩包当作应用。
- 解压下载文件，将 FreeCell.app 拖入“应用程序”，双击打开。
- 如果系统阻止首次启动，确认下载来源和版本后，打开“系统设置 → 隐私与安全性”，找到该应用的拦截提示并点击“仍要打开”，按系统要求认证并确认。此入口通常在尝试启动后出现，具体提示因 macOS 版本而异。参考 [Apple 官方说明](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac)。无需关闭系统安全保护。

## 发布验收与后续事项

1. 处理公共 Git 历史中的旧商业牌面及旧预览图。当前工作树已替换，历史提交仍保留旧文件；历史清理会改变提交 ID，需提前协调协作者及现有克隆。本次没有重写或强制推送历史，当前 Release 的应用包仅包含新牌面。
2. 在应用副本中测试实际下载、解压及首次启动，并在另一台 M 系列 Mac 验证独立运行、图标、全部资源、音频和存档。当前本机构建验收不能替代下载后的 Gatekeeper 验收。
3. 确认最低 macOS 版本的实测支持范围。
4. 后续制作 arm64 应用 ZIP 或 DMG，保留临时签名、所有资源与第三方声明；生成 SHA-256 校验值，命名中注明 Apple Silicon。
5. 已完成源码与文档提交、推送，并创建 `v1.6.0` 标签及 GitHub Release，上传应用附件与校验值。`.build` 和本机构建目录不纳入 Git。

## Release 文案草稿

标题：FreeCell 1.6.0 · macOS 空当接龙

Fungleo 编写的原生 macOS 空当接龙。支持整组拖牌、自动移牌、安全收牌、撤销与重做、原生全屏、动画、背景音乐与设置。

本版增加英语、简体中文、繁体中文、法语、德语、西班牙语、阿拉伯语、日语和韩语界面，可跟随系统语言或在设置中切换；并改进牌桌交互及存档保护。既有牌局存档继续兼容。

仅支持 M 系列 Apple Silicon Mac，要求 macOS 14 及以上（macOS 14 尚未实机验证）。本应用使用临时签名，未经过 Apple Developer ID 签名与公证。首次打开若被阻止，请根据 README 的“隐私与安全性 → 仍要打开”步骤操作。

作者：Fungleo  
键鼠请游戏人间 风流谈笑傲江湖  
博客：http://fungleo.com  
源码：https://github.com/fengcms/freecell-swift  
源码许可：MIT；第三方素材按 THIRD_PARTY_NOTICES.md 中的各自许可分发。

附件：FreeCell-1.6.0-macOS-AppleSilicon.zip；SHA-256 见同版本的 SHA256SUMS.txt。下载页：https://github.com/fengcms/freecell-swift/releases/tag/v1.6.0 。本机验证环境为 macOS 26（实际具体版本见正式 Release 说明），未完成其他机器或 macOS 14 验收。

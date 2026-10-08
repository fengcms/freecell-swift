# FreeCell 开发实战 FC-09｜从 Swift 应用到 GitHub Release：签名、DMG 与安装说明

**本文目标**：记录一个没有 Apple Developer 会员的独立 macOS 项目，如何构建 Apple Silicon 应用、打成 DMG 和 ZIP，并通过 GitHub Release 交付给玩家。

---

## 一、能在开发机运行，不等于可以交付

Swift Package 的可执行文件还不是完整应用。macOS 应用包需要 `Info.plist`、图标、主程序、资源 bundle、牌面、音频和第三方声明。构建脚本将这些内容放进标准 `.app` 目录，再对应用执行 ad-hoc 临时签名。

构建限定 `arm64`，Release 前会再次检查二进制架构和签名完整性。项目只支持搭载 M 系列芯片的 Apple Silicon Mac；最低系统版本配置为 macOS 14，但不能把配置值说成已经在 macOS 14 实机验证。

## 二、临时签名能做什么，不能做什么

没有 Developer ID 签名和公证，仍然可以通过 GitHub 托管应用包，但不能声称它经过 Apple 公证。首次从网络下载时，macOS 可能阻止打开，用户需要先确认来源，再从“系统设置 → 隐私与安全性”允许应用运行。

安装说明应准确、克制：给玩家清楚步骤，不建议关闭 Gatekeeper，也不把临时签名描述成完整 Developer ID 身份。开发者需要在自己的支持范围内说明 CPU 架构、最低系统版本和未测试平台。

## 三、DMG 为什么比裸 ZIP 更像安装介质

ZIP 适合简单分发，但打开后需要用户自行把 `.app` 拖到应用程序目录。DMG 可以在一个只读磁盘镜像里同时放入应用和 `/Applications` 快捷方式，玩家打开后即可拖放安装。

打包脚本先重新构建应用，将 `.app` 复制到 DMG staging 目录，创建 `Applications` 符号链接，再通过 `hdiutil` 生成压缩只读镜像。原 ZIP 继续保留作为备用方式。DMG 视觉上是安装窗口，但它并不会替用户自动安装，也不会因为文件名叫 DMG 就自动可信。

## 四、校验值让下载后可核对

对 ZIP 和 DMG 分别计算 SHA-256，并写入同一份 `SHA256SUMS.txt`。用户下载完成后可以比较文件摘要，确认本地文件与发布附件内容一致。

这不能替代签名或公证，也不能证明项目没有恶意代码；它解决的是文件传输后是否与发布时的字节一致。每种措施作用不同，发布说明不要混为一谈。

## 五、Release 也要把“怎么安装”写清楚

正式发布时，GitHub Release 提供 DMG（推荐）、ZIP（备用）和校验文件。版本说明列出支持平台、系统要求、首次启动提示、作者信息、源码许可和第三方素材声明。GitHub 自动生成的 Source code ZIP 是源码，不是可运行应用，必须特别区分。

发布前还要挂载 DMG，检查里面确实有 `.app` 与 Applications 快捷方式；验证 ZIP 与 DMG 的 SHA-256；上传后再查看 Release 的资产列表和服务器侧摘要。只看到 `gh release upload` 命令没有报错，不应代替检查 GitHub 实际资产。

## 六、打包脚本让下次发布可复现

`package-release.sh` 执行 Release 构建、签名检查、架构检查、ZIP 归档、DMG staging、镜像生成和校验文件创建。把这些步骤编码进脚本，可减少人工步骤之间的不一致。正式版本应从已提交的源码和标签构建，并把生成物放在忽略的 build 目录，不把几十 MB 的应用包误提交到源码仓库。

## 相关资料

- [应用构建脚本](../../scripts/build-app.sh)
- [Release 打包脚本](../../scripts/package-release.sh)
- [发布准备与安装说明](../09-GitHub发布准备.md)
- [GitHub Releases](https://github.com/fengcms/freecell-swift/releases)

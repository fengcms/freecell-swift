# 第三方素材与许可

源码的 MIT 许可证不替代下列第三方素材的许可。再分发应用时保留这些说明及资源包中的署名文件。

| 素材 | 作者与来源 | 许可及使用情况 |
| --- | --- | --- |
| 52 张牌面 | Byron Knoll；[Vector-Playing-Cards](https://github.com/notpeter/Vector-Playing-Cards)，提交 `72cb5b288ed61251ef344e369446687cd51281a4` | Public Domain（公共领域）；上游在不认可公共领域的司法管辖区提供 WTFPL 备用许可。允许修改、再分发及商业使用。SVG 转为 528×768 PNG，按游戏 ID 命名。 |
| Poker Hand 应用图标 | [Lorc / Game-icons.net](https://game-icons.net/1x1/lorc/poker-hand.html) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)。添加绿色背景、调整布局并生成 macOS 图标尺寸。 |
| Dream Culture 背景音乐 | [Kevin MacLeod / incompetech.com](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300046) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。文件未修改，游戏中降低音量并循环播放。 |
| click_003.wav 移牌音效 | [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | [CC0](https://creativecommons.org/publicdomain/zero/1.0/)。文件未修改，降低播放音量。 |

牌面完整上游说明与原始 SVG 保存在 `App/CardSources/`；随应用分发的声明为 `Cards/ATTRIBUTION.txt`。图标说明为 `App/IconSources/ATTRIBUTION.txt`，音频说明为 `Resources/Audio/ATTRIBUTION.txt` 与 `Kenney-LICENSE.txt`。

当前版本不使用 Full Deck Solitaire 的商业牌面。早期 Git 提交仍可能包含旧素材；替换工作树不会删除 Git 历史中的内容。公开仓库的历史清理需另行处理，避免继续提供旧提交的素材下载；清理会改变提交 ID，需要协调后实施。

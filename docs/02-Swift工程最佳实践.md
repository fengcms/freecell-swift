# Swift 工程最佳实践：本项目约定

状态：首版实践基线；2026-10-07。最佳实践应服务于正确性、可维护性和实际规模，不以设计模式数量衡量。

## 1. 技术基线

建议首版原生macOS App，最低macOS 14，SwiftUI界面、Observation状态观察，采用开发机可用的稳定Xcode和Swift 6语言模式。正式实施时确认实际工具链并记录版本；原App最低系统为11并不约束新App。

[Apple模型数据文档](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)说明Observation与SwiftUI的数据依赖机制。这里将可观察会话模型放在MainActor上，值类型规则状态保持独立。

## 2. 模块与依赖

建议一个Xcode应用目标、一个本地Swift Package规则核心及相应测试目标：

```text
FreeCell/
  App/                  入口、依赖组装
  Features/Game/        GameSession、牌桌和交互视图
  Services/             存档、资源目录、计时
  Resources/            Assets.xcassets、本地化
Packages/FreeCellCore/
  Sources/FreeCellCore/  值类型、规则、发牌、移动枚举
  Tests/FreeCellCoreTests/
FreeCellUITests/
docs/
```

依赖方向：界面→会话→核心；核心不导入SwiftUI或AppKit，也不读图片、磁盘或系统时钟。视图不自行修改牌列；所有动作通过会话统一提交。协议用于需要替换的边界（存档、时钟、随机源），不为每个简单类型创建协议。初期不引入第三方依赖、数据库或复杂路由框架。

## 3. 类型与API

优先struct/enum及let，以枚举表达花色、位置、错误；避免字符串标识域对象，避免不可达的布尔组合。仅把需要共享身份的会话/服务建成class。合理使用private/internal，只公开核心的必要接口。

遵守[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)：调用处语义清晰，命名描述用途，参数标签说明角色，公共API写文档注释。类型UpperCamelCase，成员lowerCamelCase，使用统一格式工具而非人工争论空格。

生产代码不使用强制解包、强制类型转换、try!来处理输入或资源；依赖注入中已知不变量也优先用可检查的构造方式。规则错误使用具名错误；文件错误向用户提供可恢复操作。不要吞掉错误或把非法移动当崩溃。

## 4. SwiftUI状态与交互

GameSession使用@Observable、@MainActor；根视图通过@State持有它，子视图按需获取模型，只有需要绑定的字段使用@Bindable。牌桌渲染只展示牌与选择/可用状态，不持有另一份规则局面。稳定ID来自牌本身，不能每次刷新生成UUID。

几何位置由布局计算，命中判定与绘制共享几何信息。拖拽只产生意图，提交前以最新局面再次验证。点击选择再点击目标与拖拽共用移动流程；不依赖动画完成回调判断胜负。

支持窗口缩放、键盘操作、VoiceOver牌名和位置、清晰焦点、减少动态效果；花色与文字让信息不只依靠颜色。用户文案使用本地化资源，首版中文为主。

## 5. 并发与性能

核心规则规模小，直接同步执行。存档I/O和未来搜索避免阻塞主线程；后台任务收到值类型快照，返回结果后核对局面版本，丢弃过期提示。明确任务所有权与取消行为，关闭会话时取消任务；遵守Swift 6隔离与Sendable约束，不以unchecked Sendable隐藏问题。

图片通过Asset Catalog复用，避免在body内读取磁盘或反复解码；不提前添加复杂缓存。先用Instruments定位性能问题再优化。动画与拖拽状态独立于规则提交。

## 6. 持久化、日志与资源

采用版本化Codable存档与原子写入；存放于应用容器/Application Support适当路径，不写回App Bundle。测试注入临时目录。仅对偏好使用UserDefaults，不用其存放整个历史。

通过Logger记录加载失败和关键诊断；不要记录完整用户路径或无必要数据。记录资源来源与显式牌面映射，校验全部52张资源存在、尺寸一致、花色点数对应正确。新App不引用外部原App的绝对路径。

## 7. 验证与工程卫生

核心单元测试使用[Swift Testing](https://developer.apple.com/documentation/testing)，界面冒烟测试使用XCTest/XCUITest。参数化覆盖移动边界；用固定牌局测试胜利、撤销与存档，随机状态约束测试记录种子以便重现。

构建Debug与Release，关注编译警告及并发诊断；提交前运行格式检查、核心测试和相关UI验证。无需为了覆盖率给纯展示组件添加镜像测试；关键规则必须有测试。

用版本控制跟踪源码、工程配置、资源清单和文档；忽略DerivedData、构建输出、个人IDE状态及签名凭据。提交按可审查功能切分。核心规则解释“为什么”的注释优于重复代码的注释；架构或产品约定变更同步更新规则文档。

## 8. 首版环境适配

实际采用根Swift Package的FreeCellCore/FreeCellApp双目标；Command Line Tools构建，无第三方依赖。当前机器缺少Swift Testing/XCTest模块，核心用FreeCellChecks独立验证程序覆盖上述规则，不使用swift test。牌面使用资源Bundle替代Asset Catalog；Xcode可打开Package.swift。详见《04-实现与验收记录》。


## 9. 原生牌桌输入边界（1.1）

为控制不透明拖动、整组牌龙和原生双击识别，采用NSViewRepresentable桥接一个AppKit牌桌。NSView只持有绘制快照、鼠标按压/拖动和焦点状态；移动仍由MainActor上的GameSession提交，规则由FreeCellCore统一验证。FreeCellPresentation计算缩放及命中矩形，可在无窗口环境独立测试。取消或局面改变不修改规则状态。可访问性元素使用不可变的MainActor Sendable回调，动作切回主执行器，不以unchecked Sendable隐藏隔离问题。

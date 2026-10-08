import AppKit
import SwiftUI
import FreeCellCore

struct GameView: View {
    @Bindable var session: GameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showRules = false
    @State private var showDeal = false
    @State private var seedInput = ""
    @State private var seedError = ""
    @State private var reset: ResetAction?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let gold = Color(red: 0.91, green: 0.77, blue: 0.46)

    enum ResetAction: String, Identifiable { case newGame, restart; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(gold.opacity(0.25))
            GameBoard(state: session.state, selection: session.selection, hint: session.hintMove,
                      version: session.boardVersion, animationRequest: session.animationRequest, enabled: !session.paused && session.active, reduceMotion: reduceMotion,
                      onCardClick: { session.click(card: $0, at: $1) },
                      onEmptyClick: { session.clickEmpty($0) },
                      onDoubleClick: { session.doubleClick(cardID: $0) },
                      onMove: { session.move(cardID: $0, to: $1) },
                      onCancel: { session.cancelSelection() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(session.paused ? 0.12 : 1)
                .accessibilityHidden(session.paused)
                .overlay(alignment: .bottom) {
                    if session.state.isWon && !session.paused {
                        HStack(spacing: 16) {
                            Image(systemName: "sparkles").foregroundStyle(gold)
                            Text("全部归位，恭喜过关！").font(.headline).foregroundStyle(gold)
                            Text("\(session.moves) 步 · \(session.elapsed)").foregroundStyle(.white)
                            Button("再来一局") { session.newGame() }.buttonStyle(.borderedProminent).tint(gold).foregroundStyle(.black)
                        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.bottom, 20)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.45), value: session.state.isWon)
                .overlay {
                    if session.paused {
                        VStack(spacing: 16) {
                            Image(systemName: "pause.circle").font(.system(size: 48))
                            Text("牌局已暂停").font(.title2.bold())
                            Button("继续游戏") { session.togglePause() }.buttonStyle(.borderedProminent)
                        }.foregroundStyle(.white)
                    }
                }

            footer
        }
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.24, blue: 0.20), Color(red: 0.025, green: 0.13, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .background(NativeWindowConfiguration())
        .onReceive(timer) { _ in session.tick() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in session.setActive(true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in session.setActive(false) }
        .sheet(isPresented: $showRules) { rulesSheet }
        .sheet(isPresented: $showDeal) { dealSheet }
        .alert(item: $reset) { action in
            Alert(title: Text(action == .newGame ? "开始新牌局？" : "重新开始本局？"),
                  message: Text("当前进度及撤销历史将被清除。"),
                  primaryButton: .destructive(Text("确定")) { if action == .newGame { session.newGame() } else { session.restart() } },
                  secondaryButton: .cancel(Text("取消")))
        }
        .alert("存档恢复", isPresented: Binding(get: { session.recoveryMessage != nil }, set: { if !$0 { session.recoveryMessage = nil } })) {
            Button("知道了") { session.recoveryMessage = nil }
        } message: { Text(session.recoveryMessage ?? "") }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("空当接龙").font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(gold)
                    Text("FREECELL · 经典纸牌").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                metric("步数", String(session.moves))
                metric("用时", session.elapsed)
                metric("已收牌", "\(session.state.foundations.flatMap { $0 }.count) / 52")
            }
            HStack(spacing: 10) {
                Button("新局", systemImage: "plus") {
                    if session.state.isWon { session.newGame() } else { reset = .newGame }
                }
                Button("重开", systemImage: "arrow.clockwise") { reset = .restart }
                Button("撤销", systemImage: "arrow.uturn.backward") { session.undo() }.disabled(!session.canUndo || session.paused)
                Button("重做", systemImage: "arrow.uturn.forward") { session.redo() }.disabled(!session.canRedo || session.paused)
                Button("提示", systemImage: "lightbulb") { session.showHint() }.disabled(session.paused || session.state.isWon)
                Button("收牌", systemImage: "tray.and.arrow.down") { session.collect() }.disabled(session.paused || session.state.isWon)
                Spacer(minLength: 0)
                Button(session.paused ? "继续" : "暂停", systemImage: session.paused ? "play" : "pause") { session.togglePause() }
                Button("规则", systemImage: "questionmark.circle") { showRules = true }
            }.buttonStyle(.bordered).controlSize(.small)
        }.padding(.horizontal, 28).padding(.vertical, 20)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(.headline, design: .monospaced)).foregroundStyle(.white)
        }.padding(.leading, 24)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !CardImages.shared.missingNames.isEmpty { Text("牌面资源缺失：\(CardImages.shared.missingNames.joined(separator: "、"))").foregroundStyle(.orange) }
            if let error = session.saveError { Text(error).foregroundStyle(.orange) }
            Text(session.message).font(.callout).foregroundStyle(gold).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("状态：" + session.message)
            HStack {
                Toggle("自动安全收牌", isOn: $session.autoCollect).toggleStyle(.checkbox).font(.caption)
                Spacer()
                Button("牌局 \(String(session.archive.seed))") { seedInput = String(session.archive.seed); seedError = ""; showDeal = true }
                    .buttonStyle(.plain).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                    .help("输入自有牌局编号，以复现同一发牌")
            }
        }.padding(.horizontal, 28).padding(.vertical, 14).background(.black.opacity(0.15))
    }

    private var rulesSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("空当接龙 · 游戏规则").font(.title2.bold())
            Text("把全部 52 张牌移入四个基础堆。每个花色从 A 到 K 依次递增。")
            Text("工作列：按点数递减、红黑交替叠放。空列可以接任意牌。空当：每格只能放一张牌。基础堆最上方的牌可移回工作列，只要符合接牌规则。")
            Text("整组移动：连续有序牌组的容量为（空空当数 + 1）× 2 的可用空列数次方。来源列与空目标列都不能计作中转列。")
            Text("自动收牌采用保守条件，默认关闭；手动“收牌”也只收安全牌。一次动作及随后的自动收牌可以一起撤销。提示只建议合法移动，不保证可解。")
            Text("双击依次尝试：收牌、接到非空工作列、放入空当、放到空列；暂存牌不会换到另一空当。没有目标时晃动。拖动有序牌组时整组跟随鼠标。")
            Divider()
            Text("键盘：Tab / Shift-Tab 切换控件；牌桌内用方向键切换牌，空格选牌或确认目标，回车自动移动；⌘Z 撤销，⇧⌘Z 重做，⇧⌘H 提示，⌘K 收牌，⌘P 暂停，⌃⌘F 切换原生全屏，Esc 取消选择。")
            Text("本游戏采用自有牌局编号，不兼容 Microsoft 编号。切换到其他应用或暂停时停止计时。牌面来源：用户提供的 Full Deck Solitaire（GRL Games）。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("开始游戏") { showRules = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 540)
    }
    private var dealSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("指定牌局").font(.title2.bold())
            Text("输入 0～18446744073709551615 的自有编号，可复现同一发牌。\(session.state.isWon ? "" : "开始后会清除当前进度。")")
            TextField("牌局编号", text: $seedInput).textFieldStyle(.roundedBorder)
            if !seedError.isEmpty { Text(seedError).foregroundStyle(.orange) }
            HStack {
                Button("取消") { showDeal = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("开始此牌局") {
                    if let seed = UInt64(seedInput.trimmingCharacters(in: .whitespacesAndNewlines)) { session.newGame(seed: seed); showDeal = false }
                    else { seedError = "请输入范围内的非负整数。" }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
    }
}

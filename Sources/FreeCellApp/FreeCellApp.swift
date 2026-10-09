import AppKit
import SwiftUI

@main
struct FreeCellApp: App {
    @State private var session: GameSession
    init() { _session = State(initialValue: GameSession(settings: AppSettings.forCurrentLaunch())) }
    @NSApplicationDelegateAdaptor(FreeCellDelegate.self) private var delegate
    var body: some Scene {
        Window(ProcessInfo.processInfo.arguments.contains("--verification") ? L("空当接龙 · 验证") : L("空当接龙"), id: "game") {
            GameView(session: session)
                .modifier(GameLocaleModifier())
                .frame(minWidth: 760, minHeight: 620)
                .onAppear { delegate.session = session; session.connectSettings(); session.startAudio(); NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("关于空当接龙")) { AboutGame.show() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button(L("撤销")) { session.undo() }.keyboardShortcut("z").disabled(!session.canUndo || session.paused || session.state.isWon)
                Button(L("重做")) { session.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo || session.paused || session.state.isWon)
            }
            CommandGroup(after: .windowSize) {
                Button(L("切换全屏")) { NativeWindowActions.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
            CommandMenu(L("牌局")) {
                Button(L("重新开始本局")) { GameCommand.restart.send() }.keyboardShortcut("r")
                Button(L("统计")) { GameCommand.statistics.send() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("规则")) { GameCommand.rules.send() }.keyboardShortcut("/")
                Divider()
                Button(L("提示")) { session.showHint() }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(session.paused)
                Button(L("安全收牌")) { session.collect() }.keyboardShortcut("k").disabled(session.paused || session.state.isWon)
                Button(session.paused ? L("继续") : L("暂停")) { session.togglePause() }.keyboardShortcut("p").disabled(session.state.isWon)
                Button(L("取消选择")) { session.cancelSelection() }.keyboardShortcut(.escape, modifiers: [])
                Divider()
                Button(L("打开存档目录")) { session.revealSaveFolder() }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("新建牌局")) { GameCommand.newGame.send() }.keyboardShortcut("n")
            }
        }
        Settings { SettingsView(settings: session.settings).modifier(GameLocaleModifier()) }
    }
}

@MainActor
final class FreeCellDelegate: NSObject, NSApplicationDelegate {
    weak var session: GameSession?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM executables have no application Info.plist. Set the Dock icon for both launch paths.
        let iconURL = Bundle.main.url(forResource: "FreeCell", withExtension: "icns")
            ?? GameResources.bundle.url(forResource: "AppIcon", withExtension: "png")
        if let iconURL, let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        Task {
            let saved = await session.saveBeforeQuit()
            if saved { sender.reply(toApplicationShouldTerminate: true) }
            else {
                let alert = NSAlert()
                alert.messageText = L("当前牌局尚未保存")
                alert.informativeText = L("保存失败。取消退出后可检查存档目录；仍然退出可能丢失最近进度。")
                alert.addButton(withTitle: L("取消退出"))
                alert.addButton(withTitle: L("仍然退出"))
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Menus and board buttons share the same confirmation and sheet paths.
enum GameCommand { case newGame, restart, rules, statistics
    func send() { NotificationCenter.default.post(name: .freeCellCommand, object: self) }
}
extension Notification.Name { static let freeCellCommand = Notification.Name("FreeCell.command") }

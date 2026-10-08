import AppKit
import SwiftUI

@main
struct FreeCellApp: App {
    @State private var session = GameSession()
    @NSApplicationDelegateAdaptor(FreeCellDelegate.self) private var delegate
    var body: some Scene {
        Window(ProcessInfo.processInfo.arguments.contains("--verification") ? "空当接龙 · 验证" : "空当接龙", id: "game") {
            GameView(session: session)
                .frame(minWidth: 760, minHeight: 620)
                .onAppear { delegate.session = session; NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1120, height: 820)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { session.undo() }.keyboardShortcut("z").disabled(!session.canUndo || session.paused)
                Button("重做") { session.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo || session.paused)
            }
            CommandGroup(after: .windowSize) {
                Button("切换全屏") { NativeWindowActions.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
            CommandMenu("牌局") {
                Button("提示") { session.showHint() }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(session.paused)
                Button("安全收牌") { session.collect() }.keyboardShortcut("k").disabled(session.paused)
                Button(session.paused ? "继续" : "暂停") { session.togglePause() }.keyboardShortcut("p")
                Button("取消选择") { session.cancelSelection() }.keyboardShortcut(.escape, modifiers: [])
                Divider()
                Button("打开存档目录") { session.revealSaveFolder() }
            }
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class FreeCellDelegate: NSObject, NSApplicationDelegate {
    weak var session: GameSession?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM executables have no application Info.plist. Set the Dock icon for both launch paths.
        let iconURL = Bundle.main.url(forResource: "FreeCell", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
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
                alert.messageText = "当前牌局尚未保存"
                alert.informativeText = "保存失败。取消退出后可检查存档目录；仍然退出可能丢失最近进度。"
                alert.addButton(withTitle: "取消退出")
                alert.addButton(withTitle: "仍然退出")
                sender.reply(toApplicationShouldTerminate: alert.runModal() == .alertSecondButtonReturn)
            }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

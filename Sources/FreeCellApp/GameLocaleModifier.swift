import AppKit
import SwiftUI

struct GameLocaleModifier: ViewModifier {
    func body(content: Content) -> some View {
        let language = GameLocalization.shared.language
        content
            .environment(\.locale, Locale(identifier: language.rawValue))
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .onAppear { refreshNativeUI() }
            .onChange(of: language) { _, _ in refreshNativeUI() }
    }
    private func refreshNativeUI() {
        AboutGame.refreshTitle()
        // SwiftUI rebuilds command menus after view updates.
        DispatchQueue.main.async {
            NativeMenuLocalization.refresh()
            for window in NSApplication.shared.windows {
                switch window.identifier?.rawValue {
                case "game": window.title = ProcessInfo.processInfo.arguments.contains("--verification") ? L("空当接龙 · 验证") : L("空当接龙")
                case "com_apple_SwiftUI_Settings_window": window.title = "FreeCell · " + L("设置").replacingOccurrences(of: "…", with: "")
                default: break
                }
            }
        }
    }
}

@MainActor enum NativeMenuLocalization {
    private static let menuKeys = ["File", "Edit", "View", "Window", "Help"]
    private static let actions: [String: String] = [
        "terminate:": "menu.quit %@", "hide:": "menu.hide %@", "hideOtherApplications:": "Hide Others",
        "unhideAllApplications:": "Show All", "performClose:": "Close", "performMiniaturize:": "Minimize",
        "performZoom:": "Zoom", "arrangeInFront:": "Bring All to Front", "cut:": "Cut", "copy:": "Copy",
        "paste:": "Paste", "selectAll:": "Select All", "delete:": "Delete"
    ]
    private static var observers: [NSObjectProtocol] = []
    private static var isRefreshing = false
    private static var lastAutomaticRefresh: TimeInterval = 0
    static func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if observers.isEmpty {
            observers = [NSMenu.didChangeItemNotification, NSMenu.didAddItemNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        // Do not modify menus reentrantly while AppKit is building a sheet/menu.
                        let now = ProcessInfo.processInfo.systemUptime
                        guard !isRefreshing, now - lastAutomaticRefresh > 0.5 else { return }
                        lastAutomaticRefresh = now
                        DispatchQueue.main.async { refresh() }
                    }
                }
            }
        }
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if item.title == "设置…" || item.title == "Settings…" || GameLocalization.shared.isTranslation(item.title, of: "设置") {
                    let title = L("设置")
                    if item.title != title { item.title = title }
                }
                for key in menuKeys where GameLocalization.shared.isTranslation(item.title, of: key) {
                    let title = L(key)
                    if item.title != title { item.title = title }
                    if item.submenu?.title != title { item.submenu?.title = title }
                    break
                }
                if let action = item.action, let key = actions[NSStringFromSelector(action)] {
                    let title = key.contains("%@") ? L(key, "FreeCell") : L(key)
                    if item.title != title { item.title = title }
                }
                if let submenu = item.submenu { visit(submenu) }
            }
        }
        if let menu = NSApplication.shared.mainMenu { visit(menu) }
    }
}

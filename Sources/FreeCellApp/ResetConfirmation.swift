import AppKit

@MainActor
enum ResetConfirmation {
    static func present(title: String, onConfirm: @escaping @MainActor () -> Void) {
        guard let parent = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow,
              parent.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "当前进度及撤销历史将被清除。"
        alert.alertStyle = .warning
        let confirm = alert.addButton(withTitle: "确定")
        confirm.keyEquivalent = "\r"
        confirm.keyEquivalentModifierMask = []
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        // Handle the extra cancel shortcut only while this sheet is the event's window.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alert] event in
            let handled = MainActor.assumeIsolated {
                guard let alert, event.window === alert.window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
                alert.buttons[1].performClick(nil)
                return true
            }
            return handled ? nil : event
        }
        alert.beginSheetModal(for: parent) { response in
            if let monitor { NSEvent.removeMonitor(monitor) }
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }
}

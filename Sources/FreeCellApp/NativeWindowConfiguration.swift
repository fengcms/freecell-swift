import AppKit
import SwiftUI

struct NativeWindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
    func updateNSView(_ view: WindowConfigurationView, context: Context) { view.configureWindow() }
}

@MainActor
final class WindowConfigurationView: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureWindow() }
    func configureWindow() {
        guard let window else { return }
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }
}

@MainActor
enum NativeWindowActions {
    static func toggleFullScreen() {
        guard let window = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow else { return }
        window.toggleFullScreen(nil)
    }
}

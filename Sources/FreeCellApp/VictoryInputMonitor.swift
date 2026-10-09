import AppKit
import SwiftUI

/// Handles victory-only shortcuts without changing right-click or Space behavior during play.
struct VictoryInputMonitor: NSViewRepresentable {
    let isActive: Bool
    let onPlayAgain: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isActive: isActive, view: view, action: onPlayAgain)
        context.coordinator.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, view: nsView, action: onPlayAgain)
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        private weak var view: NSView?
        private var isActive = false
        private var action: (() -> Void)?
        private var monitor: Any?

        func update(isActive: Bool, view: NSView, action: @escaping () -> Void) {
            self.isActive = isActive
            self.view = view
            self.action = action
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .keyDown]) { [weak self] event in
                let isRightClick = event.type == .rightMouseDown
                let isSpace = event.type == .keyDown && event.keyCode == 49 &&
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty && !event.isARepeat
                guard isRightClick || isSpace else { return event }
                let eventWindowNumber = event.window?.windowNumber
                let handled = MainActor.assumeIsolated {
                    guard let self, self.isActive,
                          let window = self.view?.window,
                          window.windowNumber == eventWindowNumber else { return false }
                    self.action?()
                    return true
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

import AppKit
import SwiftUI

@MainActor
enum AboutGame {
    private static var controller: NSWindowController?
    static func show() {
        if controller == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 530),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "关于空当接龙"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AboutGameView())
            window.center()
            controller = NSWindowController(window: window)
        }
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct AboutGameView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }
    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 84, height: 84)
                    .accessibilityLabel("空当接龙图标")
            }
            VStack(spacing: 5) {
                Text("空当接龙 · FreeCell").font(.title2.bold())
                Text("版本 \(version)").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Text("经典空当接龙，以思考与耐心，\n把 52 张牌依次归位。")
                Text("支持整组拖拽、自动收牌、撤销与重做，\n搭配轻柔音乐，让每一局都从容自在。")
            }.font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider().padding(.horizontal, 24)
            VStack(spacing: 10) {
                Text("作者 · Fungleo").font(.headline)
                Text("键鼠请游戏人间 风流谈笑傲江湖")
                    .font(.system(size: 14, design: .serif))
            }
            VStack(spacing: 10) {
                sourceLink("GitHub · fengcms/freecell-swift", "https://github.com/fengcms/freecell-swift")
                sourceLink("个人博客 · fungleo.com", "http://fungleo.com")
            }.font(.callout)
        }.padding(30).frame(width: 450, height: 530).background(.background)
    }
    @ViewBuilder private func sourceLink(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) { Link(title, destination: url) }
    }
}

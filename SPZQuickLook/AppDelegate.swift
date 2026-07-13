import Cocoa

/// .ply/.spz のダブルクリック (application(_:open:)) でビューアウィンドウを開く
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var viewerWindows: [NSWindow] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openViewer(url: url)
        }
    }

    private func openViewer(url: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // ARC 管理 (viewerWindows 配列) と AppKit の close 時自動 release が二重解放になり
        // クローズアニメーション中に SIGSEGV するため、自動 release を無効化する
        window.isReleasedWhenClosed = false
        window.title = url.lastPathComponent
        window.contentViewController = ViewerViewController(url: url)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewerWindows.append(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        viewerWindows.removeAll { $0 === window }
    }
}

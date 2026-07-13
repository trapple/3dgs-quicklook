import SwiftUI

@main
struct SPZQuickLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("SPZ Quick Look")
                    .font(.title2)
                Text("Finder で .spz / .ply (3DGS) を選んでスペースキーを押すとプレビューされます。\nこのアプリは拡張を登録するためだけに存在します。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(minWidth: 420, minHeight: 240)
        }
    }
}

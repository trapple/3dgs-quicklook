import Cocoa
import MetalKit
import OSLog
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

    private static let logger = Logger(subsystem: "jp.trapple.SPZQuickLook", category: "preview")

    private var eventMonitors: [Any] = []
    private weak var splatView: SplatMetalView?

    override func loadView() {
        view = NSView()
        // QL ホスト内では SwiftUI ジェスチャにピンチ/スクロールが配送されない
        // (glb-quicklook の知見) ため、AppKit のイベントモニタで直接拾ってズームする
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.splatView?.zoom(magnificationDelta: event.magnification)
            return event
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            // 支配軸で判定: 縦スクロール = ズーム、横スクロール = パン
            // (qlmanage ホストは横 delta を奪い dx=0 で届くが、経路自体は残す)
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                self.splatView?.pan(deltaX: event.scrollingDeltaX, deltaY: 0)
            } else {
                self.splatView?.zoom(magnificationDelta: event.scrollingDeltaY * 0.01)
            }
            return event
        } as Any)
    }

    deinit {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SPZLoaderError.noGPU
        }
        // 失敗時はそのまま throw し、Quick Look 標準フォールバックに任せる (Fail Fast)
        let result: SplatLoadResult
        do {
            result = try await SPZLoader.load(url: url)
        } catch {
            Self.logger.error("SPZ load failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            throw error
        }

        let sceneRenderer = try SplatSceneRenderer(device: device, camera: OrbitCamera(bounds: result.bounds))
        try await sceneRenderer.add(points: result.points)

        let splatView = SplatMetalView(device: device, sceneRenderer: sceneRenderer)
        splatView.frame = view.bounds
        splatView.autoresizingMask = [.width, .height]
        view.addSubview(splatView)
        self.splatView = splatView

        Self.logger.info("preview ready: \(url.lastPathComponent, privacy: .public) points=\(result.points.count, privacy: .public)")

        splatView.installBackgroundToggle()
        if result.truncatedCount > 0 {
            splatView.showTruncationWarning(count: result.truncatedCount)
        }
    }
}

import Cocoa
import MetalKit
import OSLog

/// 単体ビューア (ダブルクリックで開いた .ply/.spz を表示)。
/// QL 拡張と同じ Shared のビューア部品を使う。ウィンドウを先に出し、ロードは非同期
final class ViewerViewController: NSViewController {

    private static let logger = Logger(subsystem: "jp.trapple.SPZQuickLook", category: "viewer")

    private let url: URL
    private let statusLabel = NSTextField(labelWithString: "読み込み中…")

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        view.wantsLayer = true
        view.layer?.backgroundColor = CGColor(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)

        statusLabel.textColor = .white
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await load() }
    }

    private func load() async {
        guard let device = MTLCreateSystemDefaultDevice() else {
            statusLabel.stringValue = "Metal が利用できません"
            return
        }
        do {
            let result = try await SPZLoader.load(url: url)
            let sceneRenderer = try SplatSceneRenderer(device: device, camera: OrbitCamera(bounds: result.bounds))
            try await sceneRenderer.add(points: result.points)

            let splatView = SplatMetalView(device: device, sceneRenderer: sceneRenderer)
            splatView.handlesScrollEventsDirectly = true
            splatView.frame = view.bounds
            splatView.autoresizingMask = [.width, .height]
            view.addSubview(splatView)
            splatView.installBackgroundToggle()
            if result.truncatedCount > 0 {
                splatView.showTruncationWarning(count: result.truncatedCount)
            }
            statusLabel.removeFromSuperview()
        } catch {
            // Fail Fast: 理由を明示して画面に出す (silent にしない)
            Self.logger.error("viewer load failed for \(self.url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            statusLabel.stringValue = "読み込みに失敗しました: \(error.localizedDescription)\n(3DGS ではない .ply の可能性があります)"
        }
    }
}

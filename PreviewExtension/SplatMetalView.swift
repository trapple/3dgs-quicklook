import AppKit
import MetalKit

/// マウス入力をオービットカメラに変換する MTKView。
/// 背景色は SplatRenderer の clear が透明 (0,0,0,0) なのを利用し、layer の背景色で切り替える
final class SplatMetalView: MTKView {
    private let sceneRenderer: SplatSceneRenderer

    var isDarkBackground = true {
        didSet { applyBackgroundColor() }
    }

    init(device: MTLDevice, sceneRenderer: SplatSceneRenderer) {
        self.sceneRenderer = sceneRenderer
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm_srgb
        depthStencilPixelFormat = .depth32Float
        sampleCount = 1
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        delegate = sceneRenderer
        wantsLayer = true
        layer?.isOpaque = false
        // 常時描画ループを止め、入力・ソート完了時のみ再描画する (CPU/GPU 負荷対策)
        isPaused = true
        enableSetNeedsDisplay = true
        sceneRenderer.redrawTarget = self
        applyBackgroundColor()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // spec: ダーク #262626 ⇄ ライト #d9d9d9
    private func applyBackgroundColor() {
        layer?.backgroundColor = isDarkBackground
            ? CGColor(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)
            : CGColor(red: 0xd9 / 255.0, green: 0xd9 / 255.0, blue: 0xd9 / 255.0, alpha: 1)
    }

    override func mouseDragged(with event: NSEvent) {
        // QL ホストは横スクロールの delta を奪うため、パンの正経路は Shift+ドラッグ / 右ドラッグ
        if event.modifierFlags.contains(.shift) {
            pan(deltaX: event.deltaX, deltaY: event.deltaY)
            return
        }
        sceneRenderer.camera.rotate(
            deltaYaw: Float(event.deltaX) * 0.01,
            deltaPitch: Float(event.deltaY) * 0.01
        )
        needsDisplay = true
    }

    override func rightMouseDragged(with event: NSEvent) {
        pan(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    override func otherMouseDragged(with event: NSEvent) {
        pan(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    func zoom(magnificationDelta: CGFloat) {
        sceneRenderer.camera.zoom(factor: Float(1.0 + magnificationDelta))
        needsDisplay = true
    }

    func pan(deltaX: CGFloat, deltaY: CGFloat) {
        sceneRenderer.camera.pan(deltaX: Float(deltaX), deltaY: Float(deltaY))
        needsDisplay = true
    }
}

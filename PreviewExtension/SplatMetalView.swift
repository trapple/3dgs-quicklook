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
        sceneRenderer.camera.rotate(
            deltaYaw: Float(event.deltaX) * 0.01,
            deltaPitch: Float(event.deltaY) * 0.01
        )
    }

    func zoom(magnificationDelta: CGFloat) {
        sceneRenderer.camera.zoom(factor: Float(1.0 + magnificationDelta))
    }
}

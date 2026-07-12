import Foundation
import MetalKit
import MetalSplatter
import SplatIO

/// MTKView の draw ループで MetalSplatter SplatRenderer に viewport を渡して描画する。
/// 深度ソート・アルファブレンドは SplatRenderer 内部 (SplatSorter) が自動で行う
@MainActor
final class SplatSceneRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderer: SplatRenderer
    // SampleApp と同じ in-flight 3 フレーム制御
    private let inFlight = DispatchSemaphore(value: 3)
    private var drawableSize: CGSize = .zero

    var camera: OrbitCamera

    /// イベント駆動描画のための再描画先。ソート完了時に needsDisplay を立てる
    weak var redrawTarget: MTKView?

    init(device: MTLDevice, camera: OrbitCamera) throws {
        guard let queue = device.makeCommandQueue() else {
            throw SPZLoaderError.noGPU
        }
        self.device = device
        self.commandQueue = queue
        self.camera = camera
        self.renderer = try SplatRenderer(
            device: device,
            colorFormat: .bgra8Unorm_srgb,
            depthFormat: .depth32Float,
            sampleCount: 1,
            maxViewCount: 1,
            maxSimultaneousRenders: 3
        )
        super.init()
        // 常時 60fps で回さず、ソート完了時だけ再描画する (QL プレビューの CPU/GPU 負荷対策)
        renderer.onSortComplete = { [weak self] _ in
            Task { @MainActor in
                self?.redrawTarget?.needsDisplay = true
            }
        }
    }

    func add(points: [SplatPoint]) async throws {
        let chunk = try SplatChunk(device: device, from: points)
        await renderer.addChunk(chunk)
        redrawTarget?.needsDisplay = true
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            self.drawableSize = size
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMain(in: view)
        }
    }

    private func drawOnMain(in view: MTKView) {
        guard renderer.isReadyToRender,
              drawableSize.width > 0, drawableSize.height > 0,
              let drawable = view.currentDrawable else { return }
        inFlight.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        let width = Int(drawableSize.width), height = Int(drawableSize.height)
        let viewport = SplatRenderer.ViewportDescriptor(
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(width), height: Double(height),
                                  znear: 0, zfar: 1),
            projectionMatrix: camera.projectionMatrix(aspect: Float(width) / Float(height)),
            viewMatrix: camera.viewMatrix,
            screenSize: SIMD2(width, height)
        )
        // 戻り値 false = ソート未完了等でフレームドロップ (present しない)
        let didRender = (try? renderer.render(
            viewports: [viewport],
            colorTexture: drawable.texture,
            colorStoreAction: .store,
            depthTexture: view.depthStencilTexture,
            rasterizationRateMap: nil,
            renderTargetArrayLength: 0,
            to: commandBuffer
        )) ?? false
        if didRender {
            commandBuffer.present(drawable)
        } else {
            // ソート未完了等でドロップしたフレームは少し待って再試行 (スピンさせない)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30.0) { [weak view] in
                view?.needsDisplay = true
            }
        }
        commandBuffer.commit()
    }
}

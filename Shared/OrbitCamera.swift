import simd

/// 注視点 (bounds 中心) を周回するオービットカメラ。
/// 一般的な 3DGS データを正立させるため viewMatrix に Z 軸 π 回転を含める
/// (MetalSplatter SampleApp の commonUpCalibration と同じ補正)
struct OrbitCamera {
    static let fovYRadians: Float = 65 * .pi / 180

    private var center: SIMD3<Float>
    private let initialDistance: Float
    private var distance: Float
    private var yaw: Float = 0
    private var pitch: Float = 0
    /// 3DGS データは上下軸の標準がない (COLMAP 系: Y 下向き / SuperSplat 系: Y 上向き) ため、
    /// デフォルトの 180° 補正をトグルできるようにする
    private var isFlipped = false

    private static let pitchLimit: Float = 88 * .pi / 180

    init(bounds: SplatBounds) {
        center = bounds.center
        // バウンディング球が画面に収まる距離 + 余白 1.4 倍
        initialDistance = bounds.radius / tan(Self.fovYRadians * 0.5) * 1.4
        distance = initialDistance
    }

    mutating func rotate(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        pitch = min(max(pitch + deltaPitch, -Self.pitchLimit), Self.pitchLimit)
    }

    /// 画面基準の横/縦パン。delta はスクロールのポイント数、
    /// 移動量はズーム距離に比例させる (寄っているほど細かく動く)
    mutating func pan(deltaX: Float, deltaY: Float) {
        let cameraSpace = SIMD3<Float>(deltaX, -deltaY, 0) * (distance * 0.0015)
        center -= orientation.inverse.act(cameraSpace)
    }

    mutating func toggleFlip() {
        isFlipped.toggle()
    }

    mutating func zoom(factor: Float) {
        guard factor > 0, factor.isFinite else { return }
        distance = min(max(distance / factor, initialDistance * 0.02), initialDistance * 20)
    }

    /// ワールド → カメラ空間の回転 (viewMatrix の回転部と同一)。
    /// Z 軸 π 回転は一般的な 3DGS データ (Y 下向き) を正立させる補正
    /// (MetalSplatter SampleApp の commonUpCalibration)。isFlipped でオフにできる
    private var orientation: simd_quatf {
        let calibration = simd_quatf(angle: isFlipped ? 0 : .pi, axis: SIMD3<Float>(0, 0, 1))
        return simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * calibration
    }

    var viewMatrix: simd_float4x4 {
        matrixTranslation(SIMD3<Float>(0, 0, -distance))
            * simd_float4x4(orientation)
            * matrixTranslation(-center)
    }

    func projectionMatrix(aspect: Float) -> simd_float4x4 {
        matrixPerspectiveRH(
            fovYRadians: Self.fovYRadians,
            aspect: aspect,
            near: max(distance * 0.01, 1e-3),
            far: distance * 100
        )
    }
}

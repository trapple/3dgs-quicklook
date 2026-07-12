import simd

/// 注視点 (bounds 中心) を周回するオービットカメラ。
/// 一般的な 3DGS データを正立させるため viewMatrix に Z 軸 π 回転を含める
/// (MetalSplatter SampleApp の commonUpCalibration と同じ補正)
struct OrbitCamera {
    static let fovYRadians: Float = 65 * .pi / 180

    private let center: SIMD3<Float>
    private let initialDistance: Float
    private var distance: Float
    private var yaw: Float = 0
    private var pitch: Float = 0

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

    mutating func zoom(factor: Float) {
        guard factor > 0, factor.isFinite else { return }
        distance = min(max(distance / factor, initialDistance * 0.05), initialDistance * 20)
    }

    var viewMatrix: simd_float4x4 {
        matrixTranslation(SIMD3<Float>(0, 0, -distance))
            * matrixRotation(radians: pitch, axis: SIMD3<Float>(1, 0, 0))
            * matrixRotation(radians: yaw, axis: SIMD3<Float>(0, 1, 0))
            * matrixRotation(radians: .pi, axis: SIMD3<Float>(0, 0, 1))
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

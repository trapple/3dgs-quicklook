import simd

/// AABB 中心を中心とするバウンディング球。radius 0 (点 1 個・空) は 1 にフォールバックし、
/// カメラ距離が 0 になるのを防ぐ
struct SplatBounds {
    var center: SIMD3<Float>
    var radius: Float

    init(positions: [SIMD3<Float>]) {
        guard let first = positions.first else {
            center = .zero
            radius = 1
            return
        }
        var minP = first, maxP = first
        for p in positions {
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)
        }
        center = (minP + maxP) * 0.5
        var maxDistSq: Float = 0
        for p in positions {
            maxDistSq = max(maxDistSq, simd_length_squared(p - center))
        }
        let r = maxDistSq.squareRoot()
        radius = (r > 0 && r.isFinite) ? r : 1
    }
}

import simd

/// 点群の「主要部」を表すバウンディング球。
/// 3DGS シーンには遠方のフローター (ノイズ点) が付き物で、AABB や最遠点半径だと
/// 球が数十倍に膨らみ初期カメラが引きすぎる。そのため中心は軸ごとの中央値、
/// 半径は中心からの距離の 90 パーセンタイルで求める。
/// radius 0 (点 1 個・空・全点同位置) は 1 にフォールバックし、カメラ距離が 0 になるのを防ぐ
struct SplatBounds {
    var center: SIMD3<Float>
    var radius: Float

    init(positions: [SIMD3<Float>]) {
        guard !positions.isEmpty else {
            center = .zero
            radius = 1
            return
        }
        center = SIMD3<Float>(
            Self.median(positions.map(\.x)),
            Self.median(positions.map(\.y)),
            Self.median(positions.map(\.z))
        )
        let c = center
        var distances = positions.map { simd_length($0 - c) }
        distances.sort()
        let idx = min(distances.count - 1, Int((Double(distances.count) * 0.9).rounded(.up)) - 1)
        let r = distances[max(idx, 0)]
        radius = (r > 0 && r.isFinite) ? r : 1
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) * 0.5 : sorted[mid]
    }
}

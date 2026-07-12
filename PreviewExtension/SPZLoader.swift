import Foundation
import SplatIO

struct SplatLoadResult {
    let points: [SplatPoint]
    let truncatedCount: Int
    let bounds: SplatBounds
}

enum SPZLoaderError: Error {
    case emptyScene
    case noGPU
}

enum SPZLoader {
    /// 描画上限。QL appex のメモリと応答性を守るための値で、超過分は
    /// 「⚠︎ N 個省略」としてオーバーレイ表示する (silent にしない)
    static let maxSplatCount = 4_000_000

    static func load(url: URL) async throws -> SplatLoadResult {
        // 失敗 (gzip 破損・ヘッダ不正・非対応バージョン) は SplatIO がそのまま throw する (Fail Fast)
        let all = try await AutodetectSceneReader(url).readAll()
        guard !all.isEmpty else { throw SPZLoaderError.emptyScene }
        let kept = all.count > maxSplatCount ? Array(all.prefix(maxSplatCount)) : all
        return SplatLoadResult(
            points: kept,
            truncatedCount: all.count - kept.count,
            bounds: SplatBounds(positions: kept.map(\.position))
        )
    }
}

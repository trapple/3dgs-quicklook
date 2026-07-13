import Foundation
import SplatIO

// ply2spz — 3DGS ファイル (.ply/.splat/.spz) を .spz に変換する
//
// 使い方: ply2spz <input.(ply|splat|spz)> [output.spz] [-f]
//   output 省略時は入力の拡張子を .spz に差し替えたパスに出力する。
//   既存ファイルは -f を付けない限り上書きしない (Fail Fast)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("エラー: " + message + "\n").utf8))
    exit(1)
}

var force = false
var paths: [String] = []
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "-f", "--force":
        force = true
    case "-h", "--help":
        print("使い方: ply2spz <input.(ply|splat|spz)> [output.spz] [-f]")
        exit(0)
    default:
        paths.append(arg)
    }
}

guard paths.count == 1 || paths.count == 2 else {
    fail("使い方: ply2spz <input.(ply|splat|spz)> [output.spz] [-f]")
}

let inputURL = URL(fileURLWithPath: paths[0])
let outputURL = paths.count == 2
    ? URL(fileURLWithPath: paths[1])
    : inputURL.deletingPathExtension().appendingPathExtension("spz")

guard FileManager.default.fileExists(atPath: inputURL.path) else {
    fail("入力ファイルがありません: \(inputURL.path)")
}
guard outputURL != inputURL else {
    fail("入力と出力が同じパスです (入力が .spz の場合は出力パスを指定してください)")
}
if FileManager.default.fileExists(atPath: outputURL.path), !force {
    fail("出力先が既に存在します (-f で上書き): \(outputURL.path)")
}

do {
    let points = try await AutodetectSceneReader(inputURL).readAll()
    guard !points.isEmpty else { fail("スプラットが 0 個です (3DGS ファイルではない可能性)") }

    let writer = try SPZSceneWriter(toFileAtPath: outputURL.path)
    try await writer.start(numPoints: points.count)
    try await writer.write(points)
    try await writer.close()

    let inSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? Int) ?? 0
    let outSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
    let mb = { (b: Int?) in String(format: "%.1fMB", Double(b ?? 0) / 1_048_576) }
    print("✅ \(points.count.formatted()) スプラット: \(inputURL.lastPathComponent) (\(mb(inSize))) → \(outputURL.lastPathComponent) (\(mb(outSize)))")
} catch {
    fail("変換に失敗しました: \(error)")
}

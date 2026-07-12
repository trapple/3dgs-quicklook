import simd
import XCTest

final class SplatBoundsTests: XCTestCase {

    func testTwoPointsCenterAndRadius() {
        let b = SplatBounds(positions: [SIMD3<Float>(-1, 0, 0), SIMD3<Float>(3, 0, 0)])
        XCTAssertEqual(b.center.x, 1, accuracy: 1e-6)
        XCTAssertEqual(b.center.y, 0, accuracy: 1e-6)
        XCTAssertEqual(b.radius, 2, accuracy: 1e-6)
    }

    func testSinglePointHasFallbackRadius() {
        let b = SplatBounds(positions: [SIMD3<Float>(5, 5, 5)])
        XCTAssertEqual(b.center, SIMD3<Float>(5, 5, 5))
        XCTAssertEqual(b.radius, 1) // 半径 0 はカメラ距離が 0 になるためフォールバック
    }

    func testEmptyIsUnitSphereAtOrigin() {
        let b = SplatBounds(positions: [])
        XCTAssertEqual(b.center, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(b.radius, 1)
    }

    func testFarFloaterDoesNotInflateBounds() {
        // 主要部: 原点周辺の 10 点 + フローター 1 点 (x=100)。
        // 中央値中心 + p90 半径ならフローターに引っ張られない
        var positions = (0..<10).map { i in
            SIMD3<Float>(cos(Float(i)), sin(Float(i)), 0) // 距離 1 の円周上
        }
        positions.append(SIMD3<Float>(100, 0, 0))
        let b = SplatBounds(positions: positions)
        XCTAssertLessThan(abs(b.center.x), 1.0)
        XCTAssertLessThan(b.radius, 3.0) // AABB/最遠点なら 100 近くになる
    }
}

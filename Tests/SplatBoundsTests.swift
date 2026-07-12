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
}

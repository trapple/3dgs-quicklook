import simd
import XCTest

final class MatrixMathTests: XCTestCase {

    func testTranslationMovesPoint() {
        let m = matrixTranslation(SIMD3<Float>(1, 2, 3))
        let p = m * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(p.x, 1); XCTAssertEqual(p.y, 2); XCTAssertEqual(p.z, 3); XCTAssertEqual(p.w, 1)
    }

    func testRotationHalfPiAboutYMapsXToMinusZ() {
        let m = matrixRotation(radians: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let p = m * SIMD4<Float>(1, 0, 0, 1)
        XCTAssertEqual(p.x, 0, accuracy: 1e-6)
        XCTAssertEqual(p.z, -1, accuracy: 1e-6)
    }

    func testPerspectiveMapsNearAndFarPlane() {
        let near: Float = 0.1, far: Float = 100
        let m = matrixPerspectiveRH(fovYRadians: .pi / 3, aspect: 1.0, near: near, far: far)
        // RH: 視線は -Z。near 平面 → NDC z=0 (Metal), far 平面 → NDC z=1
        let pNear = m * SIMD4<Float>(0, 0, -near, 1)
        let pFar = m * SIMD4<Float>(0, 0, -far, 1)
        XCTAssertEqual(pNear.z / pNear.w, 0, accuracy: 1e-5)
        XCTAssertEqual(pFar.z / pFar.w, 1, accuracy: 1e-4)
    }
}

import simd
import XCTest

final class OrbitCameraTests: XCTestCase {

    private func makeCamera() -> OrbitCamera {
        OrbitCamera(bounds: SplatBounds(positions: [SIMD3<Float>(9, 10, 10), SIMD3<Float>(11, 10, 10)]))
    }

    func testViewMatrixMapsCenterToMinusDistanceOnZ() {
        var cam = makeCamera()
        cam.rotate(deltaYaw: 0.7, deltaPitch: 0.3) // 回転しても中心は視軸上に留まる
        let p = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1) // bounds の中心
        XCTAssertEqual(p.x, 0, accuracy: 1e-4)
        XCTAssertEqual(p.y, 0, accuracy: 1e-4)
        XCTAssertLessThan(p.z, 0) // カメラ前方 (-Z)
    }

    func testInitialDistanceFitsBoundingSphere() {
        let cam = makeCamera()
        let p = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        // radius 1、fovY 65°: distance = radius / tan(32.5°) * 1.4 ≈ 2.20
        XCTAssertEqual(p.z, -2.20, accuracy: 0.05)
    }

    func testPitchIsClamped() {
        var cam = makeCamera()
        cam.rotate(deltaYaw: 0, deltaPitch: 100) // 大量に回しても ±88° で止まる
        let before = cam.viewMatrix
        cam.rotate(deltaYaw: 0, deltaPitch: 1)
        XCTAssertEqual(before, cam.viewMatrix) // クランプ済みなので変化しない
    }

    func testPanMovesSceneSidewaysInViewSpace() {
        var cam = makeCamera()
        let before = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        cam.pan(deltaX: 100, deltaY: 0) // 指を右へ → シーンが画面右へ動く
        let after = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        XCTAssertGreaterThan(after.x, before.x)
        XCTAssertEqual(after.y, before.y, accuracy: 1e-4) // 横パンで縦位置は変わらない
    }

    func testPanFollowsCameraOrientation() {
        var cam = makeCamera()
        cam.rotate(deltaYaw: 1.2, deltaPitch: -0.4) // 回転後でも画面基準で動く
        let before = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        cam.pan(deltaX: 100, deltaY: 0)
        let after = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        XCTAssertGreaterThan(after.x, before.x)
        XCTAssertEqual(after.z, before.z, accuracy: 1e-3) // 奥行きは変わらない
    }

    func testZoomIsClamped() {
        var cam = makeCamera()
        for _ in 0..<1000 { cam.zoom(factor: 1.5) } // 近づき続けても下限で止まる
        let pNear = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        XCTAssertGreaterThan(pNear.z, -1e3)
        XCTAssertLessThan(pNear.z, 0)
        for _ in 0..<1000 { cam.zoom(factor: 0.5) } // 離れ続けても上限で止まる
        let pFar = cam.viewMatrix * SIMD4<Float>(10, 10, 10, 1)
        XCTAssertGreaterThan(pFar.z, -1e4) // 有限
    }
}

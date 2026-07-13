import simd

/// Metal の NDC (z: 0...1) 向け右手系透視投影行列
func matrixPerspectiveRH(fovYRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let ys = 1 / tan(fovYRadians * 0.5)
    let xs = ys / aspect
    let zs = far / (near - far)
    return simd_float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * near, 0)
    ))
}

func matrixTranslation(_ t: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    return m
}

func matrixRotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: radians, axis: simd_normalize(axis)))
}

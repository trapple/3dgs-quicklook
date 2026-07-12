# SPZ Quick Look 拡張 実装プラン

> **実装者向け:** このプランは branch + 直列 (このセッションで順に実装) で消化する。step は `- [ ]` チェックボックスで track する。

**Goal:** .spz (3D Gaussian Splatting) ファイルを Finder のスペースキーでプレビューできる macOS Quick Look 拡張 (ホストアプリ + appex) を作る。

**Architecture:** ホストアプリ SPZQuickLook.app (ほぼ空) に PreviewExtension.appex を埋め込む 2 ターゲット構成。appex は SplatIO で .spz をデコードし、MetalSplatter の SplatRenderer + MTKView で描画する (深度ソート・アルファブレンドはライブラリ内部)。カメラは自作オービット。

**Tech Stack:** Swift 5.10 / AppKit + MetalKit / MetalSplatter 1.0.1 (SplatIO 含む、SPM) / XcodeGen / XCTest

## Global Constraints

### Spec 由来 (spec から逐語コピー)

- 対応形式: **.spz のみ**。スコープ: **プレビューのみ** (サムネイル拡張は作らない)
- 機能: カメラ操作 (ドラッグ回転 + ズーム) と背景色切替のみ。**自動回転なし**。アニメーションなし
- 対象 UTI: `com.nianticlabs.spz` を `UTImportedTypeDeclarations` で自己宣言。`UTTypeConformsTo: [public.data, public.3d-content]`、拡張子 `spz`
- エラー: 「gzip 展開失敗・ヘッダ不正・非対応バージョン → `preparePreviewOfFile` から throw し、Quick Look 標準のフォールバック (ファイル情報表示) に任せる。壊れた 3D 表示を出さない」
- 「ガウシアン数上限を設ける (具体値は実装時に確定)。**上限超過時は「⚠︎ N 個省略」をオーバーレイで可視化**し、サイレントに切り捨てない」→ 本プランでは上限 **4,000,000** で確定
- 「タイムアウトは設けない (Quick Look 自体が拡張プロセスを管理・強制終了するため二重管理になる)」
- 背景色: glb-quicklook と同じダーク #262626 ⇄ ライト #d9d9d9 の 2 値トグル
- SPZLoader (デコード層) を描画層から分離する — 将来 RealityKit `GaussianSplatComponent` (macOS 27+) へ乗り換える際にパーサ層を流用するため

### PJ 恒久ルール (CLAUDE.md / `.claude/rules/` 由来)

- グローバル CLAUDE.md: 回答・コメントは日本語 / `git -C <dir>` を使う (cd しない) / ドキュメント修正がある場合はコードより先に
- 外部プロセス起動 (curl 等) には必ず timeout を指定する
- 小さくイテレーションを回す: fixtures の全件確認前に 1 件で動作確認する
- プロジェクト固有の CLAUDE.md / rules: 該当なし (新規リポジトリ)

### 運用前提 (brainstorming で確定した実装方式)

- 実装スタイル **B: branch + 直列**。branch `feature/spz-quicklook` は作成済み・spec commit 済み
- main 直コミット禁止。タスクごとに commit する
- 制約 (MetalSplatter 由来): **macOS 15+ / Apple Silicon 専用** (SplatRenderer.init に `#if arch(x86_64) fatalError` がある)。開発機は Apple Silicon + macOS 26 なので問題なし

---

## ファイル構造

```
project.yml                                 … XcodeGen 定義 (3 ターゲット: app / appex / UnitTests)
Makefile                                    … gen/build/install/test/ql/reset/fixtures
.gitignore                                  … *.xcodeproj, build/, fixtures/, .DS_Store
SPZQuickLook/SPZQuickLookApp.swift          … ホスト。説明ウィンドウのみ
PreviewExtension/PreviewViewController.swift … QL 入口。ロード → ビュー組み立て
PreviewExtension/MatrixMath.swift           … 行列ヘルパー (perspective/translation/rotation) 純関数
PreviewExtension/OrbitCamera.swift          … オービットカメラ状態 + view/projection 行列 (純 struct)
PreviewExtension/SplatBounds.swift          … バウンディング球計算 (純 struct)
PreviewExtension/SPZLoader.swift            … SplatIO で readAll + 上限カット + bounds 計算
PreviewExtension/SplatSceneRenderer.swift   … MTKViewDelegate。SplatRenderer に viewport を渡して描画
PreviewExtension/SplatMetalView.swift       … MTKView サブクラス。マウス入力 + 背景色
PreviewExtension/PreviewExtension.entitlements
Tests/MatrixMathTests.swift
Tests/OrbitCameraTests.swift
Tests/SplatBoundsTests.swift
fixtures/                                   … git 管理外。make fixtures で取得
```

責務境界: `MatrixMath`/`OrbitCamera`/`SplatBounds` は AppKit/Metal に依存しない純ロジック (UnitTests 対象)。`SPZLoader` は SplatIO 依存 (デコード層)。`SplatSceneRenderer`/`SplatMetalView` は Metal 依存 (描画層)。

## 参照 API (調査済み、MetalSplatter 1.0.1)

```swift
// SplatIO
public class AutodetectSceneReader: SplatSceneReader {
    public init(_ url: URL) throws               // 拡張子で判別。spz 対応。file URL のみ
}
extension SplatSceneReader {
    public func readAll() async throws -> [SplatPoint]
}
public struct SplatPoint: Sendable {
    public var position: SIMD3<Float>
    public var color: Color                      // .sphericalHarmonicFloat([SIMD3<Float>]) | .sRGBUInt8(...)
    public var opacity: Opacity
    public var scale: Scale
    public var rotation: simd_quatf
}

// MetalSplatter
public init(device: MTLDevice, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat,
            sampleCount: Int, maxViewCount: Int, maxSimultaneousRenders: Int,
            highQualityDepth: Bool = true, clearColor: MTLClearColor = .init(red: 0, green: 0, blue: 0, alpha: 0)) throws
public struct SplatChunk { public init(device: MTLDevice, from points: [SplatPoint]) throws }
@discardableResult public func addChunk(_ chunk: SplatChunk, sortByLocality: Bool = true, enabled: Bool = true) async -> ChunkID
public var isReadyToRender: Bool
@discardableResult
public func render(viewports: [ViewportDescriptor], colorTexture: MTLTexture, colorStoreAction: MTLStoreAction,
                   depthTexture: MTLTexture?, rasterizationRateMap: MTLRasterizationRateMap?,
                   renderTargetArrayLength: Int, accessTimeout: TimeInterval = 0.1,
                   sortTimeout: TimeInterval = 0.1, to commandBuffer: MTLCommandBuffer) throws -> Bool
public struct ViewportDescriptor {
    public init(viewport: MTLViewport, projectionMatrix: simd_float4x4, viewMatrix: simd_float4x4, screenSize: SIMD2<Int>)
}
```

ソートはレンダラー内部の SplatSorter が自動実行 (明示呼び出し不要)。SampleApp (MetalKitSceneRenderer) は colorPixelFormat `.bgra8Unorm_srgb` / depth `.depth32Float` / sampleCount 1 / in-flight 3 (DispatchSemaphore)。一般的な 3DGS データを正立させる補正として viewMatrix に **Z 軸まわり π 回転** (commonUpCalibration) を入れる。

---

### Task 1: プロジェクト骨格 (XcodeGen + ホストアプリ + appex スタブ)

**Files:**
- Create: `.gitignore`, `project.yml`, `Makefile`, `SPZQuickLook/SPZQuickLookApp.swift`, `PreviewExtension/PreviewViewController.swift`, `PreviewExtension/PreviewExtension.entitlements` (XcodeGen が properties から生成するため空ファイル可)

**Interfaces:**
- Produces: `make gen` / `make build` が通るプロジェクト。appex は QL に登録されるがまだ `featureUnsupported` を throw するだけ (QL 標準フォールバック表示)

- [ ] **Step 1: .gitignore**

```gitignore
*.xcodeproj
build/
fixtures/
.DS_Store
```

- [ ] **Step 2: project.yml** (glb-quicklook の構成を踏襲 + SPM packages)

```yaml
name: SPZQuickLook
options:
  bundleIdPrefix: jp.trapple
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    # バージョンの正。リリース時はここを読む
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"

packages:
  MetalSplatter:
    url: https://github.com/scier/MetalSplatter
    exactVersion: 1.0.1

schemes:
  SPZQuickLook:
    build:
      targets:
        SPZQuickLook: all
    run:
      config: Release
    test:
      targets: [UnitTests]

targets:
  SPZQuickLook:
    type: application
    platform: macOS
    sources: [SPZQuickLook]
    info:
      path: SPZQuickLook/Info.plist
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        NSPrincipalClass: NSApplication
        NSMainStoryboardFile: ""
        CFBundleDocumentTypes:
          - CFBundleTypeName: Gaussian Splat (SPZ)
            CFBundleTypeRole: Viewer
            LSHandlerRank: Default
            LSItemContentTypes: [com.nianticlabs.spz]
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: com.nianticlabs.spz
            UTTypeDescription: Gaussian Splat (SPZ)
            UTTypeConformsTo: [public.data, public.3d-content]
            UTTypeTagSpecification:
              public.filename-extension: [spz]
    dependencies:
      - target: PreviewExtension
        embed: true

  PreviewExtension:
    type: app-extension
    platform: macOS
    sources: [PreviewExtension]
    settings:
      base:
        # 親アプリの bundle ID をプレフィックスにしないと ValidateEmbeddedBinary で失敗する
        PRODUCT_BUNDLE_IDENTIFIER: jp.trapple.SPZQuickLook.PreviewExtension
    # sandbox 必須: 無いと pkd が "plug-ins must be sandboxed" で登録を拒否する
    entitlements:
      path: PreviewExtension/PreviewExtension.entitlements
      properties:
        com.apple.security.app-sandbox: true
    info:
      path: PreviewExtension/Info.plist
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        CFBundleDisplayName: SPZ Preview
        # appex は XPC! でないと pluginkit に登録されない
        CFBundlePackageType: "XPC!"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.quicklook.preview
          NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).PreviewViewController"
          NSExtensionAttributes:
            QLSupportedContentTypes: [com.nianticlabs.spz]
            QLSupportsSearchableItems: false
    dependencies:
      - package: MetalSplatter
        product: MetalSplatter
      - package: MetalSplatter
        product: SplatIO

  UnitTests:
    type: bundle.unit-test
    platform: macOS
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    sources:
      - Tests
      - path: PreviewExtension/MatrixMath.swift
      - path: PreviewExtension/OrbitCamera.swift
      - path: PreviewExtension/SplatBounds.swift
```

注: Task 1 時点では `MatrixMath.swift` 等が未作成のため、**Task 1 では UnitTests ターゲットの `sources` を `- Tests` の 1 行だけにし、`Tests/.gitkeep` 相当として空のテストファイルを置かず、schemes の `test:` 行ごとコメントアウトしない**。→ 具体的には Task 1 では UnitTests ターゲット定義と schemes の test 行を**丸ごと省略**し、Task 2 で追加する (ビルドを常にグリーンに保つ)。

- [ ] **Step 3: Makefile**

```makefile
APP := SPZQuickLook
DERIVED := build
SPZ_SAMPLE_BASE := https://raw.githubusercontent.com/nianticlabs/spz/main/samples

.PHONY: gen build install test ql reset fixtures

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(DERIVED) build

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

install: build
	-pkill -x $(APP)
	-$(LSREGISTER) -u $(DERIVED)/Build/Products/Release/$(APP).app
	rm -rf /Applications/$(APP).app
	ditto $(DERIVED)/Build/Products/Release/$(APP).app /Applications/$(APP).app
	$(LSREGISTER) -f -R -trusted /Applications/$(APP).app
	open /Applications/$(APP).app

test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug \
		-derivedDataPath $(DERIVED) test

ql:
	qlmanage -p fixtures/hornedlizard.spz

reset:
	qlmanage -r && qlmanage -r cache

fixtures:
	mkdir -p fixtures
	curl -L --max-time 300 -o fixtures/hornedlizard.spz  $(SPZ_SAMPLE_BASE)/hornedlizard.spz
	curl -L --max-time 300 -o fixtures/racoonfamily.spz  $(SPZ_SAMPLE_BASE)/racoonfamily.spz
	printf 'this is not a spz' > fixtures/broken.spz
```

- [ ] **Step 4: ホストアプリ `SPZQuickLook/SPZQuickLookApp.swift`**

```swift
import SwiftUI

@main
struct SPZQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("SPZ Quick Look")
                    .font(.title2)
                Text("Finder で .spz を選んでスペースキーを押すとプレビューされます。\nこのアプリは拡張を登録するためだけに存在します。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(minWidth: 420, minHeight: 240)
        }
    }
}
```

- [ ] **Step 5: appex スタブ `PreviewExtension/PreviewViewController.swift`**

```swift
import Cocoa
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // スタブ: Task 6 で実装する。それまでは QL 標準フォールバックに落とす
        throw CocoaError(.featureUnsupported)
    }
}
```

`PreviewExtension/PreviewExtension.entitlements` は XcodeGen が properties から生成するため、`touch` で空ファイルを作らず **project.yml の記述だけで足りるか `make gen` で確認**。XcodeGen は entitlements の properties 指定時にファイルを自動生成する。

- [ ] **Step 6: ビルド確認**

実行: `make build`
期待: `** BUILD SUCCEEDED **` (SPM 解決で MetalSplatter 1.0.1 + spz-swift が取得される)

- [ ] **Step 7: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add .gitignore project.yml Makefile SPZQuickLook PreviewExtension
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: プロジェクト骨格 (ホストアプリ + QL appex スタブ + MetalSplatter 依存)"
```

---

### Task 2: MatrixMath (行列ヘルパー)

**Files:**
- Create: `PreviewExtension/MatrixMath.swift`
- Test: `Tests/MatrixMathTests.swift`
- Modify: `project.yml` (UnitTests ターゲットと schemes の test 行を追加 — Task 1 の注参照)

**Interfaces:**
- Produces:
  - `func matrixPerspectiveRH(fovYRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4`
  - `func matrixTranslation(_ t: SIMD3<Float>) -> simd_float4x4`
  - `func matrixRotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4`

- [ ] **Step 1: 失敗するテストを書く** (`Tests/MatrixMathTests.swift`)

```swift
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
```

- [ ] **Step 2: project.yml に UnitTests を追加**

Task 1 の注の通り、UnitTests ターゲット (sources: `Tests`, `PreviewExtension/MatrixMath.swift`) と schemes の `test: targets: [UnitTests]` を追加。OrbitCamera.swift / SplatBounds.swift の行は各 Task で追加する。

- [ ] **Step 3: 実行して失敗を確認**

実行: `make test`
期待: FAIL (`matrixTranslation` 未定義のコンパイルエラー)

- [ ] **Step 4: 最小実装** (`PreviewExtension/MatrixMath.swift`)

```swift
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
```

- [ ] **Step 5: 実行して通過を確認**

実行: `make test`
期待: PASS

- [ ] **Step 6: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add project.yml PreviewExtension/MatrixMath.swift Tests/MatrixMathTests.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: 行列ヘルパー (perspective/translation/rotation)"
```

---

### Task 3: SplatBounds (バウンディング球)

**Files:**
- Create: `PreviewExtension/SplatBounds.swift`
- Test: `Tests/SplatBoundsTests.swift`
- Modify: `project.yml` (UnitTests sources に `PreviewExtension/SplatBounds.swift` を追加)

**Interfaces:**
- Produces: `struct SplatBounds { var center: SIMD3<Float>; var radius: Float; init(positions: [SIMD3<Float>]) }`
- Consumes: なし (純ロジック)

- [ ] **Step 1: 失敗するテストを書く** (`Tests/SplatBoundsTests.swift`)

```swift
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
```

- [ ] **Step 2: 実行して失敗を確認**

実行: `make test`
期待: FAIL (`SplatBounds` 未定義)

- [ ] **Step 3: 最小実装** (`PreviewExtension/SplatBounds.swift`)

```swift
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
```

- [ ] **Step 4: 実行して通過を確認**

実行: `make test`
期待: PASS

- [ ] **Step 5: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add project.yml PreviewExtension/SplatBounds.swift Tests/SplatBoundsTests.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: バウンディング球計算"
```

---

### Task 4: OrbitCamera

**Files:**
- Create: `PreviewExtension/OrbitCamera.swift`
- Test: `Tests/OrbitCameraTests.swift`
- Modify: `project.yml` (UnitTests sources に `PreviewExtension/OrbitCamera.swift` を追加)

**Interfaces:**
- Consumes: `SplatBounds` (Task 3)、`matrixPerspectiveRH`/`matrixTranslation`/`matrixRotation` (Task 2)
- Produces:

```swift
struct OrbitCamera {
    init(bounds: SplatBounds)
    mutating func rotate(deltaYaw: Float, deltaPitch: Float)  // ラジアン
    mutating func zoom(factor: Float)                          // 1 より大で近づく
    var viewMatrix: simd_float4x4 { get }
    func projectionMatrix(aspect: Float) -> simd_float4x4
}
```

- [ ] **Step 1: 失敗するテストを書く** (`Tests/OrbitCameraTests.swift`)

```swift
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
```

- [ ] **Step 2: 実行して失敗を確認**

実行: `make test`
期待: FAIL (`OrbitCamera` 未定義)

- [ ] **Step 3: 最小実装** (`PreviewExtension/OrbitCamera.swift`)

```swift
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
```

- [ ] **Step 4: 実行して通過を確認**

実行: `make test`
期待: PASS (Step 1 の `testInitialDistanceFitsBoundingSphere` の期待値 2.20 は `1 / tan(32.5°) * 1.4` = 2.197)

- [ ] **Step 5: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add project.yml PreviewExtension/OrbitCamera.swift Tests/OrbitCameraTests.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: オービットカメラ (回転クランプ・ズームクランプ・初期フレーミング)"
```

---

### Task 5: SPZLoader (デコード層)

**Files:**
- Create: `PreviewExtension/SPZLoader.swift`

**Interfaces:**
- Consumes: `AutodetectSceneReader` / `SplatPoint` (SplatIO)、`SplatBounds` (Task 3)
- Produces:

```swift
struct SplatLoadResult {
    let points: [SplatPoint]     // 上限適用済み
    let truncatedCount: Int      // 省略した個数 (0 なら全量)
    let bounds: SplatBounds      // 上限適用後の点群のバウンディング球
}
enum SPZLoader {
    static let maxSplatCount = 4_000_000
    static func load(url: URL) async throws -> SplatLoadResult
}
enum SPZLoaderError: Error { case emptyScene }
```

デコード自体 (gzip/ヘッダ検証) は SplatIO/spz-swift がエラーを throw する。ここのユニットテストは持たない (純ロジックは Task 3 で担保済み、SplatPoint の public イニシャライザ有無が不確実なため合成データを作らない)。実物 fixtures での確認は Task 7。

- [ ] **Step 1: 実装** (`PreviewExtension/SPZLoader.swift`)

```swift
import Foundation
import SplatIO

struct SplatLoadResult {
    let points: [SplatPoint]
    let truncatedCount: Int
    let bounds: SplatBounds
}

enum SPZLoaderError: Error {
    case emptyScene
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
```

- [ ] **Step 2: ビルド確認**

実行: `make build`
期待: `** BUILD SUCCEEDED **`

- [ ] **Step 3: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add PreviewExtension/SPZLoader.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: SPZLoader (SplatIO デコード + 上限カット + bounds)"
```

---

### Task 6: 描画層 (SplatSceneRenderer + SplatMetalView)

**Files:**
- Create: `PreviewExtension/SplatSceneRenderer.swift`, `PreviewExtension/SplatMetalView.swift`

**Interfaces:**
- Consumes: `SplatRenderer`/`SplatChunk`/`ViewportDescriptor` (MetalSplatter)、`OrbitCamera` (Task 4)、`SplatLoadResult` (Task 5)
- Produces:
  - `SplatSceneRenderer: NSObject, MTKViewDelegate` — `init(device:camera:) throws`, `func add(points: [SplatPoint]) async throws`, `var camera: OrbitCamera`
  - `SplatMetalView: MTKView` — `init(device: MTLDevice, sceneRenderer: SplatSceneRenderer)`, `var isDarkBackground: Bool`

- [ ] **Step 1: SplatSceneRenderer 実装** (`PreviewExtension/SplatSceneRenderer.swift`)

```swift
import Foundation
import MetalKit
import MetalSplatter
import SplatIO

/// MTKView の draw ループで MetalSplatter SplatRenderer に viewport を渡して描画する。
/// 深度ソート・アルファブレンドは SplatRenderer 内部 (SplatSorter) が自動で行う
@MainActor
final class SplatSceneRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderer: SplatRenderer
    // SampleApp と同じ in-flight 3 フレーム制御
    private let inFlight = DispatchSemaphore(value: 3)
    private var drawableSize: CGSize = .zero

    var camera: OrbitCamera

    init(device: MTLDevice, camera: OrbitCamera) throws {
        guard let queue = device.makeCommandQueue() else {
            throw SPZLoaderError.emptyScene // 到達しない想定。CommandQueue 生成失敗は実質 GPU 無し環境
        }
        self.device = device
        self.commandQueue = queue
        self.camera = camera
        self.renderer = try SplatRenderer(
            device: device,
            colorFormat: .bgra8Unorm_srgb,
            depthFormat: .depth32Float,
            sampleCount: 1,
            maxViewCount: 1,
            maxSimultaneousRenders: 3
        )
        super.init()
    }

    func add(points: [SplatPoint]) async throws {
        let chunk = try SplatChunk(device: device, from: points)
        await renderer.addChunk(chunk)
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        Task { @MainActor in self.drawableSize = size }
    }

    func draw(in view: MTKView) {
        guard renderer.isReadyToRender,
              drawableSize.width > 0, drawableSize.height > 0,
              let drawable = view.currentDrawable else { return }
        inFlight.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        let width = Int(drawableSize.width), height = Int(drawableSize.height)
        let viewport = ViewportDescriptor(
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(width), height: Double(height),
                                  znear: 0, zfar: 1),
            projectionMatrix: camera.projectionMatrix(aspect: Float(width) / Float(height)),
            viewMatrix: camera.viewMatrix,
            screenSize: SIMD2(width, height)
        )
        // 戻り値 false = ソート未完了等でフレームドロップ (present しない)
        let didRender = (try? renderer.render(
            viewports: [viewport],
            colorTexture: drawable.texture,
            colorStoreAction: .store,
            depthTexture: view.depthStencilTexture,
            rasterizationRateMap: nil,
            renderTargetArrayLength: 0,
            to: commandBuffer
        )) ?? false
        if didRender {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
```

注 (`draw(in:)` は MTKViewDelegate 上 nonisolated 宣言): Swift 5.10 の最小並行性チェックでは `@MainActor` クラスの同期メソッドとしてビルドが通る見込みだが、コンパイルエラーになる場合は `draw(in:)` / `mtkView(_:drawableSizeWillChange:)` を `nonisolated` にして `MainActor.assumeIsolated { ... }` で包む (MTKView のコールバックはメインスレッド)。

- [ ] **Step 2: SplatMetalView 実装** (`PreviewExtension/SplatMetalView.swift`)

```swift
import AppKit
import MetalKit

/// マウス入力をオービットカメラに変換する MTKView。
/// 背景色は SplatRenderer の clear が透明 (0,0,0,0) なのを利用し、layer の背景色で切り替える
final class SplatMetalView: MTKView {
    private let sceneRenderer: SplatSceneRenderer

    var isDarkBackground = true {
        didSet { applyBackgroundColor() }
    }

    init(device: MTLDevice, sceneRenderer: SplatSceneRenderer) {
        self.sceneRenderer = sceneRenderer
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm_srgb
        depthStencilPixelFormat = .depth32Float
        sampleCount = 1
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        delegate = sceneRenderer
        wantsLayer = true
        layer?.isOpaque = false
        applyBackgroundColor()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // spec: ダーク #262626 ⇄ ライト #d9d9d9
    private func applyBackgroundColor() {
        layer?.backgroundColor = isDarkBackground
            ? CGColor(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)
            : CGColor(red: 0xd9 / 255.0, green: 0xd9 / 255.0, blue: 0xd9 / 255.0, alpha: 1)
    }

    override func mouseDragged(with event: NSEvent) {
        sceneRenderer.camera.rotate(
            deltaYaw: Float(event.deltaX) * 0.01,
            deltaPitch: Float(event.deltaY) * 0.01
        )
    }

    func zoom(magnificationDelta: CGFloat) {
        sceneRenderer.camera.zoom(factor: Float(1.0 + magnificationDelta))
    }
}
```

- [ ] **Step 3: ビルド確認**

実行: `make build`
期待: `** BUILD SUCCEEDED **`

- [ ] **Step 4: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add PreviewExtension/SplatSceneRenderer.swift PreviewExtension/SplatMetalView.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: Metal 描画層 (SplatRenderer 統合 + マウス入力ビュー)"
```

---

### Task 7: PreviewViewController 統合 + 実機確認

**Files:**
- Modify: `PreviewExtension/PreviewViewController.swift` (Task 1 のスタブを置き換え)

**Interfaces:**
- Consumes: `SPZLoader` (Task 5)、`SplatSceneRenderer`/`SplatMetalView` (Task 6)、`OrbitCamera` (Task 4)

- [ ] **Step 1: 実装** (`PreviewExtension/PreviewViewController.swift` 全置換)

```swift
import Cocoa
import MetalKit
import OSLog
import QuickLookUI

class PreviewViewController: NSViewController, QLPreviewingController {

    private static let logger = Logger(subsystem: "jp.trapple.SPZQuickLook", category: "preview")

    private var eventMonitors: [Any] = []
    private weak var splatView: SplatMetalView?

    override func loadView() {
        view = NSView()
        // QL ホスト内では SwiftUI ジェスチャにピンチ/スクロールが配送されない
        // (glb-quicklook の知見) ため、AppKit のイベントモニタで直接拾ってズームする
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.splatView?.zoom(magnificationDelta: event.magnification)
            return event
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.splatView?.zoom(magnificationDelta: event.scrollingDeltaY * 0.01)
            return event
        } as Any)
    }

    deinit {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CocoaError(.featureUnsupported)
        }
        // 失敗時はそのまま throw し、Quick Look 標準フォールバックに任せる (Fail Fast)
        let result: SplatLoadResult
        do {
            result = try await SPZLoader.load(url: url)
        } catch {
            Self.logger.error("SPZ load failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            throw error
        }

        let sceneRenderer = try SplatSceneRenderer(device: device, camera: OrbitCamera(bounds: result.bounds))
        try await sceneRenderer.add(points: result.points)

        let splatView = SplatMetalView(device: device, sceneRenderer: sceneRenderer)
        splatView.frame = view.bounds
        splatView.autoresizingMask = [.width, .height]
        view.addSubview(splatView)
        self.splatView = splatView

        addBackgroundToggleButton(on: splatView)
        if result.truncatedCount > 0 {
            addTruncationLabel(on: splatView, count: result.truncatedCount)
        }
    }

    private func addBackgroundToggleButton(on splatView: SplatMetalView) {
        let button = NSButton(
            image: NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "背景色を切り替え")!,
            target: nil, action: #selector(toggleBackground(_:))
        )
        button.target = self
        button.isBordered = false
        button.toolTip = "背景色を切り替え"
        button.translatesAutoresizingMaskIntoConstraints = false
        splatView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: splatView.topAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: splatView.trailingAnchor, constant: -10),
        ])
    }

    @objc private func toggleBackground(_ sender: NSButton) {
        splatView?.isDarkBackground.toggle()
    }

    private func addTruncationLabel(on splatView: SplatMetalView, count: Int) {
        // 上限超過はサイレントに切り捨てず必ず可視化する (spec)
        let label = NSTextField(labelWithString: "⚠︎ \(count.formatted()) 個のスプラットを省略")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        splatView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: splatView.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: splatView.leadingAnchor, constant: 10),
        ])
    }
}
```

- [ ] **Step 2: ビルド + fixtures 取得**

実行: `make build && make fixtures`
期待: BUILD SUCCEEDED、`fixtures/hornedlizard.spz` (約 18MB)・`fixtures/racoonfamily.spz` (約 24MB)・`fixtures/broken.spz` が存在

- [ ] **Step 3: インストール + 拡張登録確認**

実行: `make install` → `pluginkit -m | grep -i spz`
期待: `jp.trapple.SPZQuickLook.PreviewExtension` が表示される (先頭 `+` または `?`)

- [ ] **Step 4: 実機確認 (小さくイテレーション: まず 1 件)**

実行: `make ql` (= `qlmanage -p fixtures/hornedlizard.spz`)

チェックリスト (ユーザー目視):
1. トカゲのスプラットシーンが表示される (1 秒以内目安)
2. ドラッグで回転する
3. スクロール / ピンチでズームする
4. 右上ボタンで背景がダーク ⇄ ライト切替
5. 勝手に回転しない

- [ ] **Step 5: 残りの fixtures 確認**

実行: `qlmanage -p fixtures/racoonfamily.spz` → 表示されること
実行: `qlmanage -p fixtures/broken.spz` → **QL 標準フォールバック (ファイル情報) に落ちること**。クラッシュしないこと

表示異常 (上下逆・鏡像) がある場合: `OrbitCamera.viewMatrix` の Z 軸 π 回転 (commonUpCalibration) を調整して再確認する。

- [ ] **Step 6: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add PreviewExtension/PreviewViewController.swift
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "feat: QL プレビュー統合 (ロード → Metal 描画 + 背景切替 + 省略可視化)"
```

---

### Task 8: README

**Files:**
- Create: `README.md`, `README-ja.md`, `LICENSE` (MIT、glb-quicklook と同じ)

- [ ] **Step 1: README.md** (glb-quicklook の README 構成を踏襲)

```markdown
# 3DGS Quick Look

English | [日本語](README-ja.md)

A macOS Quick Look extension that previews .spz (3D Gaussian Splatting) files with the spacebar in Finder.
Native implementation with Metal ([MetalSplatter](https://github.com/scier/MetalSplatter)) — no WebView, no auto-rotation.

- Drag to orbit, pinch or two-finger scroll to zoom
- Toggle dark ⇄ light background with the button in the top-right corner
- Broken files fall back to the standard Quick Look file info view

Requires macOS 15+ on Apple Silicon.

## Build from source

Requirements: Xcode / xcodegen (`brew install xcodegen`)

```bash
make install   # xcodegen → xcodebuild → copy to /Applications → register
```

If previews don't show up, try `make reset` (resets the qlmanage cache) and `killall Finder`.
Still nothing? Check the registration with `pluginkit -m | grep -i spz`.

## Development

```bash
make fixtures  # download sample .spz files (Niantic Labs samples) into fixtures/
make test      # unit tests
make ql        # open a preview directly via qlmanage -p fixtures/hornedlizard.spz
```

## License

[MIT](LICENSE)
```

- [ ] **Step 2: README-ja.md** (同内容の日本語版)

README.md と同構成で日本語化する (glb-quicklook の README-ja.md を参照)。

- [ ] **Step 3: LICENSE**

glb-quicklook の LICENSE (MIT) をコピーし、年と名前はそのまま (`Copyright (c) 2026 trapple`)。

- [ ] **Step 4: commit**

```bash
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook add README.md README-ja.md LICENSE
git -C /Users/trapple/repos/github.com/trapple/3dgs-quicklook commit -m "docs: README (en/ja) と LICENSE"
```

---

## セルフレビュー結果

- spec カバー率: プレビュー拡張・カメラ操作・背景切替・自動回転なし・Fail Fast・上限可視化・UTI 宣言・XcodeGen/Makefile・fixtures・受け入れ条件 — 全て対応タスクあり。「SPZLoader を描画層から分離」も Task 5/6 の分割で担保
- placeholder: なし (上限 4,000,000 と fixtures URL は本プランで確定済み)
- 型一貫性: `SplatLoadResult`/`SplatBounds`/`OrbitCamera` のシグネチャは Task 間で一致を確認済み
- 未知数として残るもの: MetalSplatter 1.0.1 の細部 API 差異 (例: `draw(in:)` の並行性チェック、`SplatChunk` init のラベル)。ビルドエラーが出た場合はライブラリのソース (`build/SourcePackages/checkouts/MetalSplatter`) を直接確認して合わせる

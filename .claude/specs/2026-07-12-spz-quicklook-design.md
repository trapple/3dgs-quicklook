# SPZ Quick Look 拡張 設計書

日付: 2026-07-12
ステータス: 承認済み (2026-07-12 描画方式を MetalSplatter に変更 — 改訂理由は「技術選定」参照)

## 目的

3D Gaussian Splatting の圧縮フォーマット .spz (Niantic Labs) を Finder のスペースキー (Quick Look) でプレビューできる macOS 拡張を自作する。

動機: .spz に対応した macOS 用 Quick Look ツールが存在しない (ifc-quicklook と同じ動機)。

## 要件

- 対応形式: **.spz のみ** (.ply / .splat / .ksplat はスコープ外)
- スコープ: **プレビューのみ** (Finder サムネイル拡張は作らない)
- 機能: カメラ操作 (ドラッグ回転 + ズーム + 二本指横スクロールでパン) と背景色切替のみ
- **自動回転なし**。アニメーション (動的スプラット列) なし
- 配布: 自分用 (公証不要、対応 OS 下限は開発機の macOS でよい)

## 技術選定

### 描画 + パーサ: MetalSplatter (SplatIO 含む)

| 検討案 | 判定 | 理由 |
|---|---|---|
| [scier/MetalSplatter](https://github.com/scier/MetalSplatter) | ✅ 採用 | Swift/Metal 製 OSS (MIT)。**SPZ をネイティブ入出力サポート** (SplatIO レイヤ、内部は同作者の spz-swift 系実装)。深度ソート + アルファブレンドのレンダリングパイプラインをライブラリが持つ。iOS/macOS/visionOS 対応済み・App Store の同名アプリで実績あり |
| RealityKit `GaussianSplatComponent` (WWDC26) | ✗ 現時点不可 | **macOS 27.0+ (beta) の API**。開発機 (macOS 26 + Xcode 26.4.1) の SDK に存在しないことを swiftinterface の grep で実測確認済み。公式ドキュメントの availability も iOS/macOS/visionOS 27.0+ Beta。macOS 27 正式リリース後の乗り換え候補としてスコープ外へ |
| 自作 Metal レンダラー | ✗ | MetalSplatter が同じものをライブラリとして提供している。車輪の再発明 |
| [nianticlabs/spz](https://github.com/nianticlabs/spz) 公式 C++ パーサ | ✗ | ObjC++ シム層の複雑さを持ち込む。SplatIO で足りる |

パーサも MetalSplatter 同梱の SplatIO を使う (依存は **MetalSplatter 1 パッケージだけ**)。SplatIO で不足があれば同作者の [spz-swift](https://github.com/scier/spz-swift) (`import spz`、macOS 14+、純 Swift) を追加する余地はあるが、YAGNI で最初は入れない。

描画は Metal (MTKView) ベースになるため、ビューは glb-quicklook の SwiftUI RealityView 構成ではなく、**AppKit NSViewController + MTKView** 構成 (ifc-quicklook の ARView + 自作オービットカメラに近い形) を取る。

## アーキテクチャ

Quick Look 拡張は単体配布できないため「ホストアプリ + 拡張」の 2 ターゲット構成 (既存 2 プロジェクトと同じ)。

```
SPZQuickLook.app (ホスト。ほぼ空。/Applications に置いて拡張を登録するだけ)
└── PreviewExtension.appex (com.apple.quicklook.preview)
    ├── PreviewViewController  … QLPreviewingController 実装。入口
    ├── SplatMetalView         … MTKView + MetalSplatter SplatRenderer + 背景切替ボタン
    ├── OrbitCamera            … 自作オービットカメラ (ドラッグ回転 + ズーム、view/projection 行列を生成)
    ├── SPZLoader              … SplatIO で .spz をデコードし SplatRenderer に流し込む + bbox 計算
    └── MetalSplatter (SPM 依存: MetalSplatter + SplatIO プロダクト)
```

- **PreviewViewController**: `preparePreviewOfFile(at:)` で URL を受け取り、SPZLoader でロード → SplatMetalView を載せる薄い層。マウスドラッグ / スクロール / ピンチのイベントは AppKit で直接拾う (QL ホスト内では SwiftUI ジェスチャにピンチ/スクロールが配送されない glb-quicklook の知見)
- **SplatMetalView / OrbitCamera**: MTKView の draw ループで SplatRenderer に viewport (view/projection 行列) を渡して描画。右上に背景色切替ボタンを 1 つだけ置く
- 依存は **MetalSplatter の 1 パッケージだけ**。純 Swift SPM パッケージなので glb-quicklook の GLTFKit2 (バイナリ XCFramework の vendor 取得) より単純に、XcodeGen の SPM 依存としてそのまま宣言する
- ビルドは **XcodeGen (project.yml)** でプロジェクト定義をテキスト管理 (.xcodeproj は git 管理外)。Makefile に `gen` / `build` / `install` / `test` / `ql` / `reset` / `fixtures` ターゲット (既存 2 プロジェクトと同一パターン)
- 対象 UTI: Apple 公式 UTI が無いため `UTImportedTypeDeclarations` で自己宣言
  - 識別子: `com.nianticlabs.spz` (フォーマット提供元 Niantic の逆引きドメイン)
  - `UTTypeConformsTo: [public.data, public.3d-content]`
  - 拡張子: `spz`

## データフロー

1. Finder でスペースキー → 拡張プロセス起動 → `preparePreviewOfFile(at url:)`
2. SPZLoader が SplatIO で .spz を読み込み (gzip 展開 + デコードはライブラリ内部、バックグラウンド実行)
3. デコードした点群を SplatRenderer に追加し、MTKView の draw ループで描画 (深度ソート + アルファブレンドはライブラリ内部)
4. 全 position からバウンディングボックスを計算し、モデル全体が収まるよう初期カメラ距離を決定
5. ドラッグ = オービット、縦スクロール / ピンチ = ズーム、**Shift+ドラッグ / 右ドラッグ = パン**。自動回転なし
   - 横スクロールのパンも実装するが、QL ホストが横スクロールの delta を奪う (dx=0 で届く) ことを qlmanage で実測済みのため、確実に動く経路として修飾キー付きドラッグを正とする

座標系: .spz のデフォルトは RUB (OpenGL/three.js 準拠)。SplatIO/MetalSplatter は SPZ ネイティブ対応なので基本はライブラリ既定に任せるが、実機確認で上下・鏡像の反転が出た場合はロード時またはカメラ側で変換を挟む。

## エラーハンドリング (Fail Fast)

- gzip 展開失敗・ヘッダ不正・非対応バージョン (SPZ 4 等の将来フォーマットで読めないもの) → `preparePreviewOfFile` から throw し、Quick Look 標準のフォールバック (ファイル情報表示) に任せる。壊れた 3D 表示を出さない
- ガウシアン数上限を設ける (具体値は実機の描画性能を見て実装時に確定)。**上限超過時は「⚠︎ N 個省略」をオーバーレイで可視化**し、サイレントに切り捨てない (ifc-quicklook の三角形上限と同じ方針)
- タイムアウトは設けない (Quick Look 自体が拡張プロセスを管理・強制終了するため二重管理になる)

## テスト方針

自動テストは最小とし、実物確認を軸にする (glb-quicklook と同方針)。

**開発ループ**: `make build` → アプリを一度起動して拡張登録 (`pluginkit -m` で確認) → `qlmanage -p fixtures/sample.spz` で直接プレビュー起動。

**自動テスト**: SPZLoader のデコード結果検証が中心。ヘッダ値 (numPoints / shDegree)・ガウシアン数・bbox の期待値を固定した XCTest。

**テスト用アセット** (`fixtures/` に取得。取得元は実装時に確定 — 候補: Babylon.js サンプルアセット、nianticlabs/spz のテストデータ、Scaniverse 公開シーン):

| ファイル | 確認内容 |
|---|---|
| 小さいシーン (数万スプラット) | 最小ケースが即座に表示される |
| 中規模シーン (数十万〜百万スプラット) | 実用シーンの見栄えと表示速度 |
| SH 係数付きシーン (shDegree ≥ 1) | 視線方向依存の色が正しく出る |
| 壊れたファイル (自作) | 標準フォールバックへ落ちること |

## マイルストーン (小さく回す)

1. **M1**: MetalSplatter を SPM 依存に取り、fixtures の .spz を SplatIO でデコード → SplatRenderer + MTKView で単体表示できるところまで (**最大リスク = ライブラリ統合なので最初に潰す**)
2. **M2**: オービットカメラ + 初期フレーミング + 背景切替
3. **M3**: QL appex 化 (ホストアプリ・UTI 宣言・サンドボックス)、スペースキーで表示
4. **M4**: エラー表示・上限可視化・仕上げ

## 受け入れ条件

1. Finder でスペースキー → 小さいシーンなら体感即座 (1 秒以内目安) に表示される
2. ドラッグで回転、スクロール / ピンチでズームできる
3. 背景色トグルが効く
4. 勝手に回転しない
5. 不正な .spz でクラッシュせず標準フォールバックする

## スコープ外 (将来の拡張候補)

- **RealityKit `GaussianSplatComponent` への乗り換え (積極検討)**: macOS 27 正式リリース + Xcode 27 GA が揃ったら、描画層を MetalSplatter から Apple ネイティブ API に乗り換えることをぜひ試したい。SplatIO/spz-swift のデコード結果 (position/scale/rotation/opacity/SH) を `GaussianSplatResource.BufferResource` (LowLevelBuffer + BufferDescriptor) に流し込む形で、パーサ層はそのまま流用できる見込み。WWDC26「Explore advances in RealityKit」参照。SPZLoader を描画層から分離しておくのはこの乗り換えを見据えた設計判断
- Finder サムネイル拡張
- .ply / .splat / .ksplat 対応 (SplatIO 自体は対応しているため、UTI 宣言追加だけで対応できる可能性が高い)
- SPZ 4 等の将来フォーマットバージョンの完全対応 (読めれば良い。書き込み系は対象外)
- アニメーション (動的スプラット列) 対応
- Developer ID 署名 + 公証、Homebrew cask 等の配布整備 (glb-quicklook の配布整備 spec と同様、別フェーズで検討)

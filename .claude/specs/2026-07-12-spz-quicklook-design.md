# SPZ Quick Look 拡張 設計書

日付: 2026-07-12
ステータス: 承認待ち

## 目的

3D Gaussian Splatting の圧縮フォーマット .spz (Niantic Labs) を Finder のスペースキー (Quick Look) でプレビューできる macOS 拡張を自作する。

動機: .spz に対応した macOS 用 Quick Look ツールが存在しない (ifc-quicklook と同じ動機)。

## 要件

- 対応形式: **.spz のみ** (.ply / .splat / .ksplat はスコープ外)
- スコープ: **プレビューのみ** (Finder サムネイル拡張は作らない)
- 機能: カメラ操作 (ドラッグ回転 + ズーム) と背景色切替のみ
- **自動回転なし**。アニメーション (動的スプラット列) なし
- 配布: 自分用 (公証不要、対応 OS 下限は開発機の macOS でよい)

## 技術選定

### パーサ: spz-swift (純 Swift 実装)

| 検討案 | 判定 | 理由 |
|---|---|---|
| [scier/spz-swift](https://github.com/scier/spz-swift) | ✅ 採用 | 純 Swift。gzip 展開は Foundation 標準の Compression フレームワークで完結し、C/C++ ブリッジ不要。v2.1.0 (2026-02) 相当 |
| [nianticlabs/spz](https://github.com/nianticlabs/spz) 公式 C++ | ✗ | ifc-quicklook で必要だった ObjC++ シム層の複雑さを持ち込むことになる。純 Swift 版があるなら不要 |
| 自前パーサ | ✗ | フォーマット仕様 (24bit 固定小数点 position、SH 係数の量子化等) の再実装は車輪の再発明 |

### 描画: RealityKit `GaussianSplatComponent` (WWDC26 追加のネイティブ API) 一本

`GaussianSplatResource` に position / scale / rotation / opacity / SH 係数のバッファを渡して構築し、`GaussianSplatComponent` として Entity にアタッチするだけで、深度ソート + アルファブレンドの Gaussian Splat 描画を RealityKit が行う。glb-quicklook と同じ「ネイティブ API + 自作レンダラー不要」の軽量構成。

**最大リスク**: この API の macOS 対応可否が事前調査 (公式ドキュメント・WWDC26 セッション) では確認しきれなかった (visionOS 中心の記載)。**実装の最初のマイルストーンで実機検証して潰す** (ifc-quicklook の M1 と同じ考え方)。使えないと判明した場合は設計に戻り、フォールバック方針 (MetalSplatter ベースの自作 Metal レンダラー等) を再検討する。

自作 Metal レンダラーのフォールバック実装は**今回のスコープに含めない** (ユーザー判断で確定)。

## アーキテクチャ

Quick Look 拡張は単体配布できないため「ホストアプリ + 拡張」の 2 ターゲット構成 (既存 2 プロジェクトと同じ)。

```
SPZQuickLook.app (ホスト。ほぼ空。/Applications に置いて拡張を登録するだけ)
└── PreviewExtension.appex (com.apple.quicklook.preview)
    ├── PreviewViewController  … QLPreviewingController 実装。入口
    ├── SplatPreviewView       … SwiftUI。RealityView + GaussianSplatComponent + 背景切替ボタン
    ├── SPZLoader              … spz-swift でデコードし GaussianSplatResource を構築
    └── spz-swift (SPM 依存)
```

- **PreviewViewController**: `preparePreviewOfFile(at:)` で URL を受け取り、SPZLoader でロード → `NSHostingView` で SwiftUI ビューを載せる薄い層
- **SplatPreviewView**: `RealityView` にエンティティを配置。カメラ操作 (オービット + ズーム)。右上に背景色切替ボタンを 1 つだけ置く。QL ホスト内では SwiftUI ジェスチャにピンチ/スクロールが配送されない glb-quicklook の知見があるため、AppKit イベントモニタ方式 (PinchZoom 相当) を流用する
- 依存は **spz-swift の 1 つだけ**。純 Swift SPM パッケージなので glb-quicklook の GLTFKit2 (バイナリ XCFramework の vendor 取得) より単純に、XcodeGen の SPM 依存としてそのまま宣言する
- ビルドは **XcodeGen (project.yml)** でプロジェクト定義をテキスト管理 (.xcodeproj は git 管理外)。Makefile に `gen` / `build` / `install` / `test` / `ql` / `reset` / `fixtures` ターゲット (既存 2 プロジェクトと同一パターン)
- 対象 UTI: Apple 公式 UTI が無いため `UTImportedTypeDeclarations` で自己宣言
  - 識別子: `com.nianticlabs.spz` (フォーマット提供元 Niantic の逆引きドメイン)
  - `UTTypeConformsTo: [public.data, public.3d-content]`
  - 拡張子: `spz`

## データフロー

1. Finder でスペースキー → 拡張プロセス起動 → `preparePreviewOfFile(at url:)`
2. SPZLoader がファイルを読み込み → gzip 展開 → ヘッダ + ガウシアン配列にデコード (バックグラウンド実行)
3. `GaussianSplatResource` を構築 → `GaussianSplatComponent` を Entity にアタッチ → `RealityView` に配置
4. 全 position からバウンディングボックスを計算し、モデル全体が収まるよう初期カメラ距離を決定
5. ドラッグ = オービット、スクロール / ピンチ = ズーム。自動回転なし

座標系: .spz のデフォルトは RUB (OpenGL/three.js 準拠)。RealityKit も RUB (右手系 Y-up) なので基本は素通しだが、実機確認で上下・鏡像の反転が出た場合はロード時に変換を挟む。

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

1. **M1**: `GaussianSplatComponent` / `GaussianSplatResource` が macOS で使えるかの実機検証。最小 Swift コードで数個のダミーガウシアンを表示できるところまで (**最大リスクなので最初に潰す**。ダメなら設計に戻る)
2. **M2**: spz-swift で fixtures をデコードし、GaussianSplatResource に流し込んで単体アプリで表示
3. **M3**: QL appex 化 (ホストアプリ・UTI 宣言・サンドボックス)、スペースキーで表示
4. **M4**: カメラフレーミング・背景切替・エラー表示・上限可視化の仕上げ

## 受け入れ条件

1. Finder でスペースキー → 小さいシーンなら体感即座 (1 秒以内目安) に表示される
2. ドラッグで回転、スクロール / ピンチでズームできる
3. 背景色トグルが効く
4. 勝手に回転しない
5. 不正な .spz でクラッシュせず標準フォールバックする

## スコープ外 (将来の拡張候補)

- Finder サムネイル拡張
- .ply / .splat / .ksplat 対応
- SPZ 4 等の将来フォーマットバージョンの完全対応 (読めれば良い。書き込み系は対象外)
- アニメーション (動的スプラット列) 対応
- Developer ID 署名 + 公証、Homebrew cask 等の配布整備 (glb-quicklook の配布整備 spec と同様、別フェーズで検討)
- 自作 Metal レンダラー (GaussianSplatComponent が macOS で使えなかった場合の再検討候補: [scier/MetalSplatter](https://github.com/scier/MetalSplatter) — Swift/Metal, MIT, macOS 対応済み)

# 3DGS Quick Look

[English](README.md) | 日本語

3D Gaussian Splatting ファイルの macOS ビューアです:

- **.spz** — Finder のスペースキーで Quick Look プレビュー
- **.ply (3DGS)** — 単体ビューアウィンドウ (ダブルクリック / このアプリケーションで開く)。.ply のスペースキープレビューは Apple 内蔵拡張が UTI を握っているため上書きできません (OS 仕様)

Metal ([MetalSplatter](https://github.com/scier/MetalSplatter)) によるネイティブ実装 — WebView なし、自動回転なし。

- ドラッグで回転、ピンチまたは二本指の縦スクロールでズーム
- Shift+ドラッグ / 右ドラッグ (または二本指の横スクロール) でパン
- 右上のボタンで背景ダーク ⇄ ライト切替と上下反転 (3DGS には上下軸の標準がないため)
- 壊れたファイルは Quick Look 標準のファイル情報表示にフォールバック

macOS 15 以降・Apple Silicon 専用。

## インストール (Homebrew)

```bash
brew install trapple/tap/3dgs-quicklook
open /Applications/SPZQuickLook.app   # 初回のみ: Quick Look 拡張が登録されます
```

## ply2spz CLI

3DGS の .ply (や .splat) を .spz に変換します — スペースキープレビューが効くようになり、サイズも約 1/10 になります:

```bash
ply2spz input.ply                    # 隣に input.spz を出力
ply2spz input.ply ~/Desktop/out.spz  # 出力先を指定
ply2spz input.ply -f                 # 既存ファイルを上書き
```

Homebrew でインストールすると PATH に入ります (実体はアプリ内 `Contents/Helpers/ply2spz`)。

## ソースからビルド

必要なもの: Xcode / xcodegen (`brew install xcodegen`)

```bash
make install   # xcodegen → xcodebuild → /Applications へコピー → 登録
```

プレビューが出ない場合は `make reset` (qlmanage キャッシュのリセット) と `killall Finder` を試してください。
それでも出ない場合は `pluginkit -m | grep -i spz` で登録を確認してください。

## 開発

```bash
make fixtures  # サンプル .spz (Niantic Labs のサンプル) を fixtures/ に取得
make test      # ユニットテスト
make ql        # qlmanage -p fixtures/hornedlizard.spz で直接プレビュー起動
```

## ライセンス

[MIT](LICENSE)

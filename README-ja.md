# 3DGS Quick Look

[English](README.md) | 日本語

Finder で .spz (3D Gaussian Splatting) ファイルをスペースキーでプレビューできる macOS Quick Look 拡張です。
Metal ([MetalSplatter](https://github.com/scier/MetalSplatter)) によるネイティブ実装 — WebView なし、自動回転なし。

- ドラッグで回転、ピンチまたは二本指の縦スクロールでズーム
- Shift+ドラッグ / 右ドラッグ (または二本指の横スクロール) でパン
- 右上のボタンで背景をダーク ⇄ ライト切替
- 壊れたファイルは Quick Look 標準のファイル情報表示にフォールバック

macOS 15 以降・Apple Silicon 専用。

## インストール (Homebrew)

```bash
brew install trapple/tap/3dgs-quicklook
open /Applications/SPZQuickLook.app   # 初回のみ: Quick Look 拡張が登録されます
```

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

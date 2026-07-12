# SPZ Quick Look 配布整備 設計書

日付: 2026-07-12
ステータス: 承認済み (ユーザー指示「brew install 出来るようにしといて。他の 2 リポジトリを参考にして」)
前提: MVP 完成済み (feature/spz-quicklook)。glb-quicklook の配布整備設計を踏襲する。

## 目的

Developer ID 署名 + 公証済みのバイナリを GitHub Release で配布し、Homebrew (自前 tap `trapple/homebrew-tap`)
でインストールできるようにする。リリース作業を `make release` 1 コマンドに自動化する。

## glb-quicklook との差分

構成・フローは glb-quicklook の配布整備設計と同一。差分のみ列挙する:

| 項目 | 値 |
|---|---|
| リポジトリ | `trapple/3dgs-quicklook` (新規作成: public) |
| アプリ名 | SPZQuickLook.app / リリース資産 `SPZQuickLook-{VERSION}.zip` |
| cask | `Casks/3dgs-quicklook.rb` (`brew install trapple/tap/3dgs-quicklook`) |
| 公証プロファイル | `glb-quicklook-notary` を再利用 (ifc-quicklook も同プロファイルを再利用している前例に従う。プロファイル名は keychain 内の識別子にすぎず Apple ID 単位で共通) |
| cask の依存 | `depends_on macos: ">= :sequoia"` に加えて **`depends_on arch: :arm64`** (MetalSplatter が x86_64 で fatalError するため) |
| zap trash | `~/Library/Containers/jp.trapple.SPZQuickLook*` |

## 共通事項 (glb-quicklook 設計から継承)

- バージョンの正は `project.yml` の `MARKETING_VERSION`。初回リリースは v1.0.0
- `scripts/release.sh`: precheck (main / clean / pushed / tag 未存在 / 証明書 / 公証プロファイル / gh 認証) → 署名ビルド
  (`ENABLE_HARDENED_RUNTIME=YES`, `--timestamp`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`) → notarytool submit --wait →
  staple → zip → tag + GitHub Release → cask の version/sha256 書き換え → tap へ push
- `set -euo pipefail`、全ステップ Fail Fast
- 開発ビルド (`make build` / `make install`) は ad-hoc 署名のまま

## 受け入れ条件

1. `make release` が一度も手を止めずに完走する
2. `spctl -a -vv /Applications/SPZQuickLook.app` が accepted (source=Notarized Developer ID)
3. `brew install trapple/tap/3dgs-quicklook` でインストールでき、スペースキーでプレビューが動く
4. GitHub Release v1.0.0 に staple 済み zip が添付されている

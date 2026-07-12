#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="trapple/3dgs-quicklook"
TAP_DIR="${TAP_DIR:-$HOME/repos/github.com/trapple/homebrew-tap}"
# 公証プロファイルは glb-quicklook のものを再利用 (Apple ID 単位で共通のため)
NOTARY_PROFILE="${NOTARY_PROFILE:-glb-quicklook-notary}"
APP="SPZQuickLook"
CASK_NAME="3dgs-quicklook"
DERIVED="$REPO_DIR/build"

fail() { echo "❌ $1" >&2; exit 1; }

version() {
  grep -m1 'MARKETING_VERSION:' "$REPO_DIR/project.yml" | sed -E 's/.*"([^"]+)".*/\1/'
}

sign_identity() {
  security find-identity -v -p codesigning \
    | grep -m1 'Developer ID Application' \
    | sed -E 's/.*"(.+)".*/\1/'
}

# 証明書名の括弧内 (例: "... (38BCPZ72CZ)") から Team ID を取り出す。
# SPM のリソースバンドル (MetalSplatter のシェーダー) の署名に DEVELOPMENT_TEAM が必要
team_id() {
  sign_identity | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/'
}

precheck() {
  local v
  v="$(version)"
  [[ -n "$v" ]] || fail "project.yml から MARKETING_VERSION を読めません"
  [[ "$(git -C "$REPO_DIR" branch --show-current)" == "main" ]] \
    || fail "main ブランチで実行してください (現在: $(git -C "$REPO_DIR" branch --show-current))"
  [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] \
    || fail "working tree がクリーンではありません"
  git -C "$REPO_DIR" fetch origin main --quiet
  [[ "$(git -C "$REPO_DIR" rev-parse main)" == "$(git -C "$REPO_DIR" rev-parse origin/main)" ]] \
    || fail "main が origin/main と一致していません (push してください)"
  if git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/v$v" >/dev/null; then
    fail "tag v$v は既に存在します (project.yml の MARKETING_VERSION を上げてください)"
  fi
  [[ -n "$(sign_identity)" ]] \
    || fail "Developer ID Application 証明書がありません。Xcode → Settings → Accounts → Manage Certificates で作成してください"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "公証プロファイル '$NOTARY_PROFILE' がありません。次を実行してください: xcrun notarytool store-credentials $NOTARY_PROFILE"
  gh auth status >/dev/null 2>&1 || fail "gh が未認証です (gh auth login)"
  echo "✅ 前提チェック OK (version $v, identity: $(sign_identity))"
}

build_signed() {
  local identity
  identity="$(sign_identity)"
  echo "==> Release ビルド (署名: $identity)"
  make -C "$REPO_DIR" gen
  xcodebuild -project "$REPO_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="$(team_id)" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build
}

notarize_and_staple() {
  local app_path="$DERIVED/Build/Products/Release/$APP.app"
  local submit_zip="$DERIVED/$APP-notarize.zip"
  echo "==> 公証"
  ditto -c -k --keepParent "$app_path" "$submit_zip"
  if ! xcrun notarytool submit "$submit_zip" --keychain-profile "$NOTARY_PROFILE" --wait; then
    fail "公証に失敗しました。詳細: xcrun notarytool history --keychain-profile $NOTARY_PROFILE で ID を確認し、xcrun notarytool log <ID> --keychain-profile $NOTARY_PROFILE"
  fi
  echo "==> staple"
  xcrun stapler staple "$app_path"
}

create_release() {
  local v="$1" zip="$2"
  local app_path="$DERIVED/Build/Products/Release/$APP.app"
  ditto -c -k --keepParent "$app_path" "$zip"
  echo "==> tag v$v + GitHub Release"
  git -C "$REPO_DIR" tag -a "v$v" -m "v$v"
  git -C "$REPO_DIR" push origin "v$v"
  gh release create "v$v" "$zip" -R "$REPO_SLUG" --title "v$v" --generate-notes
}

update_cask() {
  local v="$1" zip="$2"
  local sha
  sha="$(shasum -a 256 "$zip" | awk '{print $1}')"
  echo "==> cask 更新 (version $v, sha256 $sha)"
  [[ -d "$TAP_DIR" ]] || git clone "git@github.com:trapple/homebrew-tap.git" "$TAP_DIR"
  local cask="$TAP_DIR/Casks/$CASK_NAME.rb"
  [[ -f "$cask" ]] || fail "cask がありません: $cask"
  sed -i '' -E "s/^  version \".*\"$/  version \"$v\"/" "$cask"
  sed -i '' -E "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" "$cask"
  git -C "$TAP_DIR" add "Casks/$CASK_NAME.rb"
  git -C "$TAP_DIR" commit -m "$CASK_NAME $v"
  git -C "$TAP_DIR" push
}

run_release() {
  local v
  v="$(version)"
  precheck
  build_signed
  notarize_and_staple
  local zip="$DERIVED/$APP-$v.zip"
  create_release "$v" "$zip"
  update_cask "$v" "$zip"
  echo "🎉 v$v リリース完了: https://github.com/$REPO_SLUG/releases/tag/v$v"
}

main() {
  case "${1:-release}" in
    check) precheck ;;
    release) run_release ;;
    *) fail "usage: release.sh [check]" ;;
  esac
}

main "$@"

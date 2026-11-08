#!/usr/bin/env bash
# Mac で DeskLink をビルドできる状態まで自動で準備する。
#
#   ./scripts/setup-mac.sh            準備して Xcode を開く
#   ./scripts/setup-mac.sh --test     さらにシミュレーターで単体テストを実行
#
# 環境変数（任意）:
#   BUNDLE_ID=com.yourname.desklink   アプリの Bundle Identifier
#   DEVELOPMENT_TEAM=XXXXXXXXXX       署名に使う Team ID（Xcode > Settings > Accounts で確認）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RUN_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --test) RUN_TESTS=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "不明なオプション: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m%s\033[0m\n' "$1" >&2; exit 1; }

# ---- 1. Xcode ----
step "Xcode を確認"
if ! XCODE_PATH="$(xcode-select -p 2>/dev/null)" || [[ "$XCODE_PATH" != *Xcode*.app* ]]; then
  if [ -d /Applications/Xcode.app ]; then
    echo "Xcode を開発ツールとして設定します（パスワードを求められます）"
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  else
    open "macappstore://apps.apple.com/app/xcode/id497799835" || true
    fail "Xcode が見つかりません。App Store で Xcode をインストールし、一度起動してから再実行してください。"
  fi
fi
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "Xcode の初回セットアップを実行します（パスワードを求められます）"
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
fi
xcodebuild -version
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  echo "iOS シミュレーターをダウンロードします（数GB、時間がかかります）"
  xcodebuild -downloadPlatform iOS
fi

# ---- 2. Homebrew とツール ----
step "Homebrew とビルドツールを確認"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew をインストールします（パスワードを求められます）"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
fi
for tool in cmake ninja xcodegen; do
  command -v "$tool" >/dev/null 2>&1 || brew install "$tool"
done

# ---- 3. ライブラリ ----
step "OpenSSL をビルド（済みならスキップ）"
./scripts/build-openssl.sh

step "FreeRDP をビルド（済みならスキップ）"
if [ -f Vendor/iphoneos/lib/libFreeRDPAll.a ] && [ -f Vendor/iphonesimulator/lib/libFreeRDPAll.a ]; then
  echo "ビルド済み（作り直す場合は Vendor/ と build/freerdp/ を削除して再実行）"
else
  ./scripts/build-freerdp.sh
fi

# ---- 4. Xcode プロジェクト ----
step "Xcode プロジェクトを生成"
SPEC=project.yml
if [ -n "${BUNDLE_ID:-}" ] || [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  mkdir -p build
  SPEC=build/project.local.yml
  sed -e "s|PRODUCT_BUNDLE_IDENTIFIER: com.example.desklink|PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID:-com.example.desklink}|" \
      -e "s|DEVELOPMENT_TEAM: \"\".*|DEVELOPMENT_TEAM: \"${DEVELOPMENT_TEAM:-}\"|" \
      project.yml > "$SPEC"
fi
xcodegen --spec "$SPEC" --project-root "$ROOT" --project "$ROOT"

# ---- 5. テスト（任意）----
if [ "$RUN_TESTS" = 1 ]; then
  step "シミュレーターで単体テスト"
  UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = json.load(sys.stdin)["devices"]
ipads = [d for rt, ds in devs.items() if "iOS" in rt for d in ds if d["name"].startswith("iPad")]
print(ipads[-1]["udid"] if ipads else "")')
  [ -n "$UDID" ] || fail "iPad のシミュレーターが見つかりません。Xcode > Settings > Components で iOS を追加してください。"
  xcodebuild test -project DeskLink.xcodeproj -scheme DeskLink -destination "id=$UDID" CODE_SIGNING_ALLOWED=NO
fi

# ---- 6. 仕上げ ----
step "完了"
open DeskLink.xcodeproj
cat <<'EOF'
Xcode が開きます。残りは手作業です:
  1. 左の DeskLink → Signing & Capabilities → Team で自分の Apple ID を選ぶ
     （BUNDLE_ID / DEVELOPMENT_TEAM を指定して実行した場合は不要）
  2. 画面上部の実行先で iPad シミュレーター、または USB 接続した iPad を選んで ▶︎
  実機の場合: iPad の「設定 > プライバシーとセキュリティ > デベロッパモード」をオン、
  初回起動時は「設定 > 一般 > VPNとデバイス管理」で開発元を信頼してください。
EOF

#!/usr/bin/env bash
# Finder でダブルクリックすると、DeskLink の準備（ツール導入・ライブラリのビルド・
# Xcode プロジェクトの生成）を行い、最後に Xcode を開きます。
cd "$(dirname "$0")" || exit 1
chmod +x scripts/*.sh 2>/dev/null

./scripts/setup-mac.sh "$@"
status=$?

echo
if [ "$status" -eq 0 ]; then
  echo "✅ 完了しました。Xcode が開いています。"
else
  echo "❌ 途中で止まりました（終了コード $status）。上のメッセージの最後の20行ほどをコピーして Claude に送ってください。"
fi
echo
read -r -p "Enter キーを押すとこのウィンドウを閉じます…" _ || true
exit "$status"

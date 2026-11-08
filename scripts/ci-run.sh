#!/usr/bin/env bash
# CI 用: コマンドを実行してログを保存し、失敗したらログ末尾を GitHub のエラー注釈として出力する。
# 使い方: scripts/ci-run.sh <logfile> <command...>
set -uo pipefail
log="$1"
shift
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  tail -n 80 "$log" > "$log.tail"
  "$(dirname "$0")/ci-annotate.sh" "$*" "$log.tail"
fi
exit "$status"

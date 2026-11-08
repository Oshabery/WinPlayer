#!/usr/bin/env bash
# ファイルの内容を1つの GitHub Actions エラー注釈として出力する（複数行対応）。
# 使い方: scripts/ci-annotate.sh <title> <file>
set -u
title="$1"
file="$2"
python3 - "$title" "$file" <<'EOF'
import sys
title, path = sys.argv[1], sys.argv[2]
text = open(path, errors="replace").read()[-60000:]
def esc(s, prop=False):
    s = s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if prop:
        s = s.replace(":", "%3A").replace(",", "%2C")
    return s
print(f"::error title={esc(title, True)}::{esc(text)}")
EOF

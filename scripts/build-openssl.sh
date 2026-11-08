#!/usr/bin/env bash
# OpenSSL 3 を iPadOS 実機 (arm64) / シミュレーター (arm64) 向けに静的ライブラリとしてビルドする。
# 出力: build/openssl/<sdk>/{include,lib}
set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
MIN_IOS="${MIN_IOS:-17.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/openssl"
SRC="$WORK/src/openssl-$OPENSSL_VERSION"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

mkdir -p "$WORK/src"
if [ ! -d "$SRC" ]; then
  echo "==> OpenSSL $OPENSSL_VERSION を取得"
  curl -fL "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
    -o "$WORK/src/openssl.tar.gz"
  tar -xzf "$WORK/src/openssl.tar.gz" -C "$WORK/src"
fi

build_one() {
  local sdk="$1" target="$2" minflag="$3"
  local prefix="$WORK/$sdk"
  if [ -f "$prefix/lib/libssl.a" ]; then
    echo "==> $sdk はビルド済み（スキップ）"
    return
  fi
  echo "==> OpenSSL を $sdk 向けにビルド ($target)"
  local bdir="$WORK/build-$sdk"
  rm -rf "$bdir" && mkdir -p "$bdir"
  (
    cd "$bdir"
    "$SRC/Configure" "$target" \
      no-shared no-tests no-apps no-docs no-module no-engine no-async \
      "$minflag" \
      --prefix="$prefix" --openssldir="$prefix/ssl" --libdir=lib
    make -j"$JOBS" build_libs
    make install_dev
  )
}

build_one iphoneos          ios64-xcrun                "-mios-version-min=$MIN_IOS"
build_one iphonesimulator   iossimulator-arm64-xcrun   "-mios-simulator-version-min=$MIN_IOS"

echo "==> 完了: $WORK/{iphoneos,iphonesimulator}"

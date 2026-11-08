#!/usr/bin/env bash
# FreeRDP 3 を iPadOS 実機 / シミュレーター向けに静的ビルドし、Xcode から使える形で Vendor/ に配置する。
#
# 前提: scripts/build-openssl.sh を先に実行済み、cmake と ninja がインストール済み (brew install cmake ninja)
#
# 出力:
#   Vendor/include/                     … freerdp/ winpr/ のヘッダー
#   Vendor/<sdk>/lib/libFreeRDPAll.a    … FreeRDP + WinPR + OpenSSL をまとめた静的ライブラリ
set -euo pipefail

FREERDP_VERSION="${FREERDP_VERSION:-3.10.3}"
MIN_IOS="${MIN_IOS:-17.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/freerdp"
SRC="$WORK/src/FreeRDP-$FREERDP_VERSION"
OPENSSL_DIR="$ROOT/build/openssl"
VENDOR="$ROOT/Vendor"

if [ ! -f "$OPENSSL_DIR/iphoneos/lib/libssl.a" ]; then
  echo "OpenSSL が見つかりません。先に scripts/build-openssl.sh を実行してください。" >&2
  exit 1
fi

mkdir -p "$WORK/src"
if [ ! -d "$SRC" ]; then
  echo "==> FreeRDP $FREERDP_VERSION を取得"
  git clone --depth 1 --branch "$FREERDP_VERSION" https://github.com/FreeRDP/FreeRDP.git "$SRC"
fi

build_one() {
  local sdk="$1"
  local prefix="$WORK/install-$sdk"
  local bdir="$WORK/build-$sdk"
  local ossl="$OPENSSL_DIR/$sdk"

  echo "==> FreeRDP を $sdk 向けにビルド"
  rm -rf "$bdir"
  cmake -S "$SRC" -B "$bdir" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_FIND_ROOT_PATH="$ossl" \
    -DOPENSSL_ROOT_DIR="$ossl" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_CLIENT_COMMON=ON \
    -DWITH_CLIENT=OFF \
    -DWITH_CLIENT_SDL=OFF \
    -DWITH_SERVER=OFF \
    -DWITH_SHADOW=OFF \
    -DWITH_PROXY=OFF \
    -DWITH_SAMPLE=OFF \
    -DWITH_PLATFORM_SERVER=OFF \
    -DWITH_WINPR_TOOLS=OFF \
    -DWITH_MANPAGES=OFF \
    -DWITH_X11=OFF \
    -DWITH_WAYLAND=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_SWSCALE=OFF \
    -DWITH_OPENH264=OFF \
    -DWITH_CUPS=OFF \
    -DWITH_PCSC=OFF \
    -DWITH_SMARTCARD_EMULATE=OFF \
    -DWITH_KRB5=OFF \
    -DWITH_FUSE=OFF \
    -DWITH_PULSE=OFF \
    -DWITH_ALSA=OFF \
    -DWITH_OSS=OFF \
    -DWITH_AAD=OFF \
    -DWITH_JSON_DISABLED=ON \
    -DWITH_INTERNAL_MD4=ON \
    -DWITH_INTERNAL_MD5=ON \
    -DWITH_INTERNAL_RC4=ON \
    -DBUILTIN_CHANNELS=ON \
    -DCHANNEL_URBDRC=OFF \
    -DCHANNEL_AUDIN=OFF \
    -DCHANNEL_TSMF=OFF \
    -DCHANNEL_PRINTER=OFF \
    -DCHANNEL_SMARTCARD=OFF
  cmake --build "$bdir"
  cmake --install "$bdir"

  echo "==> $sdk 用ライブラリを libFreeRDPAll.a にまとめる"
  local out="$VENDOR/$sdk/lib"
  rm -rf "$out" && mkdir -p "$out"
  # FreeRDP / WinPR / チャネル / OpenSSL の静的ライブラリを1つに結合
  find "$prefix/lib" -name '*.a' > "$WORK/libs-$sdk.txt"
  echo "$ossl/lib/libssl.a"    >> "$WORK/libs-$sdk.txt"
  echo "$ossl/lib/libcrypto.a" >> "$WORK/libs-$sdk.txt"
  xargs libtool -static -o "$out/libFreeRDPAll.a" < "$WORK/libs-$sdk.txt"
}

build_one iphoneos
build_one iphonesimulator

echo "==> ヘッダーを Vendor/include に配置"
rm -rf "$VENDOR/include" && mkdir -p "$VENDOR/include"
cp -R "$WORK/install-iphoneos/include/freerdp3/." "$VENDOR/include/"
cp -R "$WORK/install-iphoneos/include/winpr3/."   "$VENDOR/include/"

echo "==> 完了。次に 'xcodegen' を実行して DeskLink.xcodeproj を生成してください。"

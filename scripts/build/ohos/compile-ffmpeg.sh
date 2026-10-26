#!/usr/bin/env bash
#
# Cross-compiles the vendored FFmpeg (extra/ffmpeg-ijk8) for OpenHarmony.
#
# Usage:
#   OHOS_SDK=/path/to/openharmony/sdk/native ./scripts/build/ohos/compile-ffmpeg.sh [arm64|x86_64]
#
set -euo pipefail

FF_ARCH=$1
if [ -z "${FF_ARCH}" ]; then
    echo "Usage: OHOS_SDK=... compile-ffmpeg.sh arm64|x86_64"
    exit 1
fi

if [ -z "${OHOS_SDK:-}" ]; then
    echo "OHOS_SDK must point at the OpenHarmony native SDK (the directory containing llvm/ and sysroot/)."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
SOURCE_DIR="$REPO_DIR/extra/ffmpeg-ijk8"
OUTPUT_DIR="$REPO_DIR/build/ohos/deps/output-$FF_ARCH"
BUILD_DIR="$REPO_DIR/build/ohos/deps/build-$FF_ARCH"

case "$FF_ARCH" in
    arm64)
        FF_TARGET_ARCH=aarch64
        ;;
    x86_64)
        FF_TARGET_ARCH=x86_64
        ;;
    *)
        echo "Unsupported architecture: $FF_ARCH"
        exit 1
        ;;
esac

if [ ! -d "$SOURCE_DIR" ]; then
    echo "FFmpeg source not found at $SOURCE_DIR"
    echo "Run scripts/init/init-config.sh (or init-android.sh) to populate extra/ffmpeg-ijk8 first."
    exit 1
fi

FF_SOURCE_DIR="$SOURCE_DIR"
if [ -f "$SOURCE_DIR/config.h" ] || [ -d "$SOURCE_DIR/ffbuild" ]; then
    FF_SOURCE_DIR="$REPO_DIR/build/ohos/deps/src-$FF_ARCH"
    rm -rf "$FF_SOURCE_DIR"
    mkdir -p "$FF_SOURCE_DIR"
    rsync -a \
        --exclude='.git' \
        --exclude='config.h' \
        --exclude='config.mak' \
        --exclude='ffbuild/config.*' \
        --exclude='*.o' \
        --exclude='*.a' \
        --exclude='*.so' \
        --exclude='*.so.*' \
        --exclude='libavutil/avconfig.h' \
        --exclude='libavutil/ffversion.h' \
        "$SOURCE_DIR/" "$FF_SOURCE_DIR/"
fi

TOOLCHAIN_DIR="$OHOS_SDK/llvm"
SYSROOT_DIR="$OHOS_SDK/sysroot"
TARGET_TRIPLE="${FF_TARGET_ARCH}-linux-ohos"

if [ ! -x "$TOOLCHAIN_DIR/bin/clang" ]; then
    echo "clang not found under $TOOLCHAIN_DIR"
    exit 1
fi

# shellcheck disable=SC1091
. "$REPO_DIR/config/module.sh"

CFLAGS="--target=${TARGET_TRIPLE} --sysroot=${SYSROOT_DIR} -DPIC -fPIC"
LDFLAGS="--target=${TARGET_TRIPLE} --sysroot=${SYSROOT_DIR} -fPIC -L${SYSROOT_DIR}/usr/lib/${TARGET_TRIPLE}"

# https/tls need a TLS backend; OpenSSL (compile-openssl.sh) provides it.
OPENSSL_DIR="$REPO_DIR/build/ohos/deps/output-openssl-$FF_ARCH"
TLS_CFG_FLAGS=
if [ -f "$OPENSSL_DIR/lib/libssl.a" ] && [ -f "$OPENSSL_DIR/lib/libcrypto.a" ]; then
    CFLAGS="$CFLAGS -I$OPENSSL_DIR/include"
    LDFLAGS="$LDFLAGS -L$OPENSSL_DIR/lib -ldl -lpthread"
    TLS_CFG_FLAGS="--enable-openssl --enable-protocol=https --enable-protocol=tls"
    echo "Enabling https/tls with OpenSSL at $OPENSSL_DIR"
else
    echo "OpenSSL not found at $OPENSSL_DIR; building without https/tls"
fi

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$BUILD_DIR"
"$FF_SOURCE_DIR/configure" \
    --prefix="$OUTPUT_DIR" \
    --enable-cross-compile \
    --target-os=linux \
    --arch="$FF_TARGET_ARCH" \
    --cc="$TOOLCHAIN_DIR/bin/clang" \
    --cxx="$TOOLCHAIN_DIR/bin/clang++" \
    --ar="$TOOLCHAIN_DIR/bin/llvm-ar" \
    --ranlib="$TOOLCHAIN_DIR/bin/llvm-ranlib" \
    --strip="$TOOLCHAIN_DIR/bin/llvm-strip" \
    --nm="$TOOLCHAIN_DIR/bin/llvm-nm" \
    --extra-cflags="$CFLAGS" \
    --extra-cxxflags="$CFLAGS" \
    --extra-ldflags="$LDFLAGS" \
    --enable-pic \
    --disable-symver \
    --disable-vulkan \
    $TLS_CFG_FLAGS \
    $COMMON_FF_CFG_FLAGS

make -j"$(sysctl -n hw.ncpu)"
make install

mkdir -p "$OUTPUT_DIR/include/libffmpeg"
cp "$BUILD_DIR/config.h" "$OUTPUT_DIR/include/libffmpeg/config.h"
for extra_header in application.h dns_cache.h thread.h; do
    cp "$SOURCE_DIR/libavutil/$extra_header" "$OUTPUT_DIR/include/libavutil/$extra_header"
done
for extra_header in avc.h demux.h hevc.h url.h; do
    cp "$SOURCE_DIR/libavformat/$extra_header" "$OUTPUT_DIR/include/libavformat/$extra_header"
done
for extra_header in get_bits.h h2645_parse.h mathops.h vlc.h; do
    cp "$SOURCE_DIR/libavcodec/$extra_header" "$OUTPUT_DIR/include/libavcodec/$extra_header"
done

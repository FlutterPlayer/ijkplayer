#!/usr/bin/env bash
#
# Cross-compiles OpenSSL for OpenHarmony so ijkplayer's FFmpeg can enable the
# https/tls protocols on HarmonyOS.
#
# Usage:
#   OHOS_SDK=/path/to/openharmony/native ./scripts/build/ohos/compile-openssl.sh [arm64|x86_64]
#
# The source tarball is expected at build/ohos/deps/openssl-<version>.tar.gz
# (OpenSSL 1.0.2 in extra/openssl is too old for FFmpeg 8's tls_openssl.c).
set -euo pipefail

NCPU="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

FF_ARCH=${1:-arm64}
OPENSSL_VERSION=${OPENSSL_VERSION:-3.0.15}

if [ -z "${OHOS_SDK:-}" ]; then
    echo "OHOS_SDK must point at the OpenHarmony native SDK (the directory containing llvm/ and sysroot/)."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
DEPS_DIR="$REPO_DIR/build/ohos/deps"
TARBALL="$DEPS_DIR/openssl-$OPENSSL_VERSION.tar.gz"
SOURCE_DIR="$DEPS_DIR/src-openssl-$OPENSSL_VERSION"
OUTPUT_DIR="$DEPS_DIR/output-openssl-$FF_ARCH"

TOOLCHAIN_DIR="$OHOS_SDK/llvm"
SYSROOT_DIR="$OHOS_SDK/sysroot"

case "$FF_ARCH" in
    arm64) TARGET_TRIPLE=aarch64-linux-ohos ;;
    x86_64) TARGET_TRIPLE=x86_64-linux-ohos ;;
    *) echo "Unsupported architecture: $FF_ARCH"; exit 1 ;;
esac

if [ ! -f "$TARBALL" ]; then
    echo "OpenSSL source not found at $TARBALL"
    echo "Download it with:"
    echo "  curl -L -o $TARBALL https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
    exit 1
fi

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
tar xzf "$TARBALL" -C "$SOURCE_DIR" --strip-components=1

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export CC="clang --target=$TARGET_TRIPLE --sysroot=$SYSROOT_DIR"
export CXX="clang++ --target=$TARGET_TRIPLE --sysroot=$SYSROOT_DIR"
export AR=llvm-ar
export RANLIB=llvm-ranlib
export NM=llvm-nm

cd "$SOURCE_DIR"
./Configure linux-aarch64 \
    --prefix="$OUTPUT_DIR" \
    --openssldir="$OUTPUT_DIR/ssl" \
    no-shared \
    no-tests \
    no-async \
    no-legacy \
    -fPIC

make -j"$NCPU"
make install_sw

echo "OpenSSL installed to $OUTPUT_DIR"
ls -l "$OUTPUT_DIR/lib" | head

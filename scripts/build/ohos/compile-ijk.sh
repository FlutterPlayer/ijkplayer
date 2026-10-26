#!/usr/bin/env bash
#
# Builds the OpenHarmony native libraries and the NAPI bridge.
#
# Usage:
#   OHOS_SDK=/path/to/openharmony/sdk/native ./scripts/build/ohos/compile-ijk.sh [arm64|x86_64]
#
set -euo pipefail

FF_ARCH=$1
if [ -z "${FF_ARCH}" ]; then
    echo "Usage: OHOS_SDK=... compile-ijk.sh arm64|x86_64"
    exit 1
fi

if [ -z "${OHOS_SDK:-}" ]; then
    echo "OHOS_SDK must point at the OpenHarmony native SDK (the directory containing llvm/ and sysroot/)."
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"

case "$FF_ARCH" in
    arm64)
        OHOS_ABI=arm64-v8a
        ;;
    x86_64)
        OHOS_ABI=x86_64
        ;;
    *)
        echo "Unsupported architecture: $FF_ARCH"
        exit 1
        ;;
esac

TOOLCHAIN_FILE="$OHOS_SDK/build/cmake/ohos.toolchain.cmake"
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "CMake toolchain not found at $TOOLCHAIN_FILE"
    exit 1
fi

BUILD_DIR="$REPO_DIR/build/ohos/cmake-$FF_ARCH"

cmake -S "$REPO_DIR/platform/ohos/src/main/cpp" \
    -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DOHOS_ARCH="$OHOS_ABI" \
    -DOHOS_PLATFORM=OHOS \
    -DOHOS_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DIJK_FFMPEG_ROOT="$REPO_DIR/build/ohos/deps/output-$FF_ARCH"

cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"

#!/usr/bin/env bash
#
# Copyright (C) 2013-2014 Bilibili
# Copyright (C) 2013-2014 Zhang Rui <bbcallen@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Builds the native libraries with CMake (the same CMakeLists.txt that the
# Gradle/AAR build uses), replacing the former ndk-build/Android.mk path.
#
# Usage:
#   compile-ijk.sh [arm64|x86|x86_64]      # default: arm64
#   compile-ijk.sh all32|all64|all
#   compile-ijk.sh clean
#   compile-ijk.sh <abi> clean|rebuild
#
# Output: android/build/<target>/lib/libijkplayer.so
#         FFmpeg and ijksdl are linked into this single library.
#         (stripped; unstripped copies stay in the CMake tree)
#

set -e

if [ -z "$ANDROID_NDK" ]; then
    echo "You must define ANDROID_NDK before starting."
    echo "They must point to your NDK and SDK directories."
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)

SRC_DIR=$REPO_DIR/platform/android/library/src/main/cpp
BUILD_ROOT=${IJK_BUILD_ROOT:-$REPO_DIR/build/android}
CMAKE_BUILD_TYPE=${IJK_BUILD_TYPE:-Release}
ANDROID_STL=${IJK_CXX_STL:-c++_static}
ANDROID_PLATFORM=${IJK_ANDROID_PLATFORM:-android-28}

ACT_ABI_32="x86"
ACT_ABI_64="arm64 x86 x86_64"
ACT_ABI_ALL=$ACT_ABI_64

UNAME_S=$(uname -s)
if which nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
elif [ "$UNAME_S" = "Darwin" ]; then
    JOBS=$(sysctl -n machdep.cpu.thread_count)
else
    JOBS=4
fi

TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "NDK CMake toolchain not found: $TOOLCHAIN_FILE"
    echo "ANDROID_NDK=$ANDROID_NDK"
    exit 1
fi

abi_of () {
    case "$1" in
        arm64)   echo "arm64-v8a" ;;
        x86)     echo "x86" ;;
        x86_64)  echo "x86_64" ;;
        *)       return 1 ;;
    esac
}

cmake_supports_source_dir_flag () {
    ver=$(cmake --version | head -1 | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')
    major=${ver% *}
    minor=${ver#* }
    [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 13 ]; }
}

llvm_strip () {
    for c in "$ANDROID_NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

do_clean () {
    echo "==> clean native build dirs under $BUILD_ROOT (keep deps/)"
    find "$BUILD_ROOT" -maxdepth 1 -mindepth 1 ! -name deps -exec rm -rf {} +
}

configure_abi () {
    PARAM_TARGET=$1
    PARAM_ABI=$(abi_of "$PARAM_TARGET")
    PARAM_BUILD_DIR=$BUILD_ROOT/$PARAM_TARGET
    PARAM_OUT_DIR=$PARAM_BUILD_DIR/lib

    CONTRIB_BUILD=$REPO_DIR/build/android/deps/output-$PARAM_TARGET
    if [ ! -f "$CONTRIB_BUILD/lib/libavformat.a" ] || [ ! -f "$CONTRIB_BUILD/lib/libavcodec.a" ]; then
        echo "error: no prebuilt FFmpeg static libraries for $PARAM_TARGET: $CONTRIB_BUILD/lib/libavformat.a"
        echo "       build it first: ./compile-ffmpeg.sh $PARAM_TARGET"
        exit 1
    fi

    echo "==> configure $PARAM_TARGET ($PARAM_ABI)"
    mkdir -p "$PARAM_BUILD_DIR"
    if cmake_supports_source_dir_flag; then
        cmake -S "$SRC_DIR" -B "$PARAM_BUILD_DIR" \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
            -DANDROID_ABI="$PARAM_ABI" \
            -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
            -DANDROID_STL="$ANDROID_STL" \
            -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
            -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$PARAM_OUT_DIR"
    else
        (cd "$PARAM_BUILD_DIR" && cmake "$SRC_DIR" \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
            -DANDROID_ABI="$PARAM_ABI" \
            -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
            -DANDROID_STL="$ANDROID_STL" \
            -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
            -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$PARAM_OUT_DIR")
    fi
}

build_abi () {
    PARAM_TARGET=$1
    PARAM_ABI=$(abi_of "$PARAM_TARGET")
    PARAM_BUILD_DIR=$BUILD_ROOT/$PARAM_TARGET
    PARAM_OUT_DIR=$PARAM_BUILD_DIR/lib

    configure_abi "$PARAM_TARGET"

    echo "==> build $PARAM_TARGET ($PARAM_ABI) -j$JOBS"
    cmake --build "$PARAM_BUILD_DIR" -j "$JOBS"

    STRIP=$(llvm_strip || true)
    if [ -n "$STRIP" ]; then
        "$STRIP" --strip-unneeded "$PARAM_OUT_DIR/libijkplayer.so"
    else
        echo "warning: llvm-strip not found under $ANDROID_NDK, leaving libraries unstripped"
    fi

    echo "==> $PARAM_TARGET done:"
    ls -l "$PARAM_OUT_DIR"/*.so
}

do_ndk_build () {
    PARAM_TARGET=$1
    PARAM_SUB_CMD=$2
    case "$PARAM_TARGET" in
        arm64|x86|x86_64) ;;
        *) return 0 ;;
    esac

    case "$PARAM_SUB_CMD" in
        clean)
            rm -rf "$BUILD_ROOT/$PARAM_TARGET"
            echo "==> clean $PARAM_TARGET"
        ;;
        rebuild)
            rm -rf "$BUILD_ROOT/$PARAM_TARGET"
            build_abi "$PARAM_TARGET"
        ;;
        *)
            build_abi "$PARAM_TARGET"
        ;;
    esac
}

cd "$REPO_DIR"

case "$1" in
    "")
        do_ndk_build arm64
    ;;
    arm64|x86|x86_64)
        do_ndk_build "$1" "$2"
    ;;
    all32)
        for ABI in $ACT_ABI_32; do do_ndk_build "$ABI" "$2"; done
    ;;
    all|all64)
        for ABI in $ACT_ABI_64; do do_ndk_build "$ABI" "$2"; done
    ;;
    clean)
        do_clean
    ;;
    *)
        echo "Usage:"
        echo "  compile-ijk.sh arm64|x86|x86_64 [clean|rebuild]"
        echo "  compile-ijk.sh all|all32|all64"
        echo "  compile-ijk.sh clean"
        exit 1
    ;;
esac

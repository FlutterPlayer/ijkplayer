#!/usr/bin/env bash
#
# Copyright (C) 2013-2014 Bilibili
# Copyright (C) 2013-2014 Zhang Rui <bbcallen@gmail.com>
# Copyright (C) 2018-2019 Befovy <befovy@gmail.com>
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

#----------
# modify for your build tool

FF_ALL_ARCHS="x86_64 arm64"

#----------
UNI_TMP="$UNI_BUILD_ROOT/tmp"
UNI_TMP_LLVM_VER_FILE="$UNI_TMP/llvm.ver.txt"
FF_TARGET=$1
FF_TARGET_EXTRA=$2
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$REPO_DIR/platform/macos"
UNI_BUILD_ROOT="$REPO_DIR/build/macos"

#----------
echo_archs() {
    echo "===================="
    echo "[*] check xcode version"
    echo "===================="
    echo "FF_ALL_ARCHS = $FF_ALL_ARCHS"
}

FF_LIBS="libcompat libavcodec libavfilter libavformat libavutil libswscale libswresample"

# 生成 Xcode / desktop 使用的 universal 产物
UNI_OUT="$UNI_BUILD_ROOT/ffmpeg-universal/output"
LIPO_LIBS="libavcodec libavfilter libavformat libavutil libswscale libswresample"

do_lipo_all() {
    mkdir -p "$UNI_OUT/lib"
    for lib in $LIPO_LIBS; do
        A="$UNI_BUILD_ROOT/ffmpeg-arm64/output/lib/$lib.a"
        B="$UNI_BUILD_ROOT/ffmpeg-x86_64/output/lib/$lib.a"
        if [ -f "$A" ] && [ -f "$B" ]; then
            xcrun lipo -create "$A" "$B" -output "$UNI_OUT/lib/$lib.a"
        elif [ -f "$A" ]; then
            cp -f "$A" "$UNI_OUT/lib/$lib.a"
        fi
    done
    rm -rf "$UNI_OUT/include"
    mkdir -p "$UNI_OUT/include"
    if [ -d "$UNI_BUILD_ROOT/ffmpeg-arm64/output/include" ]; then
        cp -R "$UNI_BUILD_ROOT/ffmpeg-arm64/output/include/"* "$UNI_OUT/include/"
    fi
    cp -f "$REPO_DIR/platform/ios/tools/application.h" "$UNI_OUT/include/libavutil/application.h"
    cp -f "$REPO_DIR/platform/macos/contrib/ffmpeg-arm64/libavformat/url.h" "$UNI_OUT/include/libavformat/url.h"
    cp -f "$REPO_DIR/platform/macos/contrib/ffmpeg-arm64/libavformat/demux.h" "$UNI_OUT/include/libavformat/demux.h"
    cp -f "$REPO_DIR/platform/macos/contrib/ffmpeg-arm64/libavutil/thread.h" "$UNI_OUT/include/libavutil/thread.h"
    xcrun lipo -info "$UNI_OUT/lib/libavcodec.a" 2>/dev/null || true
}



#----------
if [ "$FF_TARGET" = "x86_64" -o "$FF_TARGET" = "arm64" ]; then
    echo_archs
    sh "$SCRIPT_DIR/tools/do-compile-ffmpeg.sh" $FF_TARGET $FF_TARGET_EXTRA
    do_lipo_all
elif [ "$FF_TARGET" = "all" ]; then
    echo_archs
    for ARCH in $FF_ALL_ARCHS
    do
        sh "$SCRIPT_DIR/tools/do-compile-ffmpeg.sh" $ARCH $FF_TARGET_EXTRA
    done
    do_lipo_all
elif [ "$FF_TARGET" = "lipo" ]; then
    do_lipo_all
elif [ "$FF_TARGET" = "check" ]; then
    echo_archs
elif [ "$FF_TARGET" = "clean" ]; then
    echo_archs
    echo "=================="
    for ARCH in $FF_ALL_ARCHS
    do
        echo "clean ffmpeg-$ARCH"
        echo "=================="
        cd contrib/ffmpeg-$ARCH && git clean -xdf && cd -
    done
    echo "clean build cache"
    echo "================="
    rm -rf "$UNI_BUILD_ROOT"/ffmpeg-*
    rm -rf "$UNI_BUILD_ROOT"/ffmpeg-universal
    rm -rf "$UNI_BUILD_ROOT"/openssl-*
    rm -rf "$UNI_BUILD_ROOT"/universal/include
    rm -rf "$UNI_BUILD_ROOT"/universal/lib
    echo "clean success"
else
    echo "Usage:"
    echo "  compile-ffmpeg.sh x86_64"
    echo "  compile-ffmpeg.sh all"
    echo "  compile-ffmpeg.sh clean"
    echo "  compile-ffmpeg.sh check"
    exit 1
fi

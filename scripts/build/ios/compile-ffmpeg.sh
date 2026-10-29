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

#----------
# modify for your build tool

FF_ALL_ARCHS_IOS6_SDK="armv7 armv7s i386"
FF_ALL_ARCHS_IOS7_SDK="armv7 armv7s arm64 i386 x86_64"
FF_ALL_ARCHS_IOS8_SDK="armv7 arm64 i386 x86_64"

# arm64：iPhoneX | iphone8 plus｜iPhone8｜ iPhone7| iphone7 plus | iphone6s plus｜iPhone6｜ iPhone6 plus｜iPhone5S | 　　　　iPad Air｜ iPad mini2(iPad mini with Retina Display)
# armv7s：iPhone5｜iPhone5C｜iPad4(iPad with Retina Display)
# armv7：iPhone4｜iPhone4S｜iPad｜iPad2｜iPad3｜iPad mini｜iPod Touch 3G｜iPod Touch4
# arm64 同时用于真机和 Apple Silicon 模拟器；模拟器使用独立后缀避免与真机静态库冲突
FF_ALL_ARCHS_IOS12_SDK="arm64 arm64-simulator"

FF_ALL_ARCHS=$FF_ALL_ARCHS_IOS12_SDK

#----------
UNI_TMP="$UNI_BUILD_ROOT/tmp"
UNI_TMP_LLVM_VER_FILE="$UNI_TMP/llvm.ver.txt"
FF_TARGET=$1
FF_TARGET_EXTRA=$2
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$REPO_DIR/platform/ios"
UNI_BUILD_ROOT="$REPO_DIR/build/ios"

#----------
echo_archs() {
    echo "===================="
    echo "[*] check xcode version"
    echo "===================="
    echo "FF_ALL_ARCHS = $FF_ALL_ARCHS"
}

FF_LIBS="libavcodec libavfilter libavformat libavutil libswscale libswresample"
arch_platform () {
    case "$1" in
        *-simulator|i386|x86_64) echo "iphonesimulator" ;;
        *) echo "iphoneos" ;;
    esac
}

do_lipo_ffmpeg () {
    LIB_FILE=$1
    for PLATFORM in iphoneos iphonesimulator
    do
        LIPO_FLAGS=
        for ARCH in $FF_ALL_ARCHS
        do
            if [ "$(arch_platform $ARCH)" != "$PLATFORM" ]; then
                continue
            fi
            ARCH_LIB_FILE="$UNI_BUILD_ROOT/ffmpeg-$ARCH/output/lib/$LIB_FILE"
            if [ -f "$ARCH_LIB_FILE" ]; then
                LIPO_FLAGS="$LIPO_FLAGS $ARCH_LIB_FILE"
            else
                echo "skip $LIB_FILE of $ARCH";
            fi
        done

        if [ "$LIPO_FLAGS" != "" ]; then
            mkdir -p "$UNI_BUILD_ROOT/$PLATFORM/lib"
            xcrun lipo -create $LIPO_FLAGS -output "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
            xcrun lipo -info "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
        fi
    done
}

SSL_LIBS="libcrypto libssl"
do_lipo_ssl () {
    LIB_FILE=$1
    for PLATFORM in iphoneos iphonesimulator
    do
        LIPO_FLAGS=
        for ARCH in $FF_ALL_ARCHS
        do
            if [ "$(arch_platform $ARCH)" != "$PLATFORM" ]; then
                continue
            fi
            ARCH_LIB_FILE="$UNI_BUILD_ROOT/openssl-$ARCH/output/lib/$LIB_FILE"
            if [ -f "$ARCH_LIB_FILE" ]; then
                LIPO_FLAGS="$LIPO_FLAGS $ARCH_LIB_FILE"
            else
                echo "skip $LIB_FILE of $ARCH";
            fi
        done

        if [ "$LIPO_FLAGS" != "" ]; then
            mkdir -p "$UNI_BUILD_ROOT/$PLATFORM/lib"
            xcrun lipo -create $LIPO_FLAGS -output "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
            xcrun lipo -info "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
        fi
    done
}

do_lipo_all () {
    mkdir -p $UNI_BUILD_ROOT/universal/lib
    echo "lipo archs: $FF_ALL_ARCHS"
    for FF_LIB in $FF_LIBS
    do
        do_lipo_ffmpeg "$FF_LIB.a";
    done

    ANY_ARCH=
    for ARCH in $FF_ALL_ARCHS
    do
        ARCH_INC_DIR="$UNI_BUILD_ROOT/ffmpeg-$ARCH/output/include"
        if [ -d "$ARCH_INC_DIR" ]; then
            if [ -z "$ANY_ARCH" ]; then
                ANY_ARCH=$ARCH
                cp -R "$ARCH_INC_DIR" "$UNI_BUILD_ROOT/universal/"
            fi

            UNI_INC_DIR="$UNI_BUILD_ROOT/universal/include"

            mkdir -p "$UNI_INC_DIR/libavutil/$ARCH"
            cp -f "$ARCH_INC_DIR/libavutil/avconfig.h"  "$UNI_INC_DIR/libavutil/$ARCH/avconfig.h"
            cp -f tools/avconfig.h                      "$UNI_INC_DIR/libavutil/avconfig.h"
            cp -f "$ARCH_INC_DIR/libavutil/ffversion.h" "$UNI_INC_DIR/libavutil/$ARCH/ffversion.h"
            cp -f tools/ffversion.h                     "$UNI_INC_DIR/libavutil/ffversion.h"
            mkdir -p "$UNI_INC_DIR/libffmpeg/$ARCH"
            cp -f "$ARCH_INC_DIR/libffmpeg/config.h"    "$UNI_INC_DIR/libffmpeg/$ARCH/config.h"
            cp -f tools/config.h                        "$UNI_INC_DIR/libffmpeg/config.h"
            cp -f "ffmpeg-$ARCH/libavformat/url.h"     "$UNI_INC_DIR/libavformat/url.h"
            cp -f tools/application.h                   "$UNI_INC_DIR/libavutil/application.h"
        fi
    done

    for SSL_LIB in $SSL_LIBS
    do
        do_lipo_ssl "$SSL_LIB.a";
    done
}

#----------
if [ "$FF_TARGET" = "armv7" -o "$FF_TARGET" = "armv7s" -o "$FF_TARGET" = "arm64" -o "$FF_TARGET" = "arm64-simulator" ]; then
    echo_archs
    sh "$SCRIPT_DIR/tools/do-compile-ffmpeg.sh" $FF_TARGET $FF_TARGET_EXTRA
    do_lipo_all
elif [ "$FF_TARGET" = "i386" -o "$FF_TARGET" = "x86_64" ]; then
    echo_archs
    sh "$SCRIPT_DIR/tools/do-compile-ffmpeg.sh" $FF_TARGET $FF_TARGET_EXTRA
    do_lipo_all
elif [ "$FF_TARGET" = "lipo" ]; then
    echo_archs
    do_lipo_all
elif [ "$FF_TARGET" = "all" ]; then
    echo_archs
    for ARCH in $FF_ALL_ARCHS
    do
        sh "$SCRIPT_DIR/tools/do-compile-ffmpeg.sh" $ARCH $FF_TARGET_EXTRA
    done

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
        cd ffmpeg-$ARCH && git clean -xdf && cd -
    done
    echo "clean build cache"
    echo "================="
    rm -rf "$UNI_BUILD_ROOT"/ffmpeg-*
    rm -rf "$UNI_BUILD_ROOT"/openssl-*
    rm -rf "$UNI_BUILD_ROOT"/universal/include
    rm -rf "$UNI_BUILD_ROOT"/universal/lib
    rm -rf "$UNI_BUILD_ROOT"/iphoneos/lib
    rm -rf "$UNI_BUILD_ROOT"/iphonesimulator/lib
    echo "clean success"
else
    echo "Usage:"
    echo "  compile-ffmpeg.sh armv7|arm64|arm64-simulator|i386|x86_64"
    echo "  compile-ffmpeg.sh armv7s (obselete)"
    echo "  compile-ffmpeg.sh lipo"
    echo "  compile-ffmpeg.sh all"
    echo "  compile-ffmpeg.sh clean"
    echo "  compile-ffmpeg.sh check"
    exit 1
fi

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
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
cd "$REPO_DIR/platform/ios"
UNI_BUILD_ROOT="$REPO_DIR/build/ios"

#----------
FF_LIBS="libssl libcrypto"

#----------
echo_archs() {
    echo "===================="
    echo "[*] check xcode version"
    echo "===================="
    echo "FF_ALL_ARCHS = $FF_ALL_ARCHS"
}

arch_platform () {
    case "$1" in
        *-simulator|i386|x86_64) echo "iphonesimulator" ;;
        *) echo "iphoneos" ;;
    esac
}

do_lipo () {
    LIB_FILE=$1
    for PLATFORM in iphoneos iphonesimulator
    do
        LIPO_FLAGS=
        for ARCH in $FF_ALL_ARCHS
        do
            if [ "$(arch_platform $ARCH)" != "$PLATFORM" ]; then
                continue
            fi
            LIPO_FLAGS="$LIPO_FLAGS $UNI_BUILD_ROOT/openssl-$ARCH/output/lib/$LIB_FILE"
        done

        if [ "$LIPO_FLAGS" != "" ]; then
            mkdir -p "$UNI_BUILD_ROOT/$PLATFORM/lib"
            xcrun lipo -create $LIPO_FLAGS -output "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
            xcrun lipo -info "$UNI_BUILD_ROOT/$PLATFORM/lib/$LIB_FILE"
        fi
    done
}

do_lipo_all () {
    echo "lipo archs: $FF_ALL_ARCHS"
    for FF_LIB in $FF_LIBS
    do
        do_lipo "$FF_LIB.a";
    done

    mkdir -p $UNI_BUILD_ROOT/universal
    cp -R $UNI_BUILD_ROOT/openssl-arm64/output/include $UNI_BUILD_ROOT/universal/
}

#----------
if [ "$FF_TARGET" = "armv7" -o "$FF_TARGET" = "armv7s" -o "$FF_TARGET" = "arm64" -o "$FF_TARGET" = "arm64-simulator" ]; then
    echo_archs
    sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $FF_TARGET
elif [ "$FF_TARGET" = "i386" -o "$FF_TARGET" = "x86_64" ]; then
    echo_archs
    sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $FF_TARGET
elif [ "$FF_TARGET" = "lipo" ]; then
    echo_archs
    do_lipo_all
elif [ "$FF_TARGET" = "all" ]; then
    echo_archs
    for ARCH in $FF_ALL_ARCHS
    do
        sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $ARCH
    done

    do_lipo_all
elif [ "$FF_TARGET" = "check" ]; then
    echo_archs
elif [ "$FF_TARGET" = "clean" ]; then
    echo_archs
    for ARCH in $FF_ALL_ARCHS
    do
        cd openssl-$ARCH 2>/dev/null && git clean -xdf && cd -
        rm -rf "$UNI_BUILD_ROOT"/openssl-$ARCH
    done
    rm -rf "$UNI_BUILD_ROOT"/openssl-*
    rm -rf "$UNI_BUILD_ROOT"/iphoneos/lib
    rm -rf "$UNI_BUILD_ROOT"/iphonesimulator/lib
else
    echo "Usage:"
    echo "  compile-openssl.sh armv7|arm64|arm64-simulator|i386|x86_64"
    echo "  compile-openssl.sh armv7s (obselete)"
    echo "  compile-openssl.sh lipo"
    echo "  compile-openssl.sh all"
    echo "  compile-openssl.sh clean"
    echo "  compile-openssl.sh check"
    exit 1
fi

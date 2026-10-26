#!/usr/bin/env bash
#
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

# This script is based on projects below
# https://github.com/yixia/FFmpeg-Android
# http://git.videolan.org/?p=vlc-ports/android.git;a=summary

#--------------------
echo "===================="
echo "[*] check env $1"
echo "===================="
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../../.." && pwd )"
OUTPUT_DIR="$REPO_DIR/build/android/deps"
FF_BUILD_ROOT="$REPO_DIR/platform/android/contrib"


#--------------------
# common defines
FF_ARCH=$1
FF_BUILD_OPT=$2
echo "FF_ARCH=$FF_ARCH"
echo "FF_BUILD_OPT=$FF_BUILD_OPT"
if [ -z "$FF_ARCH" ]; then
    echo "You must specific an architecture 'arm64, x86, ...'."
    echo ""
    exit 1
fi


FF_ANDROID_PLATFORM=
FF_TOOLCHAIN_ARCH=

FF_BUILD_NAME=
FF_SOURCE=
FF_CROSS_PREFIX=
FF_DEP_OPENSSL_INC=
FF_DEP_OPENSSL_LIB=

FF_DEP_LIBSOXR_INC=
FF_DEP_LIBSOXR_LIB=

FF_DEP_LIBSRT_INC=
FF_DEP_LIBSRT_LIB=

FF_CFG_FLAGS=

FF_EXTRA_CFLAGS=
FF_EXTRA_LDFLAGS=
FF_DEP_LIBS=

# FF_MODULE_DIRS="compat libavcodec libavfilter libavformat libavutil libswresample libswscale"
FF_MODULE_DIRS="compat libavdevice libavcodec libavfilter libavformat libavutil libswresample libswscale"
FF_ASSEMBLER_SUB_DIRS=


#--------------------
echo ""
echo "--------------------"
echo "[*] make NDK standalone toolchain"
echo "--------------------"
. "$SCRIPT_DIR/do-detect-env.sh"
FF_MAKE_TOOLCHAIN_FLAGS=$IJK_MAKE_TOOLCHAIN_FLAGS
FF_MAKE_FLAGS=$IJK_MAKE_FLAG
FF_GCC_VER=$IJK_GCC_VER
FF_GCC_64_VER=$IJK_GCC_64_VER


if [ "$FF_ARCH" = "x86" ]; then
    FF_TOOLCHAIN_ARCH=x86
    FF_ANDROID_PLATFORM=26

    FF_BUILD_NAME=ffmpeg-x86
    FF_BUILD_NAME_OPENSSL=openssl-x86
    FF_BUILD_NAME_LIBSOXR=libsoxr-x86
    FF_BUILD_NAME_LIBSRT=libsrt-x86
    FF_SOURCE=$FF_BUILD_ROOT/$FF_BUILD_NAME

    FF_CROSS_PREFIX=i686-linux-android
    FF_TOOLCHAIN_NAME=x86-${FF_GCC_VER}

    FF_CFG_FLAGS="$FF_CFG_FLAGS --arch=x86 --cpu=i686 --enable-x86asm"

    FF_EXTRA_CFLAGS="$FF_EXTRA_CFLAGS -march=atom -msse3 -ffast-math -mfpmath=sse"
    FF_EXTRA_LDFLAGS="$FF_EXTRA_LDFLAGS"

    FF_ASSEMBLER_SUB_DIRS="x86"

elif [ "$FF_ARCH" = "x86_64" ]; then
    FF_TOOLCHAIN_ARCH=x86_64
    FF_ANDROID_PLATFORM=26

    FF_BUILD_NAME=ffmpeg-x86_64
    FF_BUILD_NAME_OPENSSL=openssl-x86_64
    FF_BUILD_NAME_LIBSOXR=libsoxr-x86_64
    FF_BUILD_NAME_LIBSRT=libsrt-x86_64
    FF_SOURCE=$FF_BUILD_ROOT/$FF_BUILD_NAME

    FF_CROSS_PREFIX=x86_64-linux-android
    FF_TOOLCHAIN_NAME=${FF_CROSS_PREFIX}-${FF_GCC_64_VER}

    FF_CFG_FLAGS="$FF_CFG_FLAGS --arch=x86_64 --enable-x86asm"

    FF_EXTRA_CFLAGS="$FF_EXTRA_CFLAGS"
    FF_EXTRA_LDFLAGS="$FF_EXTRA_LDFLAGS"

    FF_ASSEMBLER_SUB_DIRS="x86"

elif [ "$FF_ARCH" = "arm64" ]; then
    FF_TOOLCHAIN_ARCH=arm64
    FF_ANDROID_PLATFORM=26

    FF_BUILD_NAME=ffmpeg-arm64
    FF_BUILD_NAME_OPENSSL=openssl-arm64
    FF_BUILD_NAME_LIBSOXR=libsoxr-arm64
    FF_BUILD_NAME_LIBSRT=libsrt-arm64
    FF_SOURCE=$FF_BUILD_ROOT/$FF_BUILD_NAME

    FF_CROSS_PREFIX=aarch64-linux-android
    FF_TOOLCHAIN_NAME=${FF_CROSS_PREFIX}-${FF_GCC_64_VER}

    FF_CFG_FLAGS="$FF_CFG_FLAGS --arch=aarch64"

    FF_EXTRA_CFLAGS="$FF_EXTRA_CFLAGS"
    FF_EXTRA_LDFLAGS="$FF_EXTRA_LDFLAGS"
    FF_ASSEMBLER_SUB_DIRS="aarch64 neon"

else
    echo "unknown architecture $FF_ARCH";
    exit 1
fi

if [ ! -d $FF_SOURCE ]; then
    echo ""
    echo "!! ERROR"
    echo "!! Can not find FFmpeg directory for $FF_BUILD_NAME"
    echo "!! Run 'sh init-android.sh' first"
    echo ""
    exit 1
fi

FF_TOOLCHAIN_PATH=$OUTPUT_DIR/toolchain-$FF_ARCH
FF_MAKE_TOOLCHAIN_FLAGS="$FF_MAKE_TOOLCHAIN_FLAGS --install-dir=$FF_TOOLCHAIN_PATH"

FF_SYSROOT=$FF_TOOLCHAIN_PATH/sysroot
FF_PREFIX=$OUTPUT_DIR/output-$FF_ARCH

FF_DEP_OPENSSL_INC=$FF_PREFIX/include
FF_DEP_OPENSSL_LIB=$FF_PREFIX/lib

FF_DEP_LIBSOXR_INC=$FF_PREFIX/include
FF_DEP_LIBSOXR_LIB=$FF_PREFIX/lib

FF_DEP_LIBSRT_INC=$FF_PREFIX/include
FF_DEP_LIBSRT_LIB=$FF_PREFIX/lib

case "$UNAME_S" in
    CYGWIN_NT-*)
        FF_SYSROOT="$(cygpath -am $FF_SYSROOT)"
        FF_PREFIX="$(cygpath -am $FF_PREFIX)"
    ;;
esac


mkdir -p $FF_PREFIX


FF_TOOLCHAIN_TOUCH="$FF_TOOLCHAIN_PATH/touch"
if [ ! -f "$FF_TOOLCHAIN_TOUCH" ]; then
    echo "FF_MAKE_TOOLCHAIN_FLAGS:$FF_MAKE_TOOLCHAIN_FLAGS"
    # $ANDROID_NDK/build/tools/make-standalone-toolchain.sh \
    #     $FF_MAKE_TOOLCHAIN_FLAGS \
    #     --platform=$FF_ANDROID_PLATFORM \
    #     --toolchain=$FF_TOOLCHAIN_NAME
    PYTHON=python3
    command -v python3 >/dev/null 2>&1 || PYTHON=python
    $PYTHON $ANDROID_NDK/build/tools/make_standalone_toolchain.py \
        --arch ${FF_TOOLCHAIN_ARCH} \
        --api ${FF_ANDROID_PLATFORM} \
        --stl libc++ \
        --install-dir ${FF_TOOLCHAIN_PATH}
    touch $FF_TOOLCHAIN_TOUCH;
fi


#--------------------
echo ""
echo "--------------------"
echo "[*] check ffmpeg env"
echo "--------------------"
echo "--------------------${FF_TOOLCHAIN_PATH}/bin"
echo "--------------------${FF_CROSS_PREFIX}"
export PATH=$FF_TOOLCHAIN_PATH/bin/:$PATH
#export CC="ccache ${FF_CROSS_PREFIX}-gcc"
export AS=${FF_CROSS_PREFIX}-clang
export CC=${FF_CROSS_PREFIX}-clang
export CXX=${FF_CROSS_PREFIX}-clang++
export LD=${FF_CROSS_PREFIX}-ld
export AR=${FF_CROSS_PREFIX}-ar
export RANLIB=${FF_CROSS_PREFIX}-ranlib
export STRIP=${FF_CROSS_PREFIX}-strip
export SYSROOT=${FF_SYSROOT}
export CROSS_PREFIX=${FF_CROSS_PREFIX}

FF_CFLAGS="-O3 -Wall -pipe \
    -std=c99 \
    -fPIE -fPIC \
    -ffast-math \
    -fstrict-aliasing -Werror=strict-aliasing \
    -Wa,--noexecstack \
    -DANDROID -DNDEBUG"

FF_CFG_FLAGS="$FF_CFG_FLAGS --as=${FF_CROSS_PREFIX}-clang"
FF_CFG_FLAGS="$FF_CFG_FLAGS --cc=${FF_CROSS_PREFIX}-clang"
FF_CFG_FLAGS="$FF_CFG_FLAGS --cxx=${FF_CROSS_PREFIX}-clang++"
# NDK r23+ ships binutils as llvm-* only (no ${cross_prefix}nm/ar/ranlib/strip wrappers).
FF_CFG_FLAGS="$FF_CFG_FLAGS --nm=llvm-nm"
FF_CFG_FLAGS="$FF_CFG_FLAGS --ar=llvm-ar"
FF_CFG_FLAGS="$FF_CFG_FLAGS --ranlib=llvm-ranlib"
FF_CFG_FLAGS="$FF_CFG_FLAGS --strip=llvm-strip"
# FF_CFG_FLAGS="$FF_CFG_FLAGS --ld=${FF_CROSS_PREFIX}-ld"
# FF_CFG_FLAGS="$FF_CFG_FLAGS --ar=${FF_CROSS_PREFIX}-ar"
# FF_CFG_FLAGS="$FF_CFG_FLAGS --cxx=${FF_CROSS_PREFIX}-clang++"
# cause av_strlcpy crash with gcc4.7, gcc4.8
# -fmodulo-sched -fmodulo-sched-allow-regmoves

# --enable-thumb is OK
#FF_CFLAGS="$FF_CFLAGS -mthumb"

# not necessary
#FF_CFLAGS="$FF_CFLAGS -finline-limit=300"

export COMMON_FF_CFG_FLAGS=
. $FF_BUILD_ROOT/../../../config/module.sh

export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-jni"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-mediacodec"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-decoder=h264_mediacodec"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-decoder=hevc_mediacodec"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-decoder=mpeg2_mediacodec"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-decoder=mpeg4_mediacodec"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-bsf=h264_mp4toannexb"
export COMMON_FF_CFG_FLAGS="$COMMON_FF_CFG_FLAGS --enable-bsf=hevc_mp4toannexb"

#--------------------
# with openssl
if [ -f "${FF_DEP_OPENSSL_LIB}/libssl.a" ]; then
    echo "OpenSSL detected"
    # FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-nonfree"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-openssl"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-protocol=crypto"
    echo "${FF_DEP_OPENSSL_INC} ${FF_DEP_OPENSSL_LIB}"
    FF_CFLAGS="$FF_CFLAGS -I${FF_DEP_OPENSSL_INC}"
    # BoringSSL/OpenSSL 若为 C++ 实现（BoringSSL）需要 libc++
    FF_DEP_LIBS="$FF_DEP_LIBS -L${FF_DEP_OPENSSL_LIB} -lssl -lcrypto -lc++"
fi

if [ -f "${FF_DEP_LIBSOXR_LIB}/libsoxr.a" ]; then
    echo "libsoxr detected"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-libsoxr"

    FF_CFLAGS="$FF_CFLAGS -I${FF_DEP_LIBSOXR_INC}"
    FF_DEP_LIBS="$FF_DEP_LIBS -L${FF_DEP_LIBSOXR_LIB} -lsoxr"
fi

if [ -f "${FF_DEP_LIBSRT_LIB}/libsrt.a" ]; then
    echo "libsrt detected"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-libsrt"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-protocol=libsrt"

    FF_CFLAGS="$FF_CFLAGS -I${FF_DEP_LIBSRT_INC}"
    FF_DEP_LIBS="$FF_DEP_LIBS -L${FF_DEP_LIBSRT_LIB} -lsrt -lc -lm -ldl -lcrypto -lssl -lstdc++"
fi

export PKG_CONFIG_PATH="${FF_PREFIX}/lib/pkgconfig"

FF_CFG_FLAGS="$FF_CFG_FLAGS --pkgconfigdir=${FF_PREFIX}/lib/pkgconfig"

FF_CFG_FLAGS="$FF_CFG_FLAGS $COMMON_FF_CFG_FLAGS"

#--------------------
# Standard options:
FF_CFG_FLAGS="$FF_CFG_FLAGS --prefix=$FF_PREFIX"

# Advanced options (experts only):
FF_CFG_FLAGS="$FF_CFG_FLAGS --cross-prefix=${FF_CROSS_PREFIX}-"
FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-cross-compile"
FF_CFG_FLAGS="$FF_CFG_FLAGS --target-os=android"
FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-pic"
FF_CFG_FLAGS="$FF_CFG_FLAGS --pkg-config=pkg-config"
# FF_CFG_FLAGS="$FF_CFG_FLAGS --disable-symver"
FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-static"
FF_CFG_FLAGS="$FF_CFG_FLAGS --disable-shared"

if [ "$FF_ARCH" = "x86" ]; then
    FF_CFG_FLAGS="$FF_CFG_FLAGS --disable-asm"
else
    # Optimization options (experts only):
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-asm"
    FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-inline-asm"
fi

case "$FF_BUILD_OPT" in
    debug)
        FF_CFG_FLAGS="$FF_CFG_FLAGS --disable-optimizations"
        FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-debug"
        FF_CFG_FLAGS="$FF_CFG_FLAGS --disable-small"
    ;;
    *)
        FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-optimizations"
        FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-debug"
        FF_CFG_FLAGS="$FF_CFG_FLAGS --enable-small"
    ;;
esac

#--------------------
echo ""
echo "--------------------"
echo "[*] configurate ffmpeg"
echo "--------------------"
cd $FF_SOURCE
if [ -f "./config.h" ]; then
    echo 'reuse configure'
else
    which $CC
    ./configure $FF_CFG_FLAGS \
        --extra-cflags="$FF_CFLAGS $FF_EXTRA_CFLAGS" \
        --extra-ldflags="$FF_DEP_LIBS $FF_EXTRA_LDFLAGS"
    make clean
fi

#--------------------
echo ""
echo "--------------------"
echo "[*] compile ffmpeg"
echo "--------------------"
cp config.* $FF_PREFIX
make $FF_MAKE_FLAGS > /dev/null
make install
mkdir -p $FF_PREFIX/include/libffmpeg
cp -f config.h $FF_PREFIX/include/libffmpeg/config.h

#--------------------
echo ""
echo "--------------------"
echo "[*] link ffmpeg"
echo "--------------------"
echo $FF_EXTRA_LDFLAGS

FF_C_OBJ_FILES=
for MODULE_DIR in $FF_MODULE_DIRS
do
    MODULE_OBJ_FILES=$(find "$MODULE_DIR" -name '*.o' -not -path '*/tests/*' 2>/dev/null)
    if [ -n "$MODULE_OBJ_FILES" ]; then
        echo "link $MODULE_DIR (recursive *.o)"
        FF_C_OBJ_FILES="$FF_C_OBJ_FILES $MODULE_OBJ_FILES"
    fi
done

echo "link FF_DEP_LIBS:$FF_DEP_LIBS"
echo "link FF_EXTRA_LDFLAGS:$FF_EXTRA_LDFLAGS"
$CC -lm -lz -lmediandk -landroid -llog -shared -Wl,-Bsymbolic --sysroot=$FF_SYSROOT -Wl,--no-undefined -Wl,-z,noexecstack $FF_EXTRA_LDFLAGS \
    -Wl,-soname,libijkffmpeg.so \
    $FF_C_OBJ_FILES \
    $FF_DEP_LIBS \
    -o $FF_PREFIX/libijkffmpeg.so

mysedi() {
    f=$1
    exp=$2
    n=`basename $f`
    cp $f /tmp/$n
    sed $exp /tmp/$n > $f
    rm /tmp/$n
}

echo ""
echo "--------------------"
echo "[*] create files for shared ffmpeg"
echo "--------------------"
rm -rf $FF_PREFIX/shared
mkdir -p $FF_PREFIX/shared/lib/pkgconfig
ln -s $FF_PREFIX/include $FF_PREFIX/shared/include
ln -s $FF_PREFIX/libijkffmpeg.so $FF_PREFIX/shared/lib/libijkffmpeg.so
cp $FF_PREFIX/lib/pkgconfig/*.pc $FF_PREFIX/shared/lib/pkgconfig
for f in $FF_PREFIX/lib/pkgconfig/*.pc; do
    # in case empty dir
    if [ ! -f $f ]; then
        continue
    fi
    cp $f $FF_PREFIX/shared/lib/pkgconfig
    f=$FF_PREFIX/shared/lib/pkgconfig/`basename $f`
    # OSX sed doesn't have in-place(-i)
    mysedi $f 's/\/output/\/output\/shared/g'
    mysedi $f 's/-lavcodec/-lijkffmpeg/g'
    mysedi $f 's/-lavfilter/-lijkffmpeg/g'
    mysedi $f 's/-lavformat/-lijkffmpeg/g'
    mysedi $f 's/-lavutil/-lijkffmpeg/g'
    mysedi $f 's/-lswresample/-lijkffmpeg/g'
    mysedi $f 's/-lswscale/-lijkffmpeg/g'
done

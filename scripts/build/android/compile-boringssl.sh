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

#----------
FF_TARGET=$1
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/../../.." && pwd )"
OUTPUT_DIR="$REPO_DIR/build/android/deps"
UNI_BUILD_ROOT="$OUTPUT_DIR"
cd "$REPO_DIR/platform/android/contrib"
set +x

FF_ACT_ARCHS_32=""
FF_ACT_ARCHS_64="arm64"
FF_ACT_ARCHS_ALL="$FF_ACT_ARCHS_64 $FF_ACT_ARCHS_32"

. "$SCRIPT_DIR/tools/do-detect-env.sh"

echo_archs() {
    echo "===================="
    echo "[*] check archs"
    echo "===================="
    echo "FF_ALL_ARCHS = $FF_ACT_ARCHS_ALL"
    echo "FF_ACT_ARCHS = $*"
    echo ""
}

echo_usage() {
    echo "Usage:"
    echo "  compile-boringssl.sh arm64|x86|x86_64"
    echo "  compile-boringssl.sh all|all32"
    echo "  compile-boringssl.sh all64"
    echo "  compile-boringssl.sh clean"
    echo "  compile-boringssl.sh check"
    exit 1
}

echo_nextstep_help() {
    #----------
    echo ""
    echo "--------------------"
    echo "[*] Finished"
    echo "--------------------"
    echo "# to continue to build ffmpeg, run script below,"
    echo "sh compile-ffmpeg.sh "
    echo "# to continue to build ijkplayer, run script below,"
    echo "sh compile-ijk.sh "
}

do_build_boringssl() {
    
    echo "ARCH:$1"
    ARCH=$1
    API_LEVEL=
    FF_ARCH=
    if [ "$ARCH" = "x86" ]; then
        API_LEVEL=26
        FF_ARCH="x86"
    elif [ "$ARCH" = "x86_64" ]; then
        API_LEVEL=26
        FF_ARCH="x86_64"
    elif [ "$ARCH" = "arm64" ]; then
        API_LEVEL=26
        FF_ARCH="arm64-v8a"
    fi

    BORINGSSL_SRC_PATH=`pwd`/boringssl
    echo "BORINGSSL_SRC_PATH: $BORINGSSL_SRC_PATH"
    echo "FF_ARCH:${FF_ARCH}"
    echo "API_LEVEL:${API_LEVEL}"
    
    mkdir -p ""$OUTPUT_DIR"/boringssl-$ARCH"
    cmake \
        -B"$OUTPUT_DIR"/boringssl-$ARCH \
        -DANDROID_ABI=${FF_ARCH} \
        -DANDROID_NDK=${ANDROID_NDK} \
        -DANDROID_NATIVE_API_LEVEL=${API_LEVEL} \
        -DCMAKE_MAKE_PROGRAM=${ANDROID_HOME}/cmake/3.22.1/bin/ninja \
        -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DANDROID_STL=c++_static \
        -DANDROID_TOOLCHAIN=clang \
        -GNinja ${BORINGSSL_SRC_PATH}

    cmake --build "$OUTPUT_DIR"/boringssl-${ARCH}

    mkdir -p "$OUTPUT_DIR"/output-${ARCH}/lib
    # 新版 BoringSSL 输出到顶层，旧版在 ssl/ 与 crypto/ 下
    if [ -f "$OUTPUT_DIR"/boringssl-${ARCH}/ssl/libssl.a ]; then
        cp "$OUTPUT_DIR"/boringssl-${ARCH}/ssl/libssl.a "$OUTPUT_DIR"/output-${ARCH}/lib
        cp "$OUTPUT_DIR"/boringssl-${ARCH}/crypto/libcrypto.a "$OUTPUT_DIR"/output-${ARCH}/lib
    else
        cp "$OUTPUT_DIR"/boringssl-${ARCH}/libssl.a "$OUTPUT_DIR"/output-${ARCH}/lib
        cp "$OUTPUT_DIR"/boringssl-${ARCH}/libcrypto.a "$OUTPUT_DIR"/output-${ARCH}/lib
    fi

    # FFmpeg 8 需要 DTLS_get_data_mtu（BoringSSL 未提供），补一个兼容垫片
    case "$ARCH" in
        arm64)  CLANG_TARGET=aarch64-linux-android26 ;;
        x86)    CLANG_TARGET=i686-linux-android26 ;;
        x86_64) CLANG_TARGET=x86_64-linux-android26 ;;
    esac
    CLANG_BIN=$(ls -d ${ANDROID_NDK}/toolchains/llvm/prebuilt/*/bin | head -1)
    ${CLANG_BIN}/clang --target=${CLANG_TARGET} -O2 -fPIC \
        -I boringssl/include \
        -c ../boringssl-compat/boringssl_compat.c \
        -o "$OUTPUT_DIR"/boringssl-${ARCH}/boringssl_compat.o
    ${CLANG_BIN}/llvm-ar r "$OUTPUT_DIR"/output-${ARCH}/lib/libssl.a "$OUTPUT_DIR"/boringssl-${ARCH}/boringssl_compat.o

    mkdir -p "$OUTPUT_DIR"/output-${ARCH}/include
    cp -r boringssl/include/* "$OUTPUT_DIR"/output-${ARCH}/include

    # 让 FFmpeg 的 configure 能看到 DTLS_get_data_mtu 声明（BoringSSL 未提供）
    cat >> "$OUTPUT_DIR"/output-${ARCH}/include/openssl/ssl.h <<'EOF_HDR'

/* ijkplayer: BoringSSL compatibility - declared by boringssl_compat.c */
#ifdef __cplusplus
extern "C" {
#endif
OPENSSL_EXPORT size_t DTLS_get_data_mtu(const SSL *ssl);
OPENSSL_EXPORT void DTLS_set_link_mtu(SSL *ssl, size_t mtu);
#ifdef __cplusplus
}
#endif
EOF_HDR
}

#----------
case "$FF_TARGET" in
    "")
        echo_archs arm64
        do_build_boringssl arm64
    ;;
    arm64|x86|x86_64)
        echo_archs $FF_TARGET
        do_build_boringssl $FF_TARGET
        echo_nextstep_help
    ;;
    all32)
        echo_archs $FF_ACT_ARCHS_32
        for ARCH in $FF_ACT_ARCHS_32
        do
            do_build_boringssl $ARCH
        done
        echo_nextstep_help
    ;;
    all64)
        echo_archs $FF_ACT_ARCHS_64
        for ARCH in $FF_ACT_ARCHS_64
        do
            do_build_boringssl $ARCH
        done
        echo_nextstep_help
    ;;
    all)
        echo_archs $FF_ACT_ARCHS_ALL
        for ARCH in $FF_ACT_ARCHS_ALL
        do
            do_build_boringssl $ARCH
        done
        echo_nextstep_help
    ;;
    clean)
        echo_archs FF_ACT_ARCHS_ALL
        for ARCH in $FF_ACT_ARCHS_ALL
        do
            if [ -d boringssl ]; then
                cd boringssl && git clean -xdf && cd -
            fi
            if [ -d "$OUTPUT_DIR"/boringssl-$ARCH ]; then
                rm -rf "$OUTPUT_DIR"/boringssl-$ARCH
            fi
            rm -f "$OUTPUT_DIR"/output-$ARCH/lib/libssl.a
            rm -f "$OUTPUT_DIR"/output-$ARCH/lib/libcrypto.a
        done
        rm -rf "$OUTPUT_DIR"/boringssl-*
    ;;
    check)
        echo_archs FF_ACT_ARCHS_ALL
    ;;
    *)
        echo_usage
        exit 1
    ;;
esac

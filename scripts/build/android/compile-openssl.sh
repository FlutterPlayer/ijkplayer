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

FF_ACT_ARCHS_32="x86"
FF_ACT_ARCHS_64="arm64 x86 x86_64"
FF_ACT_ARCHS_ALL=$FF_ACT_ARCHS_64

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
    echo "  compile-openssl.sh arm64|x86|x86_64"
    echo "  compile-openssl.sh all|all32"
    echo "  compile-openssl.sh all64"
    echo "  compile-openssl.sh clean"
    echo "  compile-openssl.sh check"
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

#----------
case "$FF_TARGET" in
    "")
    ;;
    arm64|x86|x86_64)
        echo_archs $FF_TARGET
        sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $FF_TARGET
        echo_nextstep_help
    ;;
    all32)
        echo_archs $FF_ACT_ARCHS_32
        for ARCH in $FF_ACT_ARCHS_32
        do
            sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $ARCH
        done
        echo_nextstep_help
    ;;
    all|all64)
        echo_archs $FF_ACT_ARCHS_64
        for ARCH in $FF_ACT_ARCHS_64
        do
            sh "$SCRIPT_DIR/tools/do-compile-openssl.sh" $ARCH
        done
        echo_nextstep_help
    ;;
    clean)
        echo_archs FF_ACT_ARCHS_64
        for ARCH in $FF_ACT_ARCHS_ALL
        do
            if [ -d openssl-$ARCH ]; then
                cd openssl-$ARCH && git clean -xdf && cd -
            fi
            rm -rf "$OUTPUT_DIR"/openssl-$ARCH
            rm -f "$OUTPUT_DIR"/output-$ARCH/lib/libssl.a
            rm -f "$OUTPUT_DIR"/output-$ARCH/lib/libcrypto.a
        done
        rm -rf "$OUTPUT_DIR"/openssl-*
    ;;
    check)
        echo_archs FF_ACT_ARCHS_ALL
    ;;
    *)
        echo_usage
        exit 1
    ;;
esac

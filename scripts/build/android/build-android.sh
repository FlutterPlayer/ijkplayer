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
# Unattended build helper: FFmpeg (contrib) -> native libs (CMake) -> AAR.
# Both compile-ijk.sh and the AAR build use the same CMakeLists.txt.
#

set -e

if [ -z "$ANDROID_NDK" ]; then
    echo "You must define ANDROID_NDK before starting."
    echo "They must point to your NDK and SDK directories."
    exit 1
fi

REQUEST_TARGET=$1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)

ACT_ABI_32="x86"
ACT_ABI_64="arm64 x86 x86_64"

do_build_native() {
    PARAM_TARGET=$1

    echo "==> ffmpeg: $PARAM_TARGET"
    "$SCRIPT_DIR/compile-ffmpeg.sh" "$PARAM_TARGET"

    echo "==> native: $PARAM_TARGET (cmake)"
    "$SCRIPT_DIR/compile-ijk.sh" "$PARAM_TARGET"
}

do_clean() {
    echo "==> clean native + gradle outputs (keep build/android/deps)"
    find "$REPO_DIR/build/android" -maxdepth 1 -mindepth 1 ! -name deps -exec rm -rf {} + 2>/dev/null || true
    rm -rf "$REPO_DIR/platform/android/.gradle" \
           "$REPO_DIR/platform/android/app/build" \
           "$REPO_DIR/platform/android/library/build"
    echo "done."
}

do_build_aar() {
    echo "==> aar: library"
    ( cd "$REPO_DIR/platform/android" && ./gradlew :library:assembleRelease )
    echo "AAR: build/android/artifacts/fplayercore-release.aar"
    "$REPO_DIR/scripts/collect.sh" android
}

case "$REQUEST_TARGET" in
    arm64|x86|x86_64)
        do_build_native "$REQUEST_TARGET"
        do_build_aar
    ;;
    all32)
        for ABI in $ACT_ABI_32; do
            do_build_native "$ABI"
        done
        do_build_aar
    ;;
    all|all64)
        for ABI in $ACT_ABI_64; do
            do_build_native "$ABI"
        done
        do_build_aar
    ;;
    aar)
        do_build_aar
    ;;
    clean)
        do_clean
    ;;
    clean-all)
        do_clean
        rm -rf "$REPO_DIR/build/android"
        echo "已清理 build/android（含 deps）"
    ;;
    *)
        echo "Usage:"
        echo "  build-android.sh arm64|x86|x86_64"
        echo "  build-android.sh all|all32|all64"
        echo "  build-android.sh aar"
        echo "  build-android.sh clean        # 原生 + Gradle 产物（保留 build/android/deps）"
        echo "  build-android.sh clean-all    # 连 deps 一起清理"
        exit 1
    ;;
esac

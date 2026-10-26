#!/usr/bin/env bash
#
# 统一清理脚本
#
# 用法:
#   ./scripts/clean.sh                 # = all
#   ./scripts/clean.sh all             # 所有产物（含不常用的 build/ 全目录）
#   ./scripts/clean.sh android         # build/android（含 deps）
#   ./scripts/clean.sh android-native  # 仅原生构建目录（保留 deps）
#   ./scripts/clean.sh android-deps    # 仅 FFmpeg/BoringSSL 等依赖
#   ./scripts/clean.sh ios             # build/ios
#   ./scripts/clean.sh macos           # build/macos
#   ./scripts/clean.sh gradle          # Gradle/AGP 产物（build/.cxx/.gradle）
#
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_ROOT="$REPO_DIR/build"

clean_gradle() {
    echo "==> clean gradle/agp outputs"
    rm -rf "$BUILD_ROOT/android/gradle" \
           "$REPO_DIR/platform/android/.gradle" \
           "$REPO_DIR/platform/android/app/build" \
           "$REPO_DIR/platform/android/library/build"
}

clean_android_native() {
    echo "==> clean android native build dirs (keep deps)"
    find "$BUILD_ROOT/android" -maxdepth 1 -mindepth 1 ! -name deps -exec rm -rf {} + 2>/dev/null || true
}

clean_android_deps() {
    echo "==> clean android deps (ffmpeg/boringssl/toolchain)"
    rm -rf "$BUILD_ROOT/android/deps"
}

case "${1:-all}" in
    all)
        clean_gradle
        echo "==> clean $BUILD_ROOT"
        rm -rf "$BUILD_ROOT"
    ;;
    android)
        clean_gradle
        rm -rf "$BUILD_ROOT/android"
    ;;
    android-native)
        clean_android_native
    ;;
    android-deps)
        clean_android_deps
    ;;
    ios)
        echo "==> clean $BUILD_ROOT/ios"
        rm -rf "$BUILD_ROOT/ios"
    ;;
    macos)
        echo "==> clean $BUILD_ROOT/macos"
        rm -rf "$BUILD_ROOT/macos"
    ;;
    gradle)
        clean_gradle
    ;;
    *)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
    ;;
esac

echo "done."

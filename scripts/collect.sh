#!/usr/bin/env bash
#
# 收集各平台最终产物到 build/<platform>/artifacts/
#
# 用法:
#   ./scripts/collect.sh           # = all
#   ./scripts/collect.sh android   # AAR / APK / 原生 .so
#   ./scripts/collect.sh ios       # *.framework（device + simulator）
#   ./scripts/collect.sh macos     # fplayercore.framework / libfplayercore.dylib
#
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
BUILD_ROOT="$REPO_DIR/build"

copy_if_exists() {
    local src="$1" dst="$2"
    [ -e "$src" ] || return 0
    mkdir -p "$dst"
    cp -Rf "$src" "$dst"/
    echo "  + $(basename "$src")"
}

collect_android() {
    local out="$BUILD_ROOT/android/artifacts"
    echo "==> android -> $out"
    # Drop stale native artifacts (pre single-.so builds shipped three libraries).
    rm -rf "$out/native-arm64"
    mkdir -p "$out/native-arm64"
    copy_if_exists "$BUILD_ROOT/android/arm64/lib/libijkplayer.so" "$out/native-arm64"
    for f in "$BUILD_ROOT"/android/gradle/library/outputs/aar/*.aar; do
        copy_if_exists "$f" "$out"
    done
    for f in "$BUILD_ROOT"/android/gradle/app/outputs/apk/*/*.apk; do
        copy_if_exists "$f" "$out"
    done
}

collect_ios() {
    local out="$BUILD_ROOT/ios/artifacts"
    echo "==> ios -> $out"
    for d in iphoneos simulator; do
        case "$d" in
            iphoneos)  src="$REPO_DIR/platform/ios/IJKMediaPlayer/build/Release-iphoneos" ;;
            simulator) src="$REPO_DIR/platform/ios/IJKMediaPlayer/build/Release-iphonesimulator" ;;
        esac
        [ -d "$src" ] || continue
        mkdir -p "$out/$d"
        for fw in "$src"/*.framework; do
            [ -d "$fw" ] || continue
            copy_if_exists "$fw" "$out/$d"
        done
    done
}

collect_macos() {
    local out="$BUILD_ROOT/macos/artifacts"
    echo "==> macos -> $out"
    mkdir -p "$out"
    for fw in "$REPO_DIR"/platform/macos/IJKMediaPlayer/build/Release/*.framework; do
        [ -d "$fw" ] || continue
        copy_if_exists "$fw" "$out"
    done
    copy_if_exists "$BUILD_ROOT/macos/libfplayercore.dylib" "$out"
}

case "${1:-all}" in
    all)     collect_android; collect_ios; collect_macos ;;
    android) collect_android ;;
    ios)     collect_ios ;;
    macos)   collect_macos ;;
    *)
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
    ;;
esac

echo
echo "artifacts:"
find "$BUILD_ROOT" -type d -name artifacts -exec find {} -maxdepth 2 -mindepth 1 \; 2>/dev/null | sed "s|$REPO_DIR/||" | sort

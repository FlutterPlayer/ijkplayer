#!/usr/bin/env bash
#
# 用法: ./ijk-ndk-stack.sh [logcat 文件]
# 读取 adb logcat（或给定文件）并用未 strip 的 arm64-v8a 符号解析 native crash。

set -e
DIR=$(cd "$(dirname "$0")/../.." && pwd)

NDK="${ANDROID_NDK:-}"
if [ -z "$NDK" ]; then
    for d in "$HOME"/Library/Android/sdk/ndk/*; do
        [ -d "$d" ] && NDK="$d"
    done
fi
[ -n "$NDK" ] || { echo "请设置 ANDROID_NDK" >&2; exit 1; }

SYM=$(ls -d "$DIR"/build/android/gradle/library/intermediates/cxx/*/*/obj/arm64-v8a 2>/dev/null | head -1)
if [ -z "$SYM" ]; then
    echo "未找到 arm64-v8a 符号目录，请先构建：platform/android/gradlew :library:assembleRelease" >&2
    exit 1
fi

if [ -n "$1" ]; then
    "$NDK/ndk-stack" -sym "$SYM" -dump "$1"
else
    adb logcat | "$NDK/ndk-stack" -sym "$SYM"
fi

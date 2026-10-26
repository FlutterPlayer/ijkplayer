#!/usr/bin/env bash
#
# 用法: ./ijk-addr2line.sh <libname> [addr...]
#   例: ./ijk-addr2line.sh ijkplayer 0x1234
#
# 符号来自 AGP 的 CMake 中间产物（未 strip），仅 arm64-v8a。
# 使用 NDK 自带的 llvm-addr2line（macOS 默认没有 GNU addr2line）。

set -e
DIR=$(cd "$(dirname "$0")/../.." && pwd)

NDK="${ANDROID_NDK:-}"
if [ -z "$NDK" ]; then
    for d in "$HOME"/Library/Android/sdk/ndk/*; do
        [ -d "$d" ] && NDK="$d"
    done
fi
[ -n "$NDK" ] || { echo "请设置 ANDROID_NDK（或安装 NDK 到默认 SDK 目录）" >&2; exit 1; }

TOOLCHAIN=$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin 2>/dev/null | head -1)
[ -n "$TOOLCHAIN" ] || { echo "未找到 NDK llvm 工具链：$NDK" >&2; exit 1; }

SO=$(ls "$DIR"/build/android/gradle/library/intermediates/cxx/*/*/obj/arm64-v8a/lib"$1".so 2>/dev/null | head -1)
if [ -z "$SO" ]; then
    echo "未找到 lib$1.so，请先构建：platform/android/gradlew :library:assembleRelease" >&2
    exit 1
fi
shift
exec "$TOOLCHAIN/llvm-addr2line" -e "$SO" -f -C "$@"

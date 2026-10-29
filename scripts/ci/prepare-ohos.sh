#!/usr/bin/env bash
set -euo pipefail

: "${HOS_SDK_HOME:?HOS_SDK_HOME must be set by setup-ohos}"
SDK_ROOT="$HOS_SDK_HOME/default/openharmony"
NATIVE="$SDK_ROOT/native"
test -d "$NATIVE"

VERSION=$(python3 - "$NATIVE/oh-uni-package.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["platformVersion"])
PY
)
test -n "$VERSION"

if [ ! -d "$SDK_ROOT/$VERSION" ]; then
    mkdir -p "$SDK_ROOT/$VERSION"
    for component in ets js native previewer toolchains; do
        if [ -e "$SDK_ROOT/$component" ]; then
            ln -s "$SDK_ROOT/$component" "$SDK_ROOT/$VERSION/$component"
        fi
    done
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        printf 'OHOS_SDK=%s/native\n' "$SDK_ROOT"
        printf 'OHOS_BASE_SDK_HOME=%s\n' "$SDK_ROOT"
        printf 'DEVECO_SDK_HOME=%s\n' "$HOS_SDK_HOME"
    } >> "$GITHUB_ENV"
else
    export OHOS_SDK="$SDK_ROOT/native"
    export OHOS_BASE_SDK_HOME="$SDK_ROOT"
    export DEVECO_SDK_HOME="$HOS_SDK_HOME"
fi

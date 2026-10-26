#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MODULE_DIR="$REPO_DIR/platform/ohos"
PROJECT_DIR="$REPO_DIR/build/ohos/har-project"
HAR_OUT="$REPO_DIR/build/ohos/fplayercore-ohos.har"

: "${OHOS_BASE_SDK_HOME:?OHOS_BASE_SDK_HOME must point at the versioned DevEco SDK root}"
: "${OHOS_SDK:?OHOS_SDK must point at the OpenHarmony native SDK}"
: "${DEVECO_SDK_HOME:?DEVECO_SDK_HOME must point at the DevEco SDK root}"

command -v hvigorw >/dev/null 2>&1 || {
  printf 'hvigorw not found on PATH\n' >&2
  exit 1
}
command -v ohpm >/dev/null 2>&1 || {
  printf 'ohpm not found on PATH\n' >&2
  exit 1
}

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/hvigor" "$PROJECT_DIR/AppScope"
cp -R "$MODULE_DIR" "$PROJECT_DIR/fplayercore"
rm -rf "$PROJECT_DIR/fplayercore/oh_modules" "$PROJECT_DIR/fplayercore/build"

cat > "$PROJECT_DIR/AppScope/app.json5" <<'JSON5'
{
  "app": {
    "bundleName": "com.flutterplayer.fplayercore",
    "vendor": "FlutterPlayer",
    "versionCode": 1000000,
    "versionName": "1.0.0"
  }
}
JSON5

cat > "$PROJECT_DIR/build-profile.json5" <<'JSON5'
{
  "app": {
    "signingConfigs": [],
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compatibleSdkVersion": "26.0.0",
        "compileSdkVersion": "26.0.0",
        "targetSdkVersion": "26.0.0",
        "runtimeOS": "OpenHarmony"
      }
    ]
  },
  "modules": [
    {
      "name": "fplayercore_ohos",
      "srcPath": "./fplayercore",
      "targets": [
        {
          "name": "default",
          "applyToProducts": [
            "default"
          ]
        }
      ]
    }
  ]
}
JSON5

cat > "$PROJECT_DIR/hvigorfile.ts" <<'TS'
import { appTasks } from '@ohos/hvigor-ohos-plugin';

export default {
    system: appTasks,
    plugins: []
}
TS

cat > "$PROJECT_DIR/oh-package.json5" <<'JSON5'
{
  "modelVersion": "6.0.0",
  "description": "fplayercore HAR build",
  "dependencies": {},
  "devDependencies": {}
}
JSON5

cp "$MODULE_DIR/hvigor/hvigor-config.json5" "$PROJECT_DIR/hvigor/hvigor-config.json5"

cd "$PROJECT_DIR"
ohpm install
(
  cd fplayercore
  ohpm install
)
IJKROOT_PATH="$REPO_DIR" hvigorw assembleHar --mode module -p module=fplayercore_ohos@default --no-daemon

HAR="$(find "$PROJECT_DIR" -name '*.har' -not -path '*/oh_modules/*' | head -n 1)"
test -n "$HAR"
mkdir -p "$(dirname "$HAR_OUT")"
cp "$HAR" "$HAR_OUT"
printf 'HAR=%s\n' "$HAR_OUT"

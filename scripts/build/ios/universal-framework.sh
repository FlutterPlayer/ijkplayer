#!/usr/bin/env bash
#
# Build the device and Apple Silicon simulator frameworks and package them as
# one XCFramework. Both slices are arm64, so lipo cannot merge them into a
# single fat framework; XCFramework keeps the platform variants separate.

set -euo pipefail

DEVICE_FRAMEWORK="${BUILD_DIR}/${CONFIGURATION}-iphoneos/${TARGET_NAME}.framework"
SIMULATOR_FRAMEWORK="${BUILD_DIR}/${CONFIGURATION}-iphonesimulator/${TARGET_NAME}.framework"
XCFRAMEWORK_OUT="${BUILD_DIR}/${CONFIGURATION}-xcframework/${TARGET_NAME}.xcframework"

xcodebuild -target "${TARGET_NAME}" ONLY_ACTIVE_ARCH=NO \
    -configuration "${CONFIGURATION}" -sdk iphoneos -arch arm64 \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}" clean build

xcodebuild -target "${TARGET_NAME}" ONLY_ACTIVE_ARCH=NO \
    -configuration "${CONFIGURATION}" -sdk iphonesimulator -arch arm64 \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    BUILD_DIR="${BUILD_DIR}" BUILD_ROOT="${BUILD_ROOT}" clean build

rm -rf "${XCFRAMEWORK_OUT}"
mkdir -p "$(dirname "${XCFRAMEWORK_OUT}")"
xcodebuild -create-xcframework \
    -framework "${DEVICE_FRAMEWORK}" \
    -framework "${SIMULATOR_FRAMEWORK}" \
    -output "${XCFRAMEWORK_OUT}"

mkdir -p "${PROJECT_DIR}/../CocoaPodsConfig"
rm -rf "${PROJECT_DIR}/../CocoaPodsConfig/${TARGET_NAME}.xcframework"
cp -R "${XCFRAMEWORK_OUT}" "${PROJECT_DIR}/../CocoaPodsConfig/"

open "${PROJECT_DIR}/../CocoaPodsConfig"

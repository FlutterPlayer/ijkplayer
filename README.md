# ijkplayer

FFmpeg 8 media kernels for the FlutterPlayer ecosystem.

This repository builds the native player used by
[FlutterPlayer/fplayer](https://github.com/FlutterPlayer/fplayer). It contains
the C engine, the SDL-name shim, Android JNI, Apple wrappers, OpenHarmony NAPI
and the per-platform build facades.

- Android API 28+ (arm64-v8a; AAudio, OpenSL ES, Vulkan/MediaCodec)
- iOS 13+ (device arm64; arm64 simulator; VideoToolbox/Metal)
- macOS 10.15+ (arm64 CI build; universal builds are possible locally)
- Windows x64 (MSVC static build)
- OpenHarmony API 12+ (arm64-v8a; OHAudio/EGL/GLES)

## Published packages

Every tagged release publishes one version for all consumers:

| Platform | Release asset | Downstream use |
| --- | --- | --- |
| Android | `fplayercore-release.aar` | Gradle AAR; also published as `io.github.flutterplayer:fplayercore:<tag>` on Maven Central |
| iOS | `fplayercore-ios.xcframework.zip` | [`fplayercore-ios` Swift Package](https://github.com/FlutterPlayer/fplayercore-ios) |
| iOS (CocoaPods) | `fplayercore-ios.tar.gz` | podspec vendors the xcframework |
| macOS | `fplayercore-macos.xcframework.zip` | [`fplayercore-macos` Swift Package](https://github.com/FlutterPlayer/fplayercore-macos) |
| Windows | `fplayercore-windows.zip` | `fplayercore.lib`, `fplayercore.dll`, `fplayercore.h` |
| OpenHarmony | `fplayercore-ohos.har` | `@fplayer/fplayercore` HAR |
| All | `fplayercore-manifest.json` | version, commit and SHA-256 of every asset |

The release workflow is [.github/workflows/release.yml](.github/workflows/release.yml).
A tag push builds Android, iOS, macOS, Windows and OpenHarmony, publishes the
Android artifact to Maven Central when the Nexus secrets are configured, and
attaches those assets to the GitHub Release. The Android job runs
`:library:publishToSonatype` and `closeAndReleaseSonatypeStagingRepository` in
one invocation, so a successful publish closes and releases its staging
repository instead of leaving it open. The OHOS job runs on `ubuntu-latest`,
installs HarmonyOS command-line tools with `ErBWs/setup-ohos` (SDK
`26.0.0.821`), builds OpenSSL/FFmpeg/native libraries and packages the HAR.

Swift Package consumers use the dedicated binary package repositories:

```swift
.package(url: "https://github.com/FlutterPlayer/fplayercore-ios.git", exact: "1.2.12")
.product(name: "fplayercore", package: "fplayercore-ios")
```

```swift
.package(url: "https://github.com/FlutterPlayer/fplayercore-macos.git", exact: "1.2.12")
.product(name: "fplayercore", package: "fplayercore-macos")
```

```bash
git tag 1.2.0
git push origin 1.2.0
```

Before tagging, set `spec.version` in
`platform/ios/CocoaPodsConfig/fplayercore.podspec` to the same version; the
Gradle Android version is supplied by `-PVERSION_NAME=<tag>` in the workflow.

`workflow_dispatch` can rebuild a tag and opt into the OpenHarmony job with
`build_ohos=true`; tag pushes include OHOS automatically. The OHOS job uses
GitHub-hosted Ubuntu and the `ErBWs/setup-ohos` action, so no self-hosted runner
is required.

## Consumed by fplayer

`fplayer` does not vendor these binaries. It resolves the latest release, or a
pinned tag, and installs the matching asset for each platform:

```bash
./tool/fetch_ijkplayer_packages.sh
./tool/fetch_ijkplayer_packages.sh 1.2.0
```

The fetch maps the assets to `android/local-repo` (mirrored as the Maven
coordinate `io.github.flutterplayer:fplayercore:<tag>`),
`ios/fplayer/Frameworks`, `macos/fplayer/Frameworks`, `ohos/har` and
`windows/third_party/ijkplayer`.
That keeps one `fplayer` version on one kernel version across Android, iOS,
macOS, Windows and OpenHarmony.

## Build prerequisites

| Platform | Dependencies |
| --- | --- |
| Android | JDK 17, NDK 29.0.14206865, CMake 3.22.1, Gradle wrapper |
| iOS / macOS | Xcode command-line tools, `gas-preprocessor` (fetched by the init scripts), `cmake`, `yasm` |
| Windows | Visual Studio 2022, vcpkg, CMake |
| OpenHarmony | OpenHarmony SDK with the native toolchain; `OHOS_SDK` points at `native/` |
| Common | `git`, `bash` |

All scripts locate the repository root themselves and write to `build/`.

## Build Android

```bash
./scripts/init/init-android.sh
./scripts/init/init-android-boringssl.sh
./scripts/init/init-android-libsrt.sh

./scripts/build/android/compile-boringssl.sh all
./scripts/build/android/compile-ffmpeg.sh all

cd platform/android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
./gradlew :library:assembleRelease
./gradlew :app:assembleDebug
cd ../..

./scripts/collect.sh android
```

The AAR is `build/android/gradle/library/outputs/aar/fplayercore-release.aar`.
The AAR contains the Java API and the single `libijkplayer.so` (arm64-v8a);
FFmpeg is linked statically. Android builds use NDK 29+ and
`-Wl,-z,max-page-size=16384`, so every `LOAD` segment in the shared library
is 16 KB aligned for Google Play's 16 KB page-size requirement.

## Build iOS

```bash
./scripts/init/init-ios.sh
./scripts/init/init-ios-openssl.sh

./scripts/build/ios/compile-openssl.sh all
./scripts/build/ios/compile-ffmpeg.sh all

xcodebuild -project platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj \
  -scheme fplayercore -configuration Release -sdk iphoneos -arch arm64 \
  -derivedDataPath build/xcode-ios-iphoneos CODE_SIGNING_ALLOWED=NO build

xcodebuild -project platform/ios/IJKMediaPlayer/IJKMediaPlayer.xcodeproj \
  -scheme fplayercore -configuration Release -sdk iphonesimulator -arch arm64 \
  -derivedDataPath build/xcode-ios-simulator CODE_SIGNING_ALLOWED=NO build

xcodebuild -create-xcframework \
  -framework build/xcode-ios-iphoneos/Build/Products/Release-iphoneos/fplayercore.framework \
  -framework build/xcode-ios-simulator/Build/Products/Release-iphonesimulator/fplayercore.framework \
  -output fplayercore.xcframework
tar -czf fplayercore-ios.tar.gz fplayercore.xcframework
```

The iOS podspec in `platform/ios/CocoaPodsConfig` downloads
`fplayercore-ios.tar.gz` and vendors the xcframework.

## Build macOS

```bash
./scripts/init/init-osx.sh
./scripts/build/macos/compile-ffmpeg.sh all

xcodebuild -project platform/macos/IJKMediaPlayer/IJKMediaPlayer.xcodeproj \
  -scheme fplayercore -configuration Release -arch arm64 \
  -derivedDataPath build/xcode-macos CODE_SIGNING_ALLOWED=NO build

xcodebuild -create-xcframework \
  -framework build/xcode-macos/Build/Products/Release/fplayercore.framework \
  -output fplayercore.xcframework
```

The macOS target links OpenSSL statically per architecture. A universal
`arm64 x86_64` build needs both Homebrew prefixes and can be produced locally.

## Build Windows

```powershell
.\scripts\windows\prepare-deps.ps1 -VcpkgRoot $env:VCPKG_INSTALLATION_ROOT
.\scripts\windows\build-windows.ps1 -VcpkgRoot $env:VCPKG_INSTALLATION_ROOT
```

Outputs are staged under `build/windows/{bin,lib,include}`. Package them as
`fplayercore/` inside `fplayercore-windows.zip` for the release.

## Build OpenHarmony

```bash
export OHOS_SDK=/path/to/openharmony/sdk/native
export OHOS_BASE_SDK_HOME=/path/to/openharmony/sdk
export DEVECO_SDK_HOME=/path/to/deveco/sdk
./scripts/build/ohos/compile-openssl.sh arm64
./scripts/build/ohos/compile-ffmpeg.sh arm64
./scripts/build/ohos/compile-ijk.sh arm64
./scripts/build/ohos/package-har.sh
```

The HAR is `@fplayer/fplayercore`; the native libraries are
`libijkplayer.so`, `libijksdl.so`, `libijkplayer_napi.so` and the bundled
`libc++_shared.so`. See [platform/ohos/README.md](platform/ohos/README.md).

## Clean

```bash
./scripts/clean.sh
./scripts/clean.sh android
./scripts/clean.sh ios
./scripts/clean.sh macos
./scripts/clean.sh gradle
```

## Support and license

Use GitHub issues for public technical discussion. The kernel is LGPLv2.1 or
later; see [COPYING.LGPLv2.1](COPYING.LGPLv2.1) and
[COPYING.LGPLv3](COPYING.LGPLv3). Third-party components are listed in
[NOTICE](NOTICE).

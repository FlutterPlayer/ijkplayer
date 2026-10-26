# ijkplayer for OpenHarmony

This directory contains the OpenHarmony (OHOS) build of ijkplayer:

- `src/main/cpp/CMakeLists.txt` builds `libijkplayer.so`, `libijksdl.so` and the
  `libijkplayer_napi.so` bridge consumed by ArkTS.
- `src/main/cpp/napi/ijkplayer_napi.cpp` exposes the player to ArkTS and binds a
  Flutter texture surface id to an `OHNativeWindow` for EGL rendering.
- `src/main/ets/ijkplayer/` contains the ArkTS `IjkMediaPlayer` wrapper exported
  by the HAR (`@fplayer/fplayercore`).
- The OHOS backends live in `ijkmedia/ijksdl/ohos/` (EGL/GLES rendering and
  OHAudio output) and `ijkmedia/ijkplayer/ohos/` (pipeline).

## Prerequisites

- OpenHarmony SDK with the native toolchain (DevEco Studio SDK Manager, or the
  public SDK archive). `OHOS_SDK` must point at the SDK's `native` directory,
  which contains `llvm/`, `sysroot/` and `build/cmake/ohos.toolchain.cmake`.
- The vendored FFmpeg source at `extra/ffmpeg-ijk8`.

## Build

```bash
export OHOS_SDK=/path/to/openharmony/sdk/native
export OHOS_BASE_SDK_HOME=/path/to/openharmony/sdk
export DEVECO_SDK_HOME=/path/to/deveco/sdk
./scripts/build/ohos/compile-ffmpeg.sh arm64
./scripts/build/ohos/package-har.sh
```

Artifacts:

- FFmpeg: `build/ohos/deps/output-arm64/{include,lib}`
- Native libraries: `build/ohos/cmake-arm64/ijkmedia/ijksdl/libijksdl.so`,
  `build/ohos/cmake-arm64/ijkmedia/ijkplayer/libijkplayer.so`,
  `build/ohos/cmake-arm64/libijkplayer_napi.so`

Replace `arm64` with `x86_64` for the emulator.

Verified against the OpenHarmony 5.1.0 native SDK (darwin-x64 toolchain under
Rosetta on arm64 macOS): all three libraries are AArch64 ELF shared objects.
FFmpeg is linked statically into `libijkplayer.so`, so only `libc++_shared.so`
must be bundled alongside the three libraries in the OHOS app's `libs/arm64`.

The NAPI module registers as `ijkplayer_napi` and depends on
`libace_napi.z.so`, `libace_ndk.z.so`, `libnative_window.so`,
`libhilog_ndk.z.so`, `libEGL.so`, `libGLESv3.so` and `libohaudio.so`.

## Use from Flutter

The HAR is published as the `fplayercore-ohos.har` release asset. The `fplayer`
plugin fetches it with `tool/fetch_ijkplayer_packages.sh` into `ohos/har/` and
declares:

```json5
"@fplayer/fplayercore": "file:./har/fplayercore-ohos.har"
```

Build the HAR with `hvigorw assembleHar`, or download the tagged release asset.

## Limitations

- Software video decoding only. The OHOS hardware decoder used by
  `ohos_ijkplayer` is not ported yet, so CPU usage is higher for 4K streams.
- System volume changes (`volumeUp`/`volumeDown`/`volumeMute`) are not exposed
  by the public OHOS API.
- Snapshot capture is not implemented for OHOS.

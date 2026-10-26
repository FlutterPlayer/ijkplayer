# 脚本索引

脚本统一放在仓库根 `scripts/` 下；所有构建产物统一输出到仓库根 `build/`（已被 `.gitignore` 忽略）。

## 目录结构

```
build/                              # 所有生成物
├── android/
│   ├── deps/                       # FFmpeg / BoringSSL / toolchain 安装前缀
│   │   ├── output-arm64/{include,lib}
│   │   ├── boringssl-arm64/
│   │   └── toolchain-arm64/
│   ├── gradle/                     # Gradle/AGP 产物（buildDirectory 重定向）
│   │   ├── app/outputs/apk/...
│   │   └── library/outputs/aar/...
│   ├── arm64/lib/                  # compile-ijk.sh 的原生产物
│   └── artifacts/                  # collect.sh 收集的最终产物
│       ├── fplayercore-release.aar
│       ├── app-debug.apk
│       └── native-arm64/*.so
├── ios/
│   ├── ffmpeg-arm64/ ffmpeg-arm64-simulator/
│   ├── openssl-arm64/ openssl-arm64-simulator/
│   ├── universal/include           # 公共头文件
│   ├── iphoneos/lib                # 真机 arm64
│   ├── iphonesimulator/lib         # Apple Silicon 模拟器 arm64
│   └── artifacts/{iphoneos,simulator}/*.framework
└── macos/
    ├── ffmpeg-arm64/ ffmpeg-x86_64/
    ├── ffmpeg-universal/output/    # Xcode 使用
    ├── libfplayercore.dylib
    ├── lib/ include/ ...
    └── artifacts/{fplayercore.framework, libfplayercore.dylib}

scripts/
├── init/                           # 初始化：拉取第三方源码
├── build/
│   ├── android/                    # Android 依赖 + 应用构建
│   │   └── tools/                  # 单 arch 实现（内部调用）
│   ├── ios/                        # iOS 依赖构建
│   │   └── tools/
│   ├── macos/                      # macOS 依赖构建
│   │   └── tools/
│   ├── version.sh
│   └── compile-android-j4a.sh
├── dev/                            # 调试辅助
└── tools/                          # 通用工具（pull-repo / copyrighter）
```

## 1. 初始化

| 脚本 | 作用 |
|---|---|
| `scripts/init/init-android.sh` | 拉取 Android FFmpeg + soundtouch + BoringSSL |
| `scripts/init/init-ios.sh` | 拉取 iOS FFmpeg + gas-preprocessor |
| `scripts/init/init-osx.sh` | 拉取 macOS FFmpeg + gas-preprocessor |
| `scripts/init/init-ios-openssl.sh` | 拉取 iOS OpenSSL（仅当要启用 OpenSSL） |
| `scripts/init/init-config.sh` | 生成 `config/module.sh`（默认 `module-lite.sh`） |
| `scripts/init/init-android-soundtouch.sh` | 单独拉取 soundtouch |
| `scripts/init/init-android-boringssl.sh` | 单独拉取 BoringSSL（Android TLS，默认） |
| `scripts/init/init-android-openssl.sh` | 单独拉取 OpenSSL（Android，备选） |
| `scripts/init/init-android-j4a.sh` | 拉取 jni4android（`ijkj4a` 代码生成） |
| `scripts/init/init-android-libsrt.sh` / `init-android-libsoxr.sh` | 可选依赖，**默认配置未启用** |

通用工具：`scripts/tools/pull-repo-base.sh`（clone 到 `extra/` 缓存）、`pull-repo-ref.sh`（基于缓存 clone）、`copyrighter/`（补版权头）。

## 2. 依赖构建

### Android（输出 `build/android/deps/`）

| 脚本 | 作用 |
|---|---|
| `scripts/build/android/compile-ffmpeg.sh arm64` | 构建 FFmpeg（唯一 ABI：arm64） |
| `scripts/build/android/compile-boringssl.sh arm64` | 构建 BoringSSL（默认 TLS） |
| `scripts/build/android/compile-openssl.sh arm64` | 构建 OpenSSL（备选） |
| `scripts/build/android/compile-libsrt.sh` / `compile-libsoxr.sh` | 可选，默认未启用 |
| `scripts/build/android/tools/do-compile-*.sh` | 单 arch 实现（内部调用） |
| `scripts/build/android/tools/do-detect-env.sh` | 探测 NDK/SDK/工具链 |

### iOS（输出 `build/ios/`）

| 脚本 | 作用 |
|---|---|
| `scripts/build/ios/compile-ffmpeg.sh [arm64\|arm64-simulator\|all]` | iOS FFmpeg（TLS 走 SecureTransport） |
| `scripts/build/ios/compile-openssl.sh` | iOS OpenSSL（仅当升级到 ≥1.1.1） |
| `scripts/build/ios/universal-framework.sh` | 打包 device + arm64 simulator XCFramework |

### macOS（输出 `build/macos/`）

| 脚本 | 作用 |
|---|---|
| `scripts/build/macos/compile-ffmpeg.sh all` | macOS FFmpeg + lipo 出 `ffmpeg-universal/output`（TLS 走 Homebrew OpenSSL 3） |
| `scripts/build/macos/compile-ffmpeg.sh lipo` | 仅重新生成 universal 产物 |
| `scripts/build/macos/compile-libsrt.sh` | 可选，默认未启用 |

## 3. 应用构建

| 脚本 | 作用 |
|---|---|
| `scripts/build/android/compile-ijk.sh arm64` | 纯原生构建（CMake）→ `build/android/arm64/lib/*.so` |
| `scripts/build/android/build-android.sh [arm64\|all\|aar]` | 一体化：FFmpeg → 原生 → AAR（并自动 collect） |
| `scripts/collect.sh [android\|ios\|macos]` | 收集最终产物到 `build/<platform>/artifacts/` |
| `platform/android/gradlew` | Gradle 入口（`:library:assembleRelease` / `:app:assembleDebug`） |
| `scripts/build/version.sh` | 同步版本号到各构建文件 |
| `scripts/build/compile-android-j4a.sh` | 重新生成 `ijkj4a` 绑定 |

## 4. 调试工具

| 脚本 | 作用 |
|---|---|
| `scripts/dev/ijk-addr2line.sh <lib> <addr>` | 用 AGP 的 arm64 未 strip 符号解析地址 |
| `scripts/dev/ijk-ndk-stack.sh` | `adb logcat` + `ndk-stack` 自动解析 native crash |
| `ijkmedia/ijksdl/android/vulkan/shaders/build-shaders.sh` | GLSL → SPIR-V（Vulkan 着色器） |

## 5. 清理

| 命令 | 作用 |
|---|---|
| `scripts/clean.sh` / `all` | 清理全部（Gradle 产物 + 整个 `build/`） |
| `scripts/clean.sh android` | `build/android`（含 deps）+ Gradle 产物 |
| `scripts/clean.sh android-native` | 仅原生构建目录（保留 `build/android/deps`） |
| `scripts/clean.sh android-deps` | 仅 FFmpeg / BoringSSL / toolchain |
| `scripts/clean.sh ios` / `macos` | 对应平台依赖产物 |
| `scripts/clean.sh gradle` | `app|library` 的 `build/`、`.cxx/`、`.gradle/` |
| `build-android.sh clean` | 原生 + Gradle（保留 deps） |
| `build-android.sh clean-all` | 同上并删除 `build/android`（含 deps） |

各依赖脚本自身也支持 `clean`：
`compile-{ffmpeg,boringssl,openssl,libsrt,libsoxr}.sh clean`、
`scripts/build/ios/compile-{ffmpeg,openssl}.sh clean`、
`scripts/build/macos/compile-{ffmpeg,libsrt}.sh clean`。

## 约定

- 所有 `.sh` 统一 shebang：`#!/usr/bin/env bash`，均带可执行位，`bash -n` 全部通过。
- 构建脚本自行定位仓库根（`REPO_DIR`），可在任意目录调用。
- Android 仅支持 **arm64-v8a**；`armv7a`/`x86` 直接打印用法退出。
- TLS 后端：Android = BoringSSL，iOS = SecureTransport，macOS = OpenSSL 3。
- `compile-ijk.sh clean` 只清理原生构建目录，**保留** `build/android/deps/`。

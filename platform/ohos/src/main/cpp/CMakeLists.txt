cmake_minimum_required(VERSION 3.5)

if (POLICY CMP0079)
    cmake_policy(SET CMP0079 NEW)
endif ()

project(ijkplayer_napi C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_link_options(-Wl,-Bsymbolic)

if (NOT DEFINED IJKROOT_PATH)
    if (DEFINED ENV{IJKROOT_PATH})
        set(IJKROOT_PATH "$ENV{IJKROOT_PATH}")
    else ()
        set(IJKROOT_PATH "${CMAKE_CURRENT_LIST_DIR}/../../../../../")
    endif ()
endif ()
get_filename_component(IJKROOT_PATH "${IJKROOT_PATH}" ABSOLUTE)

set(IJK_OHOS ON CACHE BOOL "Build the OpenHarmony backend" FORCE)

if (NOT DEFINED IJK_FFMPEG_ROOT)
    if (OHOS_ARCH STREQUAL "x86_64")
        set(_ijk_ffmpeg_arch x86_64)
    else ()
        set(_ijk_ffmpeg_arch arm64)
    endif ()
    set(IJK_FFMPEG_ROOT "${IJKROOT_PATH}/build/ohos/deps/output-${_ijk_ffmpeg_arch}" CACHE PATH "FFmpeg output for OpenHarmony")
endif ()
set(IJK_FFMPAG_BUILD_DIR "${IJK_FFMPEG_ROOT}")

add_definitions(-D__OHOS__=1)

include_directories(${IJKROOT_PATH}/ijkmedia)
include_directories(${IJKROOT_PATH}/ijkmedia/ijkplayer)
include_directories(${IJKROOT_PATH}/ijkmedia/ijksdl)
include_directories(${IJK_FFMPEG_ROOT}/include)

add_subdirectory(${IJKROOT_PATH}/ijkmedia ${CMAKE_CURRENT_BINARY_DIR}/ijkmedia)

foreach (FF_LIB avcodec avformat avutil swresample swscale avfilter)
    target_link_directories(ijksdl PRIVATE ${IJK_FFMPEG_ROOT}/lib)
    target_link_libraries(ijksdl ${FF_LIB})
endforeach ()
target_link_libraries(ijksdl z m)

target_link_directories(ijkplayer PRIVATE ${IJK_FFMPEG_ROOT}/lib)
target_link_libraries(ijkplayer ijksdl z m)
foreach (FF_LIB avcodec avformat avutil swresample swscale avfilter)
    target_link_libraries(ijkplayer ${FF_LIB})
endforeach ()

# SSH/TLS support: FFmpeg was built with OpenSSL, so its https/tls protocol
# objects reference libssl/libcrypto; link the static copies after FFmpeg.
if (OHOS_ARCH STREQUAL "x86_64")
    set(_ijk_tls_arch x86_64)
else ()
    set(_ijk_tls_arch arm64)
endif ()
set(IJK_OPENSSL_ROOT "${IJKROOT_PATH}/build/ohos/deps/output-openssl-${_ijk_tls_arch}" CACHE PATH "OpenSSL output for OpenHarmony")
if (EXISTS "${IJK_OPENSSL_ROOT}/lib/libssl.a")
    target_link_directories(ijksdl PRIVATE ${IJK_OPENSSL_ROOT}/lib)
    target_link_directories(ijkplayer PRIVATE ${IJK_OPENSSL_ROOT}/lib)
    target_link_libraries(ijksdl ssl crypto dl pthread)
    target_link_libraries(ijkplayer ssl crypto dl pthread)
endif ()

add_library(ijkplayer_napi SHARED
    napi/ijkplayer_napi.cpp
)

target_include_directories(ijkplayer_napi PRIVATE
    ${IJKROOT_PATH}/ijkmedia
    ${IJKROOT_PATH}/ijkmedia/ijkplayer
    ${IJKROOT_PATH}/ijkmedia/ijksdl
    ${IJK_FFMPEG_ROOT}/include
)

target_link_directories(ijkplayer_napi PRIVATE
    ${IJK_FFMPEG_ROOT}/lib
)
if (EXISTS "${IJK_OPENSSL_ROOT}/lib/libssl.a")
    target_link_directories(ijkplayer_napi PRIVATE ${IJK_OPENSSL_ROOT}/lib)
endif ()

target_link_libraries(ijkplayer_napi
    ijkplayer
    ijksdl
    ace_napi.z
    ace_ndk.z
    native_window
    hilog_ndk.z
    EGL
    GLESv3
    ohaudio
)

# 只导出跨库必需的符号；FFmpeg 静态库与内部实现全部本地化，避免 .dynsym 泄露函数名。
target_link_options(ijksdl PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_LIST_DIR}/export-ijksdl.map"
    "-Wl,--exclude-libs,ALL")
target_link_options(ijkplayer PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_LIST_DIR}/export-ijkplayer.map"
    "-Wl,--exclude-libs,ALL")
target_link_options(ijkplayer_napi PRIVATE
    "-Wl,--exclude-libs,ALL")

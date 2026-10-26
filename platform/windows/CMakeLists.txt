#
# Copyright (c) 2019 befovy <befovy@gmail.com>
#
# This file is part of ijkPlayer.
#
# ijkPlayer is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# ijkPlayer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with ijkPlayer; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

cmake_minimum_required(VERSION 3.6)

project("fplayercore" LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)

message(STATUS "CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
message(STATUS "PROJECT_SOURCE_DIR ${PROJECT_SOURCE_DIR}")

set(IJKROOT_PATH "${PROJECT_SOURCE_DIR}/../..")
get_filename_component(IJKROOT_PATH ${IJKROOT_PATH} ABSOLUTE)
message(STATUS "IJKROOT_PATH ${IJKROOT_PATH}")

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif()
if (${CMAKE_BUILD_TYPE} STREQUAL "Release")
    add_definitions(-DNDEBUG=1)
elseif (${CMAKE_BUILD_TYPE} STREQUAL "Debug")
    add_definitions(-DDEBUG=1)
endif ()

if (CMAKE_SIZEOF_VOID_P EQUAL 8)
    # 64 bits
    message(STATUS "CMAKE SIZEOF POIONT 8")
    set(IJK_X64 on)
    set(IJK_X86 off)
elseif (CMAKE_SIZEOF_VOID_P EQUAL 4)
    # 32 bits
    message(STATUS "cmake sizeof point 4")
    set(IJK_X64 off)
    set(IJK_X86 on)
endif ()

set(IJK_WINDOWS_CONTRIB_PATH ${IJKROOT_PATH}/platform/windows/contrib)

if (IJK_X64)
    if (APPLE)
        # macOS Xcode 工程同样使用 universal 产物（含 arm64 + x86_64）
        set(IJK_FFMPAG_BUILD_DIR ${IJKROOT_PATH}/build/macos/ffmpeg-universal/output)
    else()
        set(IJK_FFMPAG_BUILD_DIR ${IJK_WINDOWS_CONTRIB_PATH}/ffmpeg/x64)
    endif()
elseif (IJK_X86)
    set(IJK_FFMPAG_BUILD_DIR ${IJK_WINDOWS_CONTRIB_PATH}/ffmpeg/x86)
endif ()

include(CMakePrintHelpers)
cmake_print_variables(IJK_FFMPAG_BUILD_DIR)

if (WIN32)
    if (IJK_X64)
        set(IJK_WINDOWS_PTHREAD_BUILD_DIR ${IJK_WINDOWS_CONTRIB_PATH}/pthreads-w32-2-9-1-release/Pre-built.2/lib/x64)
    elseif (IJK_X86)
        set(IJK_WINDOWS_PTHREAD_BUILD_DIR ${IJK_WINDOWS_CONTRIB_PATH}/pthreads-w32-2-9-1-release/Pre-built.2/lib/x86)
    endif ()

    add_definitions(-DHAVE_STRUCT_TIMESPEC)
endif ()

if (WIN32 AND NOT DEFINED IJK_FFMPEG_ROOT)
    if (DEFINED VCPKG_INSTALLED_DIR AND DEFINED VCPKG_TARGET_TRIPLET)
        set(IJK_FFMPEG_ROOT "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}")
    else ()
        set(IJK_FFMPEG_ROOT "${IJK_FFMPAG_BUILD_DIR}")
    endif ()
endif ()

if (WIN32)
    set(IJK_FFMPAG_BUILD_DIR "${IJK_FFMPEG_ROOT}")
endif ()

if (NOT DEFINED IJK_FFMPAG_BUILD_DIR)
    message(FATAL_ERROR "Can not find ffmpeg build output: ${IJK_FFMPAG_BUILD_DIR}")
else ()
    message(STATUS "IJK_FFMPAG_BUILD_DIR:${IJK_FFMPAG_BUILD_DIR}")
endif ()

if (WIN32)
    find_package(SDL2 CONFIG REQUIRED)
    if (TARGET SDL2::SDL2)
        set(IJK_SDL2_TARGET SDL2::SDL2)
    else ()
        set(IJK_SDL2_TARGET SDL2::SDL2-static)
    endif ()
    get_target_property(SDL2_INCLUDE_DIRS ${IJK_SDL2_TARGET} INTERFACE_INCLUDE_DIRECTORIES)
else ()
    find_package(SDL2 REQUIRED)
endif ()

add_definitions(-DUSE_SDL2=1)
include_directories(${SDL2_INCLUDE_DIRS})

add_definitions(-DIJK_WINDOWS_UNI=1)
set(IJK_WINDOWS_UNI ON)

set(FIJKPLAYER_SOURCE
    ${CMAKE_CURRENT_LIST_DIR}/sources/fplayercore.h
    ${CMAKE_CURRENT_LIST_DIR}/sources/fplayercore.c
)

if (WIN32)
    list(APPEND FIJKPLAYER_SOURCE
        ${CMAKE_CURRENT_LIST_DIR}/sources/ffmpeg_application.c
        ${CMAKE_CURRENT_LIST_DIR}/sources/ffmpeg_application.h
        ${CMAKE_CURRENT_LIST_DIR}/sources/ffmpeg_ijkutils.c
    )
endif ()

add_library(fplayercore SHARED ${FIJKPLAYER_SOURCE})

add_subdirectory(../../ijkmedia ijkmedia)

target_include_directories(fplayercore PRIVATE ${IJKROOT_PATH}/ijkmedia)
target_include_directories(fplayercore PRIVATE ${IJK_FFMPAG_BUILD_DIR}/include)
target_include_directories(fplayercore PRIVATE "${IJK_FFMPEG_ROOT}/include")
target_include_directories(fplayercore PRIVATE "${IJK_WINDOWS_PTHREAD_BUILD_DIR}/../../include")

target_link_libraries(fplayercore ijksdl_static ijkplayer_static)

if (WIN32)
    target_compile_options(ijksdl_static PRIVATE /W3 /we4013 /utf-8)
    target_compile_options(ijkplayer_static PRIVATE /W3 /we4013 /utf-8)
    target_compile_options(fplayercore PRIVATE /W3 /we4013 /utf-8)
    target_compile_definitions(ijksdl_static PRIVATE USE_SDL2=1)
    target_compile_definitions(ijkplayer_static PRIVATE USE_SDL2=1)
endif ()

if (WIN32)
    set(FFMPEG_STATIC_INCLUDE_DIRS ${IJK_FFMPEG_ROOT}/include)
    set(FFMPEG_STATIC_LIBRARY_DIRS ${IJK_FFMPEG_ROOT}/lib ${IJK_FFMPEG_ROOT}/bin)
    set(FFMPEG_STATIC_LIBRARIES avformat avcodec swresample swscale avutil)

    cmake_print_variables(FFMPEG_STATIC_INCLUDE_DIRS)
    cmake_print_variables(FFMPEG_STATIC_LIBRARIES)

    target_link_libraries(fplayercore ${IJK_SDL2_TARGET})

    find_library(IJK_PTHREAD_LIBRARY NAMES pthreadVC3 pthreadVC2 pthread
        HINTS "${IJK_FFMPEG_ROOT}/lib" "${IJK_FFMPEG_ROOT}/bin" "${IJK_WINDOWS_PTHREAD_BUILD_DIR}")
    if (IJK_PTHREAD_LIBRARY)
        target_link_libraries(fplayercore ${IJK_PTHREAD_LIBRARY})
    endif ()
elseif (APPLE)
    # 直接使用 universal 静态库，避免 pkg-config 指向单一架构的旧产物
    set(FFMPEG_STATIC_INCLUDE_DIRS ${IJK_FFMPAG_BUILD_DIR}/include)
    set(FFMPEG_STATIC_LIBRARY_DIRS ${IJK_FFMPAG_BUILD_DIR}/lib)
    set(FFMPEG_STATIC_LIBRARIES
        avformat avcodec swresample swscale avutil bz2 z m
        "-framework AudioToolbox" "-framework VideoToolbox"
        "-framework CoreFoundation" "-framework CoreMedia"
        "-framework CoreVideo" "-framework CoreServices"
    )

    cmake_print_variables(FFMPEG_STATIC_INCLUDE_DIRS)
    cmake_print_variables(FFMPEG_STATIC_LIBRARIES)

    target_link_libraries(fplayercore ${SDL2_LIBRARIES})
endif ()

message(STATUS "ffmpeg libs:${FFMPEG_STATIC_LIBRARIES}")

list(REMOVE_ITEM FFMPEG_STATIC_LIBRARIES "ssl")
list(REMOVE_ITEM FFMPEG_STATIC_LIBRARIES "crypto")

cmake_print_variables(FFMPEG_STATIC_LIBRARIES)

target_link_libraries(fplayercore ${FFMPEG_STATIC_LIBRARIES})
target_link_directories(fplayercore PUBLIC ${FFMPEG_STATIC_LIBRARY_DIRS})
if (SRT_FOUND)
    message(STATUS "SRT ${SRT_STATIC_LIBRARIES}")
    target_link_libraries(fplayercore ${SRT_STATIC_LIBRARIES})
    target_link_directories(fplayercore PUBLIC ${SRT_STATIC_LIBRARY_DIRS})
endif()

if(APPLE AND SRT_STATIC_FOUND)
    set_target_properties(fplayercore PROPERTIES LINK_FLAGS "-Wl,-no_compact_unwind")
endif()

target_compile_definitions(fplayercore PRIVATE BUILDING_IJK=1)

if (WIN32)
    target_link_libraries(fplayercore ws2_32 secur32 avrt shlwapi advapi32 shell32 kernel32 user32
        bcrypt crypt32 ncrypt mswsock ole32 uuid gdi32 winmm
        mfplat mfuuid strmiids dwmapi d3d11 d3d12 dxgi dxva2 quartz vfw32)
elseif (APPLE)
    # brew install openssl：按架构选择（/usr/local 为 x86_64，/opt/homebrew 为 arm64）
    if (CMAKE_OSX_ARCHITECTURES MATCHES "arm64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
        set(OPENSSL_ROOT_DIR "/opt/homebrew/opt/openssl@3")
    else()
        set(OPENSSL_ROOT_DIR "/usr/local/opt/openssl")
    endif()
    find_package(OpenSSL REQUIRED)
    target_link_libraries(fplayercore ${OPENSSL_LIBRARIES})
    target_link_libraries(fplayercore z)
    target_link_libraries(fplayercore bz2)

    macro(add_framework appname fwname)
        find_library(FRAMEWORK_${fwname}
                NAMES ${fwname}
                PATHS ${CMAKE_OSX_SYSROOT}/System/Library
                PATH_SUFFIXES Frameworks NO_DEFAULT_PATH)

        if (${FRAMEWORK_${fwname}} STREQUAL FRAMEWORK_${fwname}-NOTFOUND)
            MESSAGE(ERROR ": Framework ${fwname} not found")
        else ()
            target_link_libraries(${appname} "${FRAMEWORK_${fwname}}")
            MESSAGE(STATUS "Framework ${fwname} found")
        endif ()
    endmacro(add_framework)

    add_framework(fplayercore CoreVideo)
    add_framework(fplayercore CoreMedia)
    add_framework(fplayercore VideoToolbox)
    add_framework(fplayercore Security)
endif ()

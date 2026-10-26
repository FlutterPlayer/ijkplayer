#
# Copyright (c) 2019 befovy <befovy@gmail.com>
#
# This file is part of fijkPlayer.
#
# fijkPlayer is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# fijkPlayer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with ijkPlayer; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

cmake_minimum_required(VERSION 3.6)

project("FijkPlayer")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)

add_definitions(-DANDROID)

message(STATUS "CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
message(STATUS "ANDROID_PLATFORM_LEVEL:${ANDROID_PLATFORM_LEVEL}")
message(STATUS "ANDROID_ABI:${ANDROID_ABI}")
message(STATUS "PROJECT_SOURCE_DIR ${PROJECT_SOURCE_DIR}")

set(FIJKROOT_PATH "${PROJECT_SOURCE_DIR}/../../../../../..")
get_filename_component(FIJKROOT_PATH ${FIJKROOT_PATH} ABSOLUTE)
message(STATUS "FIJKROOT_PATH ${FIJKROOT_PATH}")


if (${CMAKE_BUILD_TYPE} STREQUAL "Release")
    add_definitions(-DNDEBUG)
elseif (${CMAKE_BUILD_TYPE} STREQUAL "Debug")
    add_definitions(-DDEBUG)
endif ()

add_compile_options("-Wno-deprecated-declarations")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(ANDROID_CONTRIB_PATH ${FIJKROOT_PATH}/build/android/deps)
message(STATUS "ANDROID_CONTRIB_PATH:${ANDROID_CONTRIB_PATH}")

if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    set(IJK_FFMPAG_BUILD_DIR ${ANDROID_CONTRIB_PATH}/output-arm64)
elseif (${ANDROID_ABI} STREQUAL "x86")
    set(IJK_FFMPAG_BUILD_DIR ${ANDROID_CONTRIB_PATH}/output-x86)
elseif (${ANDROID_ABI} STREQUAL "x86_64")
    set(IJK_FFMPAG_BUILD_DIR ${ANDROID_CONTRIB_PATH}/output-x86_64)
endif ()

if (NOT DEFINED IJK_FFMPAG_BUILD_DIR)
    message(FATAL_ERROR "Can not find ffmpeg build output: ${IJK_FFMPAG_BUILD_DIR}")
else ()
    message(STATUS "IJK_FFMPAG_BUILD_DIR:${IJK_FFMPAG_BUILD_DIR}")
endif ()

# FFmpeg is linked statically into libijkplayer.so so the AAR ships a single
# native library. FFmpeg archives reference each other circularly, hence the
# --start-group/--end-group wrapper. Optional dependencies are only present
# when FFmpeg was configured against them.
set(IJK_FFMPEG_ARCHIVES
    ${IJK_FFMPAG_BUILD_DIR}/lib/libavformat.a
    ${IJK_FFMPAG_BUILD_DIR}/lib/libavcodec.a
    ${IJK_FFMPAG_BUILD_DIR}/lib/libavfilter.a
    ${IJK_FFMPAG_BUILD_DIR}/lib/libswscale.a
    ${IJK_FFMPAG_BUILD_DIR}/lib/libswresample.a
    ${IJK_FFMPAG_BUILD_DIR}/lib/libavutil.a
)

foreach (OPTIONAL_ARCHIVE libssl.a libcrypto.a libsoxr.a libsrt.a)
    if (EXISTS ${IJK_FFMPAG_BUILD_DIR}/lib/${OPTIONAL_ARCHIVE})
        list(APPEND IJK_FFMPEG_ARCHIVES ${IJK_FFMPAG_BUILD_DIR}/lib/${OPTIONAL_ARCHIVE})
    endif ()
endforeach ()

foreach (FF_ARCHIVE ${IJK_FFMPEG_ARCHIVES})
    if (NOT EXISTS ${FF_ARCHIVE})
        message(FATAL_ERROR "Can not find FFmpeg static library: ${FF_ARCHIVE}")
    endif ()
endforeach ()

add_library(ijkffmpeg INTERFACE)
target_include_directories(ijkffmpeg INTERFACE ${IJK_FFMPAG_BUILD_DIR}/include)
target_link_libraries(ijkffmpeg INTERFACE
    # FFmpeg's NEON assembly is not fully PIC; local binding makes the
    # relocations resolvable inside the final shared library.
    "-Wl,-Bsymbolic"
    "-Wl,--start-group"
    ${IJK_FFMPEG_ARCHIVES}
    "-Wl,--end-group"
    z m dl
)

message(STATUE "${CMAKE_LIBRARY_OUTPUT_DIRECTORY} ${PROJECT_BINARY_DIR}")
add_subdirectory(${FIJKROOT_PATH}/ijkmedia ijkmedia)

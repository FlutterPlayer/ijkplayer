#
# Copyright (c) 2019 Befovy <befovy@gmail.com>
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
set(CMAKE_POSITION_INDEPENDENT_CODE ON)


set(BASE_SOURCES
    ijksdl_class.h
    ijksdl_container.h
    ijksdl_log.h

    ijksdl_misc.h
    ijksdl_stdinc.h
    ijksdl_inc_internal.h
    ijksdl_log.c
    ijksdl_log.h
    ijksdl_rectangle.c
    ijksdl_rectangle.h
    ijksdl_aout.c
    ijksdl_aout.h
    ijksdl_aout_internal.h
    ijksdl_audio.c
    ijksdl_audio.h
    ijksdl_error.c
    ijksdl_error.h
    ijksdl_mutex.c
    ijksdl_mutex.h
    ijksdl_stdinc.c
    ijksdl_stdinc.h
    ijksdl_thread.c
    ijksdl_thread.h
    ijksdl_timer.c
    ijksdl_timer.h
    ijksdl_vout.c
    ijksdl_vout.h
    ijksdl_vout_internal.h

    ffmpeg/ijksdl_vout_overlay_ffmpeg.c
    ffmpeg/ijksdl_vout_overlay_ffmpeg.h
    ffmpeg/ijksdl_inc_ffmpeg.h

    dummy/ijksdl_vout_dummy.c
    dummy/ijksdl_vout_dummy.h
    dummy/ijksdl_dummy.h
)

set(SDL_OHOS_SOURCES
    ohos/ijksdl_egl.c
    ohos/ijksdl_egl.h
    ohos/ijksdl_gles2.h
    ohos/ijksdl_ohos.h
    ohos/ijksdl_inc_internal_ohos.h
    ohos/ijksdl_vout_ohos_nativewindow.c
    ohos/ijksdl_vout_ohos_nativewindow.h
    ohos/ijksdl_vout_overlay_ohos_avcodec.c
    ohos/ijksdl_vout_overlay_ohos_avcodec.h
    ohos/ijksdl_aout_ohos.c
    ohos/ijksdl_aout_ohos.h
    ohos/gles2/color.c
    ohos/gles2/common.c
    ohos/gles2/internal.h
    ohos/gles2/renderer.c
    ohos/gles2/renderer_rgb.c
    ohos/gles2/renderer_yuv420p.c
    ohos/gles2/renderer_yuv420sp.c
    ohos/gles2/renderer_yuv444p10le.c
    ohos/gles2/shader.c
    ohos/gles2/fsh/rgb.fsh.c
    ohos/gles2/fsh/yuv420p.fsh.c
    ohos/gles2/fsh/yuv420sp.fsh.c
    ohos/gles2/fsh/yuv444p10le.fsh.c
    ohos/gles2/vsh/mvp.vsh.c
)

set(SDL_ANDROID_EXTRA_SOURCES
    ijksdl_extra_log.c
    ijksdl_extra_log.h
    android/ijksdl_android_jni.c
    android/ijksdl_aout_android_aaudio.c
    android/ijksdl_aout_android_aaudio.h
    android/ijksdl_aout_android_opensles.c
    android/ijksdl_android_image_reader.c
    android/ijksdl_vout_android_vulkan.c
    android/vulkan/fs_vulkan_renderer.c
    android/vulkan/ijksdl_gpu_vulkan.c
)

set(SDL_WINDOWS_UNI_SOURCES
    windows/ijksdl_windows.h
    windows/ijksdl_aout_sdl2_audio.c
    windows/ijksdl_aout_sdl2_audio.h
    windows/ijksdl_vout_uni_callback.c
    windows/ijksdl_vout_uni_callback.h

    windows/ijksdl_vout_sdl2_video.c
    windows/ijksdl_vout_sdl2_video.h
)

set(SDL_MAC_OSX_SOURCES
    ${IJKROOT_PATH}/ijkmedia/ijksdl/apple/ios/ijksdl_thread_ios.h
    ${IJKROOT_PATH}/ijkmedia/ijksdl/apple/ios/ijksdl_thread_ios.m
)

set(IJK_SDL_SOURCES ${BASE_SOURCES})

if (IJK_OHOS)
    set(IJK_SDL_SOURCES ${IJK_SDL_SOURCES} ${SDL_OHOS_SOURCES})
    add_definitions(-D__OHOS__=1)
endif ()

if (ANDROID)
    set(IJK_SDL_SOURCES ${IJK_SDL_SOURCES} ${SDL_ANDROID_EXTRA_SOURCES})
endif ()

if (IJK_WINDOWS_UNI)
    if (NOT WIN32)
        find_package(SDL2 REQUIRED)
    endif ()

    set(IJK_SDL_SOURCES ${IJK_SDL_SOURCES} ${SDL_WINDOWS_UNI_SOURCES})
    if (APPLE AND IJK_WINDOWS_UNI)
        set(IJK_SDL_SOURCES ${IJK_SDL_SOURCES} ${SDL_MAC_OSX_SOURCES})
    endif ()
    add_library(ijksdl_static STATIC ${IJK_SDL_SOURCES})
    set(IJKSDL_LIB_NAME ijksdl_static)

    target_include_directories(ijksdl_static PRIVATE ${SDL2_INCLUDE_DIRS})
    cmake_print_variables(SDL2_INCLUDE_DIRS)

elseif (ANDROID)
    # Static so that the whole native stack ends up in a single libijkplayer.so.
    add_library(ijksdl STATIC ${IJK_SDL_SOURCES})
    set(IJKSDL_LIB_NAME ijksdl)
else ()
    add_library(ijksdl SHARED ${IJK_SDL_SOURCES})
    set(IJKSDL_LIB_NAME ijksdl)
endif ()

target_include_directories(${IJKSDL_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
target_include_directories(${IJKSDL_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/ohos)
target_include_directories(${IJKSDL_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/..)

if (WIN32)
    target_include_directories(${IJKSDL_LIB_NAME} PRIVATE "${IJK_WINDOWS_PTHREAD_BUILD_DIR}/../../include")
endif()

#include ffmpeg header files
target_include_directories(${IJKSDL_LIB_NAME} PRIVATE ${IJK_FFMPAG_BUILD_DIR}/include)

if (NOT WIN32 AND NOT IJK_OHOS)
    target_compile_options(${IJKSDL_LIB_NAME} PUBLIC "-Werror")
endif ()
if (ANDROID)
    # build cpufeatures as a static lib
    # add_library(cpufeatures STATIC
    #        ${ANDROID_NDK}/sources/android/cpufeatures/cpu-features.c)

    # include(AndroidNdkModules)
    # android_ndk_import_module_cpufeatures()
    target_include_directories(${IJKSDL_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../ijkj4a)
endif ()

if (ANDROID)
    target_link_libraries(${IJKSDL_LIB_NAME} ijkffmpeg)
    target_link_libraries(${IJKSDL_LIB_NAME} ijkj4a)
    # target_link_libraries(ijksdl cpufeatures)
    target_link_libraries(${IJKSDL_LIB_NAME} log android mediandk OpenSLES aaudio vulkan)
endif ()

if (IJK_OHOS)
    target_link_libraries(${IJKSDL_LIB_NAME} EGL GLESv3 native_window ohaudio hilog_ndk.z)
endif ()

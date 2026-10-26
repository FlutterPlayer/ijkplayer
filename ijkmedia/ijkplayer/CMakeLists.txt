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

set(BUILD_SOURCES
    ff_fferror.h
    ff_ffinc.h
    ff_ffmsg.h
    ff_ffmsg_queue.h

    ff_cmdutils.c
    ff_cmdutils.h
    ff_ffplay.c
    ff_ffplay.h
    ff_ffplay_debug.h
    ff_ffplay_def.h
    ff_ffplay_options.h

    ff_ffpipeline.c
    ff_ffpipeline.h
    ff_ffpipenode.c
    ff_ffpipenode.h
    ijkmeta.c
    ijkmeta.h

    ijkplayer.c
    ijkplayer.h
    ijkplayer_internal.h

    pipeline/ffpipeline_ffplay.c
    pipeline/ffpipeline_ffplay.h
    pipeline/ffpipenode_ffplay_vdec.c
    pipeline/ffpipenode_ffplay_vdec.h

    ijkavformat/allformats.c
    ijkavformat/ijklivehook.c
    ijkavformat/ijkio.c
    ijkavformat/ijkiomanager.c
    ijkavformat/ijkiocache.c
    ijkavformat/ijkioffio.c
    ijkavformat/ijkioprotocol.c
    ijkavformat/ijkioapplication.c
    ijkavformat/ijkiourlhook.c
    ijkavformat/ijkasync.c
    ijkavformat/ijkurlhook.c
    ijkavformat/ijklongurl.c
    ijkavformat/ijksegment.c

    ijkavutil/ijkdict.c
    ijkavutil/ijkutils.c
    ijkavutil/ijkthreadpool.c
    ijkavutil/ijktree.c
    ijkavutil/ijkfifo.c
    ijkavutil/ijkstl.cpp

)

if(WIN32)
    #list(REMOVE_ITEM BUILD_SOURCES 
        # ijkavformat/ijkiomanager.c
    #)

endif()

set(ANDROID_IJKPLAYER_SOURCES
    android/ffmpeg_api_jni.c
    android/ijkplayer_android.c
    android/ijkplayer_jni.c
    android/pipeline/ffpipeline_android.c
)

set(WINDOWS_UNI_SOURCE
    windows/pipeline_windows.h
    windows/pipeline_windows.c
)

set(OHOS_SOURCES
    ohos/pipeline_ohos.h
    ohos/pipeline_ohos.c
    ohos/ffpipenode_ohos_mediacodec_vdec.h
    ohos/ffpipenode_ohos_mediacodec_vdec.cpp
    ohos/ohos_video_decoder.h
    ohos/ohos_video_decoder.cpp
    ohos/ohos_video_decoder_data.h
    ohos/ohos_video_decoder_data.cpp
    ohos/ohos_video_decoder_Info.h
    ohos/ohos_video_decoder_Info.cpp
)

if (IJK_OHOS)
    set(BUILD_SOURCES ${BUILD_SOURCES} ${OHOS_SOURCES})
    add_definitions(-D__OHOS__=1)
endif ()

if (ANDROID)
    set(BUILD_SOURCES ${BUILD_SOURCES} ${ANDROID_IJKPLAYER_SOURCES})
endif ()


if (IJK_WINDOWS_UNI)
    set(BUILD_SOURCES ${BUILD_SOURCES} ${WINDOWS_UNI_SOURCE})
    add_library(ijkplayer_static STATIC ${BUILD_SOURCES})
    set(IJKPLAYER_LIB_NAME ijkplayer_static)
else ()
    add_library(ijkplayer SHARED ${BUILD_SOURCES})
    set(IJKPLAYER_LIB_NAME ijkplayer)
endif ()

if (IJK_WINDOWS_UNI)
endif ()
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/..)
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ${IJK_FFMPAG_BUILD_DIR}/include)

# message(FATAL_ERROR ${IJK_FFMPAG_BUILD_DIR})

target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ijkavformat)
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ijkavutil)
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE pipeline)
target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../ijkj4a)

if (WIN32)
    target_include_directories(${IJKPLAYER_LIB_NAME} PRIVATE "${IJK_WINDOWS_PTHREAD_BUILD_DIR}/../../include")
endif()

if (NOT IJK_WINDOWS_UNI)
    target_link_libraries(${IJKPLAYER_LIB_NAME} ijksdl)
endif()

if (ANDROID)
    target_link_libraries(${IJKPLAYER_LIB_NAME} ijksoundtouch)
    target_link_libraries(${IJKPLAYER_LIB_NAME} ijkffmpeg)
    target_link_libraries(${IJKPLAYER_LIB_NAME} log)
    target_link_libraries(${IJKPLAYER_LIB_NAME} android)
    # The native stack is linked into this one library; do not re-export
    # symbols that came from static archives (FFmpeg, ijksdl, j4a, libc++).
    target_link_options(${IJKPLAYER_LIB_NAME} PRIVATE "-Wl,--exclude-libs,ALL")
endif ()

if (IJK_OHOS)
    target_link_libraries(${IJKPLAYER_LIB_NAME} ijksdl)
    target_link_libraries(${IJKPLAYER_LIB_NAME} EGL GLESv3 native_window ohaudio hilog_ndk.z)
    target_link_libraries(${IJKPLAYER_LIB_NAME} native_media_codecbase native_media_core native_media_vdec native_media_venc native_buffer deviceinfo_ndk.z)
endif ()

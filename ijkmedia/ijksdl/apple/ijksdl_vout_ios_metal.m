/*
 * ijksdl_vout_ios_metal.m
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "ijksdl_vout_ios_metal.h"

#include <assert.h>
#include "ijksdl/ijksdl_log.h"
#include "ijksdl/ijksdl_vout.h"
#include "ijksdl/ijksdl_vout_internal.h"
#include "ijksdl/ijksdl_fourcc.h"
#include "ijksdl/ffmpeg/ijksdl_vout_overlay_ffmpeg.h"
#include "ijksdl/apple/ios/ijksdl_vout_overlay_videotoolbox.h"
#include "libavutil/pixdesc.h"
#import <MetalKit/MetalKit.h>
#import "ijk_cvpixelbuffer.h"

@implementation FSTilePiece

- (void)dealloc
{
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    if (_avframe) {
        av_frame_free(&self->_avframe);
    }
}

@end

@implementation FSOverlayAttach

- (void)dealloc
{
    if (self.videoPicture) {
        CVPixelBufferRelease(self.videoPicture);
        self.videoPicture = NULL;
    }
    if (self.avframe) {
        av_frame_free(&self->_avframe);
    }
    if (self.videoCVTextures) {
        for (id item in self.videoCVTextures) {
            CVMetalTextureRef texRef = (__bridge CVMetalTextureRef)item;
            if (texRef) {
                CFRelease(texRef);
            }
        }
        self.videoCVTextures = nil;
    }
    self.videoTextures = nil;
    self.tilePieces = nil;
    self.subTexture = nil;
}

- (id)subTexture
{
    return nil;
}

- (BOOL)hasAlpha
{
    if (self.avframe) {
        const AVPixFmtDescriptor* desc = av_pix_fmt_desc_get(self.avframe->format);
        if (desc && (desc->flags & AV_PIX_FMT_FLAG_ALPHA)) {
            return YES;
        }
    }
    return NO;
}

@end

struct SDL_Vout_Opaque {
    __strong id<FSVideoRenderingProtocol> gl_view;
    FSSwPixelBufferPool sw_pool;
};

static enum AVPixelFormat sdl_overlay_format_to_av(Uint32 format)
{
    switch (format) {
    case SDL_FCC_I420:
    case SDL_FCC_YV12:
        return AV_PIX_FMT_YUV420P;
    case SDL_FCC_NV12:
        return AV_PIX_FMT_NV12;
    case SDL_FCC_BGRA:
    case SDL_FCC_RV32:
        return AV_PIX_FMT_BGRA;
    case SDL_FCC_RV24:
        return AV_PIX_FMT_RGB24;
    default:
        return AV_PIX_FMT_NONE;
    }
}

static SDL_VoutOverlay *vout_create_overlay_l(int width, int height, int src_format, SDL_Vout *vout)
{
    switch (src_format) {
    case IJK_AV_PIX_FMT__VIDEO_TOOLBOX:
        return SDL_VoutVideoToolBox_CreateOverlay(width, height, vout);
    default:
        return SDL_VoutFFmpeg_CreateOverlay(width, height, src_format, vout);
    }
}

static SDL_VoutOverlay *vout_create_overlay(int width, int height, int src_format, SDL_Vout *vout)
{
    SDL_LockMutex(vout->mutex);
    SDL_VoutOverlay *overlay = vout_create_overlay_l(width, height, src_format, vout);
    SDL_UnlockMutex(vout->mutex);
    return overlay;
}

static void vout_free_l(SDL_Vout *vout)
{
    if (!vout)
        return;

    SDL_Vout_Opaque *opaque = vout->opaque;
    if (opaque) {
        FSSwPixelBufferPoolRelease(&opaque->sw_pool);
        opaque->gl_view = nil;
    }

    SDL_Vout_FreeInternal(vout);
}

static int vout_display_overlay_l(SDL_Vout *vout, SDL_VoutOverlay *overlay)
{
    SDL_Vout_Opaque *opaque = vout->opaque;
    id<FSVideoRenderingProtocol> gl_view = opaque->gl_view;

    if (!gl_view) {
        ALOGE("vout_display_overlay_l: NULL gl_view\n");
        return -1;
    }

    if (!overlay) {
        //refresh current display
        FSOverlayAttach *attach = [[FSOverlayAttach alloc] init];
        return [gl_view displayAttach:attach] ? 0 : -1;
    }

    if (overlay->w <= 0 || overlay->h <= 0) {
        ALOGE("vout_display_overlay_l: invalid overlay dimensions(%d, %d)\n", overlay->w, overlay->h);
        return -1;
    }

    FSOverlayAttach *attach = [[FSOverlayAttach alloc] init];
    attach.w = overlay->w;
    attach.h = overlay->h;
    attach.sarNum = overlay->sar_num;
    attach.sarDen = overlay->sar_den;
    attach.fps = 0;
    attach.autoZRotate = 0;

    if (overlay->format == SDL_FCC__VTB) {
        //zero copy: the CVPixelBuffer is owned by the overlay, retain it for the renderer
        CVPixelBufferRef pixelBuffer = SDL_VoutOverlayVideoToolBox_GetCVPixelBufferRef(overlay);
        if (!pixelBuffer) {
            ALOGE("vout_display_overlay_l: NULL CVPixelBufferRef\n");
            return -1;
        }
        attach.videoPicture = (CVPixelBufferRef)CVPixelBufferRetain(pixelBuffer);
    } else {
        enum AVPixelFormat av_format = sdl_overlay_format_to_av(overlay->format);
        if (av_format == AV_PIX_FMT_NONE) {
            ALOGE("vout_display_overlay_l: unsupported overlay format %.4s(0x%x)\n", (char *)&overlay->format, overlay->format);
            return -1;
        }

        AVFrame frame;
        memset(&frame, 0, sizeof(frame));
        frame.width  = overlay->w;
        frame.height = overlay->h;
        frame.format = av_format;
        for (int i = 0; i < AV_NUM_DATA_POINTERS; i++) {
            frame.data[i]     = overlay->pixels[i];
            frame.linesize[i] = overlay->pitches[i];
        }
        if (overlay->format == SDL_FCC_YV12) {
            //Y + V + U -> Y + U + V
            uint8_t *tmp_data = frame.data[1];
            frame.data[1] = frame.data[2];
            frame.data[2] = tmp_data;
            int tmp_linesize = frame.linesize[1];
            frame.linesize[1] = frame.linesize[2];
            frame.linesize[2] = tmp_linesize;
        }

        CVPixelBufferPoolRef pool = FSSwPixelBufferPoolEnsure(&opaque->sw_pool, frame.width, frame.height, frame.format);
        CVPixelBufferRef pixelBuffer = FSCVPixelBufferCreateFromAVFrame(&frame, pool);
        if (!pixelBuffer) {
            ALOGE("vout_display_overlay_l: FSCVPixelBufferCreateFromAVFrame failed\n");
            return -1;
        }
        attach.videoPicture = pixelBuffer;
    }

    attach.pixelW = (int)CVPixelBufferGetWidth(attach.videoPicture);
    attach.pixelH = (int)CVPixelBufferGetHeight(attach.videoPicture);

    return [gl_view displayAttach:attach] ? 0 : -1;
}

static int vout_display_overlay(SDL_Vout *vout, SDL_VoutOverlay *overlay)
{
    @autoreleasepool {
        SDL_LockMutex(vout->mutex);
        int retval = vout_display_overlay_l(vout, overlay);
        SDL_UnlockMutex(vout->mutex);
        return retval;
    }
}

SDL_Vout *SDL_VoutIos_Create(void)
{
    SDL_Vout *vout = SDL_Vout_CreateInternal(sizeof(SDL_Vout_Opaque));
    if (!vout)
        return NULL;

    SDL_Vout_Opaque *opaque = vout->opaque;
    opaque->gl_view = nil;
    memset(&opaque->sw_pool, 0, sizeof(opaque->sw_pool));

    vout->create_overlay = vout_create_overlay;
    vout->free_l = vout_free_l;
    vout->display_overlay = vout_display_overlay;

    return vout;
}

static void SDL_VoutIos_SetRenderView_l(SDL_Vout *vout, id<FSVideoRenderingProtocol> view)
{
    SDL_Vout_Opaque *opaque = vout->opaque;

    if (opaque->gl_view == view)
        return;

    opaque->gl_view = view;
}

void SDL_VoutIos_SetRenderView(SDL_Vout *vout, id<FSVideoRenderingProtocol> view)
{
    SDL_LockMutex(vout->mutex);
    SDL_VoutIos_SetRenderView_l(vout, view);
    SDL_UnlockMutex(vout->mutex);
}

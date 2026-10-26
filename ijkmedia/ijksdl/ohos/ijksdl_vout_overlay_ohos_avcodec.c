/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "ijksdl_vout_overlay_ohos_avcodec.h"

#include <assert.h>
#include "../ijksdl_fourcc.h"
#include "../ffmpeg/ijksdl_inc_ffmpeg.h"
#include "../ijksdl_mutex.h"
#include "../ijksdl_vout_internal.h"
#include "../ijksdl_video.h"
#include "ijksdl_vout_ohos_nativewindow.h"

typedef struct SDL_VoutOverlay_Opaque {
    SDL_mutex *mutex;

    SDL_Vout *vout;

    SDL_OhosAVCodecBufferProxy *buffer_proxy;

    Uint16 pitches[AV_NUM_DATA_POINTERS];
    Uint8 *pixels[AV_NUM_DATA_POINTERS];
} SDL_VoutOverlay_Opaque;

static int overlay_lock(SDL_VoutOverlay *overlay)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return SDL_LockMutex(opaque->mutex);
}

static int overlay_unlock(SDL_VoutOverlay *overlay)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return SDL_UnlockMutex(opaque->mutex);
}

static void overlay_unref(SDL_VoutOverlay *overlay)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;

    SDL_VoutOhos_releaseBufferProxyP(opaque->vout, &opaque->buffer_proxy, false);
}

static void overlay_free_l(SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return;

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    if (!opaque)
        return;

    overlay_unref(overlay);

    if (opaque->mutex)
        SDL_DestroyMutex(opaque->mutex);

    SDL_VoutOverlay_FreeInternal(overlay);
}

static SDL_Class g_vout_overlay_ohos_avcodec_class = {
    .name = "OhosAVCodecVoutOverlay",
};

inline static bool check_object(SDL_VoutOverlay *object, const char *func_name)
{
    if (!object || !object->opaque || !object->opaque_class) {
        ALOGE("%s.%s: invalid overlay\n", (object && object->opaque_class) ? object->opaque_class->name : "?", func_name);
        return false;
    }

    if (object->opaque_class != &g_vout_overlay_ohos_avcodec_class) {
        ALOGE("%s.%s: unsupported method\n", object->opaque_class->name, func_name);
        return false;
    }

    return true;
}

static int func_fill_frame(SDL_VoutOverlay *overlay, const AVFrame *frame)
{
    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;

    if (!check_object(overlay, __func__))
        return -1;

    if (frame->format != IJK_AV_PIX_FMT__HOS_AVCODEC) {
        ALOGE("%s: unexpected frame format %d", __func__, frame->format);
        return -1;
    }

    if (opaque->buffer_proxy)
        SDL_VoutOhos_releaseBufferProxyP(opaque->vout, &opaque->buffer_proxy, false);

    opaque->buffer_proxy = (SDL_OhosAVCodecBufferProxy *)frame->opaque;
    if (!opaque->buffer_proxy) {
        ALOGE("%s: HOS_AVCODEC frame missing opaque proxy", __func__);
        return -1;
    }

    overlay->opaque_class = &g_vout_overlay_ohos_avcodec_class;
    overlay->format     = SDL_FCC__HAVC;
    overlay->planes     = 1;
    overlay->pixels[0]  = NULL;
    overlay->pixels[1]  = NULL;
    overlay->pitches[0] = 0;
    overlay->pitches[1] = 0;
    overlay->is_private = 1;

    overlay->w = (int)frame->width;
    overlay->h = (int)frame->height;
    return 0;
}

SDL_VoutOverlay *SDL_VoutOhosAVCodec_CreateOverlay(int width, int height, SDL_Vout *vout)
{
    SDL_VoutOverlay *overlay = SDL_VoutOverlay_CreateInternal(sizeof(SDL_VoutOverlay_Opaque));
    if (!overlay) {
        ALOGE("SDL_VoutOhosAVCodec_CreateOverlay: allocation failed");
        return NULL;
    }

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    opaque->mutex        = SDL_CreateMutex();
    opaque->vout         = vout;
    opaque->buffer_proxy = NULL;

    overlay->opaque_class = &g_vout_overlay_ohos_avcodec_class;
    overlay->format       = SDL_FCC__HAVC;
    overlay->pitches      = opaque->pitches;
    overlay->pixels       = opaque->pixels;
    overlay->w            = width;
    overlay->h            = height;
    overlay->is_private   = 1;

    overlay->free_l       = overlay_free_l;
    overlay->lock         = overlay_lock;
    overlay->unlock       = overlay_unlock;
    overlay->unref        = overlay_unref;
    overlay->func_fill_frame = func_fill_frame;

    if (!opaque->mutex) {
        ALOGE("SDL_CreateMutex failed");
        goto fail;
    }

    return overlay;

fail:
    overlay_free_l(overlay);
    return NULL;
}

bool SDL_VoutOverlayOhosAVCodec_isKindOf(SDL_VoutOverlay *overlay)
{
    return check_object(overlay, __func__);
}

int SDL_VoutOverlayOhosAVCodec_releaseFrame_l(SDL_VoutOverlay *overlay, bool render)
{
    if (!check_object(overlay, __func__))
        return -1;

    SDL_VoutOverlay_Opaque *opaque = overlay->opaque;
    return SDL_VoutOhos_releaseBufferProxyP_l(opaque->vout, &opaque->buffer_proxy, render);
}

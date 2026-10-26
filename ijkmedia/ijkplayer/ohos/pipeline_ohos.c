/*
 * pipeline_ohos.c
 *
 * Copyright (c) 2024 FlutterPlayer
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#include "pipeline_ohos.h"

#include "../pipeline/ffpipeline_ffplay.h"
#include "../pipeline/ffpipenode_ffplay_vdec.h"
#include "../ijkplayer_internal.h"
#include "ffpipenode_ohos_mediacodec_vdec.h"
#include "ijksdl/ohos/ijksdl_ohos.h"
#include "ijksdl/ohos/ijksdl_vout_ohos_nativewindow.h"

IjkMediaPlayer *ijkmp_ohos_create(int (*msg_loop)(void *))
{
    IjkMediaPlayer *mp = ijkmp_create(msg_loop);
    if (!mp)
        return NULL;

    mp->ffplayer->vout = SDL_VoutOHOS_CreateForNativeWindow();
    if (!mp->ffplayer->vout)
        goto fail;

    mp->ffplayer->pipeline = ffpipeline_create_ohos(mp->ffplayer);
    if (!mp->ffplayer->pipeline)
        goto fail;

    return mp;

fail:
    ijkmp_dec_ref_p(&mp);
    return NULL;
}

void ijkmp_ohos_set_surface(IjkMediaPlayer *mp, void *native_window)
{
    if (!mp || !mp->ffplayer || !mp->ffplayer->vout)
        return;

    pthread_mutex_lock(&mp->mutex);
    SDL_VoutOHOS_SetNativeWindow(mp->ffplayer->vout, native_window);
    pthread_mutex_unlock(&mp->mutex);
}

void ijkmp_ohos_set_volume(IjkMediaPlayer *mp, float left, float right)
{
    ijkmp_set_stereo_volume(mp, left, right);
}

static SDL_Aout *func_open_audio_output(IJKFF_Pipeline *pipeline, FFPlayer *ffp)
{
    return SDL_AoutOHOS_Create(ffp);
}

static IJKFF_Pipenode *func_open_video_decoder(IJKFF_Pipeline *pipeline, FFPlayer *ffp)
{
    void *native_window = ffp->vout ? SDL_VoutOHOS_GetNativeWindow(ffp->vout) : NULL;
    if (native_window) {
        IJKFF_Pipenode *node = ffpipenode_create_video_decoder_from_ohos_mediacodec(ffp, pipeline, ffp->vout, native_window);
        if (node)
            return node;
        av_log(ffp, AV_LOG_WARNING, "OHOS hardware video decoder unavailable, using software decoder\n");
    }
    return ffpipenode_create_video_decoder_from_ffplay(ffp);
}

IJKFF_Pipeline *ffpipeline_create_ohos(FFPlayer *ffp)
{
    IJKFF_Pipeline *pipeline = ffpipeline_create_from_ffplay(ffp);
    if (pipeline) {
        pipeline->func_open_audio_output = func_open_audio_output;
        pipeline->func_open_video_decoder = func_open_video_decoder;
    }
    return pipeline;
}

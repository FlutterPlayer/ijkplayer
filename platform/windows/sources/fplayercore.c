/*****************************************************************************
* fplayercore.c
*****************************************************************************
*
* copyright (c) 2019 befovy <befovy@gmail.com>
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


#include "fplayercore.h"
#include "ijkplayer/windows/pipeline_windows.h"
#include "ijkplayer/ff_ffmsg_queue.h"
#include "ijkplayer/ijkmeta.h"

#include "libavutil/imgutils.h"
#include "libavutil/mem.h"
#include "libavutil/pixfmt.h"
#include "libswscale/swscale.h"

#include <stdio.h>
#include <string.h>


struct IjkFFMediaPlayer {
    IjkMediaPlayer *mp;
    void *event_cb_data;
    ijkff_event_cb event_cb;

    IjkFFOverlay overlay;
    void *overlay_cb_data;
    ijkff_overlay_cb overlay_cb;

    struct SwsContext *sws;
    uint8_t *rgba;
    int rgba_capacity;
    uint8_t *rgba_pixels[4];
    uint16_t rgba_pitches[4];
};

static int ijkff_msg_loop(void *arg)
{
    IjkMediaPlayer *mp = arg;
    IjkFFMediaPlayer *fp = ijkmp_set_weak_thiz(mp, NULL);

    while (true) {
        AVMessage msg;

        int retval = ijkmp_get_msg(mp, &msg, 1);
        if (retval < 0)
            break;

        if (fp->event_cb) {
            fp->event_cb(fp->event_cb_data, msg.what, msg.arg1, msg.arg2, msg.obj);
        }
    }

    ijkmp_dec_ref_p(&mp);
    return 0;
}

IjkFFMediaPlayer *ijkff_create(int vout_type)
{
    ijkmp_global_init();
    IjkFFMediaPlayer *fp = mallocz(sizeof(IjkFFMediaPlayer));
    fp->mp = ijkmp_windows_create(ijkff_msg_loop, vout_type);

    ijkmp_set_weak_thiz(fp->mp, fp);
    ijkmp_set_inject_opaque(fp->mp, fp);
    return fp;
}


int ijkff_set_data_source(IjkFFMediaPlayer *fp, const char *url)
{
    assert(fp);
    return ijkmp_set_data_source(fp->mp, url);
}

int ijkff_prepare_async(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_prepare_async(fp->mp);
}

int ijkff_start(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_start(fp->mp);
}

int ijkff_stop(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_stop(fp->mp);
}

int ijkff_pause(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_pause(fp->mp);
}

int ijkff_reset(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_reset(fp->mp);
}

bool ijkff_is_playing(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_is_playing(fp->mp);
}

void ijkff_shutdown(IjkFFMediaPlayer *fp)
{
    assert(fp);
    if (fp->mp) {
        ijkmp_shutdown(fp->mp);
        ijkmp_set_inject_opaque(fp->mp, NULL);
        ijkmp_set_ijkio_inject_opaque(fp->mp, NULL);
        ijkmp_dec_ref(fp->mp);
        fp->mp = NULL;
        fp->event_cb = NULL;
        fp->event_cb_data = NULL;
    }
    if (fp->sws) {
        sws_freeContext(fp->sws);
        fp->sws = NULL;
    }
    av_free(fp->rgba);
    fp->rgba = NULL;
    fp->rgba_capacity = 0;
}

int64_t ijkff_get_current_position(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_get_current_position(fp->mp);
}

int64_t ijkff_get_duration(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_get_duration(fp->mp);
}

int ijkff_seek_to(IjkFFMediaPlayer *fp, int64_t msec)
{
    assert(fp);
    return ijkmp_seek_to(fp->mp, msec);
}

void ijkff_set_loop(IjkFFMediaPlayer *fp, int loop)
{
    assert(fp);
    ijkmp_set_loop(fp->mp, loop);
}

int ijkff_get_loop(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_get_loop(fp->mp);
}


void ijkff_set_speed(IjkFFMediaPlayer *fp, float speed)
{
    assert(fp);
    ijkmp_set_playback_rate(fp->mp, speed);
}

void ijkff_set_playback_volume(IjkFFMediaPlayer *fp, float volume)
{
    assert(fp);
    ijkmp_set_playback_volume(fp->mp, volume);
}

float ijkff_get_playback_volume(IjkFFMediaPlayer *fp)
{
    assert(fp);
    return ijkmp_get_property_float(fp->mp, FFP_PROP_FLOAT_PLAYBACK_VOLUME, 1.0f);
}

void ijkff_set_stream_selected(IjkFFMediaPlayer *fp, int strean, bool selected)
{
    assert(fp);
    ijkmp_set_stream_selected(fp->mp, strean, selected);
}

int ijkff_get_track_info_count(IjkFFMediaPlayer *fp)
{
    assert(fp);
    IjkMediaMeta *meta = ijkmp_get_meta_l(fp->mp);
    if (!meta)
        return -1;

    ijkmeta_lock(meta);
    int count = (int)ijkmeta_get_children_count_l(meta);
    ijkmeta_unlock(meta);
    return count;
}

int ijkff_get_track_info(IjkFFMediaPlayer *fp, int index, IjkFFTrackInfo *info)
{
    assert(fp);
    if (!info || index < 0)
        return -1;

    IjkMediaMeta *meta = ijkmp_get_meta_l(fp->mp);
    if (!meta)
        return -1;

    int ret = -1;
    ijkmeta_lock(meta);
    if (index >= (int)ijkmeta_get_children_count_l(meta))
        goto done;

    IjkMediaMeta *stream = ijkmeta_get_child_l(meta, (size_t)index);
    if (!stream)
        goto done;

    const char *type = ijkmeta_get_string_l(stream, IJKM_KEY_TYPE);
    if (!type)
        type = IJKM_VAL_TYPE__UNKNOWN;

    int64_t selected = -1;
    if (0 == strcmp(type, IJKM_VAL_TYPE__VIDEO)) {
        info->type = IJK_TRACK_TYPE_VIDEO;
        selected = ijkmp_get_property_int64(fp->mp, FFP_PROP_INT64_SELECTED_VIDEO_STREAM, -1);
    } else if (0 == strcmp(type, IJKM_VAL_TYPE__AUDIO)) {
        info->type = IJK_TRACK_TYPE_AUDIO;
        selected = ijkmp_get_property_int64(fp->mp, FFP_PROP_INT64_SELECTED_AUDIO_STREAM, -1);
    } else if (0 == strcmp(type, IJKM_VAL_TYPE__TIMEDTEXT)) {
        info->type = IJK_TRACK_TYPE_TIMEDTEXT;
        selected = ijkmp_get_property_int64(fp->mp, FFP_PROP_INT64_SELECTED_TIMEDTEXT_STREAM, -1);
    } else {
        info->type = IJK_TRACK_TYPE_UNKNOWN;
    }

    info->index = index;
    info->selected = selected == index ? 1 : 0;
    info->sample_rate = (int)ijkmeta_get_int64_l(stream, IJKM_KEY_SAMPLE_RATE, 0);
    info->channel_layout = ijkmeta_get_int64_l(stream, IJKM_KEY_CHANNEL_LAYOUT, 0);

    const char *language = ijkmeta_get_string_l(stream, IJKM_KEY_LANGUAGE);
    const char *codec = ijkmeta_get_string_l(stream, IJKM_KEY_CODEC_NAME);
    const char *codec_long_name = ijkmeta_get_string_l(stream, IJKM_KEY_CODEC_LONG_NAME);
    snprintf(info->language, sizeof(info->language), "%s", language ? language : "");
    snprintf(info->codec, sizeof(info->codec), "%s", codec ? codec : "");
    snprintf(info->codec_long_name, sizeof(info->codec_long_name), "%s", codec_long_name ? codec_long_name : "");
    ret = 0;

done:
    ijkmeta_unlock(meta);
    return ret;
}

float ijkff_get_float_property(IjkFFMediaPlayer *fp, int property, float dfault)
{
    assert(fp);
    return ijkmp_get_property_float(fp->mp, property, dfault);
}

int64_t ijkff_get_long_property(IjkFFMediaPlayer *fp, int property, int64_t dfault)
{
    assert(fp);
    return ijkmp_get_property_int64(fp->mp, property, dfault);
}


void ijkff_set_option(IjkFFMediaPlayer *fp, const char *value, const char *key, int category)
{
    assert(fp);
    ijkmp_set_option(fp->mp, category, key, value);
}

void ijkff_set_int_option(IjkFFMediaPlayer *fp, int64_t value, const char *key, int category)
{
    assert(fp);
    ijkmp_set_option_int(fp->mp, category, key, value);
}

void ijkff_set_window(IjkFFMediaPlayer *fp, void *window)
{
    assert(fp);
    ijkmp_set_window(fp->mp, window);
}

void ijkff_set_event_cb(IjkFFMediaPlayer *fp, void *userdata, ijkff_event_cb cb)
{
    assert(fp);
    fp->event_cb_data = userdata;
    fp->event_cb = cb;
}

int ijkplayer_overlay_draw(void *userdata,
    int w, int h, int sar_num, int sar_den,
    int planes, uint16_t *linesize, uint8_t **pixels)
{
    IjkFFMediaPlayer *fp = userdata;
    int ret = -1;
    if (!fp->mp || !fp->overlay_cb || w <= 0 || h <= 0 || !pixels)
        return ret;

    IjkFFOverlay *overlay = &(fp->overlay);
    overlay->w = w;
    overlay->h = h;
    overlay->sar_num = sar_num;
    overlay->sar_den = sar_den;

    if (planes > 1) {
        enum AVPixelFormat src_format = AV_PIX_FMT_YUV420P;
        if (planes == 2)
            src_format = AV_PIX_FMT_NV12;
        else if (planes == 4)
            src_format = AV_PIX_FMT_YUVA420P;

        int src_linesize[4] = { 0, 0, 0, 0 };
        for (int i = 0; i < planes && i < 4; ++i)
            src_linesize[i] = linesize ? linesize[i] : 0;

        fp->sws = sws_getCachedContext(fp->sws, w, h, src_format,
            w, h, AV_PIX_FMT_RGBA, SWS_BILINEAR, NULL, NULL, NULL);
        const int rgba_size = w * h * 4;
        if (fp->sws && rgba_size > fp->rgba_capacity) {
            av_free(fp->rgba);
            fp->rgba = av_malloc(rgba_size);
            fp->rgba_capacity = fp->rgba ? rgba_size : 0;
        }
        if (fp->sws && fp->rgba) {
            fp->rgba_pixels[0] = fp->rgba;
            fp->rgba_pitches[0] = (uint16_t)(w * 4);
            uint8_t *dst_data[4] = { fp->rgba, NULL, NULL, NULL };
            int dst_linesize[4] = { w * 4, 0, 0, 0 };
            if (sws_scale(fp->sws, (const uint8_t * const *)pixels,
                    src_linesize, 0, h, dst_data, dst_linesize) > 0) {
                overlay->planes = 1;
                overlay->pitches = fp->rgba_pitches;
                overlay->pixels = fp->rgba_pixels;
                fp->overlay_cb(fp->overlay_cb_data, overlay);
                ret = 0;
            }
        }
        return ret;
    }

    overlay->planes = planes;
    overlay->pitches = linesize;
    overlay->pixels = pixels;
    fp->overlay_cb(fp->overlay_cb_data, overlay);
    return 0;
}

void ijkff_set_overlay_cb(IjkFFMediaPlayer *fp, void *userdata, ijkff_overlay_cb cb)
{
    assert(fp);
    memset(&(fp->overlay), 0, sizeof(IjkFFOverlay));
    fp->overlay_cb = cb;
    fp->overlay_cb_data = userdata;
    ijkmp_set_video_callback(fp->mp, fp, ijkplayer_overlay_draw);
    ALOGI("fp(%p) ijkff_set_overlay_cb\n", fp);
}

void ijkff_log_level(int level)
{
    ijkmp_global_set_log_level(level);
}

IJK_API void ijkff_global_init()
{
    ijkmp_global_init();
}


const char *ijkff_version()
{
    return ijkmp_version();
}

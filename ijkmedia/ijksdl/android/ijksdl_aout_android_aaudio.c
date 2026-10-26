/*****************************************************************************
 * ijksdl_aout_android_aaudio.c
 *****************************************************************************
 *
 * Copyright (c) 2026 bileskou
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

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#include <aaudio/AAudio.h>

#include "../ijksdl_inc_internal.h"
#include "../ijksdl_thread.h"
#include "../ijksdl_timer.h"
#include "../ijksdl_aout_internal.h"
#include "ijksdl_aout_android_aaudio.h"

#define AAUDIO_BUFLEN_MS         10
#define AAUDIO_WRITE_TIMEOUT_NS  100000000LL

static SDL_Class g_aaudio_class = {
    .name = "AAudio",
};

typedef struct SDL_Aout_Opaque {
    SDL_cond  *wakeup_cond;
    SDL_mutex *wakeup_mutex;

    SDL_Thread *audio_tid;

    SDL_AudioSpec spec;
    int           bytes_per_frame;
    int           frames_per_buffer;
    int           bytes_per_buffer;

    AAudioStream *stream;
    int           audio_session_id;

    uint8_t      *buffer;

    volatile bool abort_request;
    volatile bool pause_on;
    volatile bool need_flush;

    SDL_Aout *fallback;
    SDL_Aout *delegate;
    bool      aaudio_failed;
} SDL_Aout_Opaque;

static int aaudio_get_session_id(AAudioStream *stream)
{
    if (!stream)
        return 0;

    return (int) AAudioStream_getSessionId(stream);
}

static AAudioStream *aaudio_create_stream(int sample_rate, int channels, aaudio_performance_mode_t mode)
{
    AAudioStreamBuilder *builder = NULL;
    AAudioStream        *stream  = NULL;

    if (AAudio_createStreamBuilder(&builder) != AAUDIO_OK)
        return NULL;

    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setChannelCount(builder, channels);
    AAudioStreamBuilder_setSampleRate(builder, sample_rate);
    AAudioStreamBuilder_setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
    AAudioStreamBuilder_setPerformanceMode(builder, mode);

    aaudio_result_t result = AAudioStreamBuilder_openStream(builder, &stream);
    AAudioStreamBuilder_delete(builder);
    if (result != AAUDIO_OK) {
        ALOGW("AAudio: openStream(%d Hz, %d ch, mode %d) failed: %s",
              sample_rate, channels, (int) mode, AAudio_convertResultToText(result));
        return NULL;
    }

    return stream;
}

static void aaudio_close_stream(SDL_Aout_Opaque *opaque)
{
    if (opaque->stream) {
        AAudioStream_requestStop(opaque->stream);
        AAudioStream_close(opaque->stream);
        opaque->stream = NULL;
    }
}

static void aaudio_wait_for_state(AAudioStream *stream, aaudio_stream_state_t state)
{
    aaudio_stream_state_t next_state = AAUDIO_STREAM_STATE_UNINITIALIZED;

    if (AAudioStream_getState(stream) == state)
        AAudioStream_waitForStateChange(stream, state, &next_state, AAUDIO_WRITE_TIMEOUT_NS);
}

static void aaudio_request_pause(AAudioStream *stream)
{
    aaudio_stream_state_t state;

    if (!stream)
        return;

    state = AAudioStream_getState(stream);
    if (state == AAUDIO_STREAM_STATE_STARTED || state == AAUDIO_STREAM_STATE_STARTING) {
        AAudioStream_requestPause(stream);
        aaudio_wait_for_state(stream, AAUDIO_STREAM_STATE_PAUSING);
    }
}

static void aaudio_flush_l(SDL_Aout_Opaque *opaque)
{
    if (!opaque->stream)
        return;

    aaudio_request_pause(opaque->stream);
    AAudioStream_requestFlush(opaque->stream);
    aaudio_wait_for_state(opaque->stream, AAUDIO_STREAM_STATE_FLUSHING);

    if (!opaque->pause_on)
        AAudioStream_requestStart(opaque->stream);
}

static bool aaudio_reopen(SDL_Aout_Opaque *opaque)
{
    AAudioStream *stream = aaudio_create_stream(opaque->spec.freq, opaque->spec.channels,
                                                AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    if (!stream)
        stream = aaudio_create_stream(opaque->spec.freq, opaque->spec.channels,
                                      AAUDIO_PERFORMANCE_MODE_NONE);
    if (!stream)
        return false;

    opaque->stream = stream;
    if (!opaque->pause_on && !opaque->abort_request)
        AAudioStream_requestStart(stream);

    return true;
}

static bool aaudio_write_buffer(SDL_Aout_Opaque *opaque)
{
    const int bytes_per_frame = opaque->bytes_per_frame;
    int frames_left = opaque->bytes_per_buffer / bytes_per_frame;
    int frames_written = 0;

    while (frames_left > 0 && !opaque->abort_request) {
        aaudio_result_t result = AAudioStream_write(opaque->stream,
                opaque->buffer + frames_written * bytes_per_frame,
                frames_left, AAUDIO_WRITE_TIMEOUT_NS);
        if (result > 0) {
            frames_written += result;
            frames_left    -= result;
        } else if (result == AAUDIO_ERROR_TIMEOUT) {
            if (opaque->pause_on)
                return true;
        } else if (result == AAUDIO_ERROR_DISCONNECTED) {
            ALOGW("AAudio: stream disconnected, reopening");
            aaudio_close_stream(opaque);
            if (!aaudio_reopen(opaque))
                return false;
            return true;
        } else {
            ALOGE("AAudio: write failed: %s", AAudio_convertResultToText(result));
            aaudio_close_stream(opaque);
            if (!aaudio_reopen(opaque))
                return false;
            return true;
        }
    }

    return true;
}

static int aout_thread_n(SDL_Aout *aout)
{
    SDL_Aout_Opaque *opaque = aout->opaque;
    SDL_AudioCallback audio_cblk = opaque->spec.callback;
    void *userdata = opaque->spec.userdata;

    SDL_SetThreadPriority(SDL_THREAD_PRIORITY_HIGH);

    while (!opaque->abort_request) {
        SDL_LockMutex(opaque->wakeup_mutex);
        if (!opaque->abort_request && opaque->pause_on) {
            aaudio_request_pause(opaque->stream);
            while (!opaque->abort_request && opaque->pause_on)
                SDL_CondWaitTimeout(opaque->wakeup_cond, opaque->wakeup_mutex, 1000);

            if (!opaque->abort_request && !opaque->pause_on) {
                if (opaque->need_flush) {
                    opaque->need_flush = 0;
                    aaudio_flush_l(opaque);
                }
                if (opaque->stream)
                    AAudioStream_requestStart(opaque->stream);
            }
        }

        if (opaque->need_flush) {
            opaque->need_flush = 0;
            aaudio_flush_l(opaque);
        }
        SDL_UnlockMutex(opaque->wakeup_mutex);

        if (opaque->abort_request)
            break;

        audio_cblk(userdata, opaque->buffer, opaque->bytes_per_buffer);

        SDL_LockMutex(opaque->wakeup_mutex);
        bool flush_after_fill = opaque->need_flush;
        if (flush_after_fill)
            opaque->need_flush = 0;
        SDL_UnlockMutex(opaque->wakeup_mutex);

        if (flush_after_fill) {
            aaudio_flush_l(opaque);
            continue;
        }

        if (!opaque->stream) {
            if (!aaudio_reopen(opaque))
                SDL_Delay(100);
            continue;
        }

        if (!aaudio_write_buffer(opaque)) {
            if (!opaque->abort_request)
                SDL_Delay(100);
        }
    }

    return 0;
}

static int aout_thread(void *arg)
{
    return aout_thread_n(arg);
}

static void aout_close_audio(SDL_Aout *aout)
{
    SDL_Aout_Opaque *opaque = aout->opaque;
    if (!opaque)
        return;

    SDL_LockMutex(opaque->wakeup_mutex);
    opaque->abort_request = true;
    SDL_CondSignal(opaque->wakeup_cond);
    SDL_UnlockMutex(opaque->wakeup_mutex);

    if (opaque->audio_tid) {
        SDL_WaitThread(opaque->audio_tid, NULL);
        opaque->audio_tid = NULL;
    }

    aaudio_close_stream(opaque);
    freep((void **) &opaque->buffer);

    if (opaque->delegate) {
        SDL_AoutCloseAudio(opaque->delegate);
        opaque->delegate = NULL;
    }
}

static void aout_free_l(SDL_Aout *aout)
{
    if (!aout)
        return;

    aout_close_audio(aout);

    SDL_Aout_Opaque *opaque = aout->opaque;
    if (opaque->fallback)
        SDL_AoutFreeP(&opaque->fallback);

    SDL_DestroyCondP(&opaque->wakeup_cond);
    SDL_DestroyMutexP(&opaque->wakeup_mutex);

    SDL_Aout_FreeInternal(aout);
}

static void aout_pause_audio(SDL_Aout *aout, int pause_on)
{
    SDL_Aout_Opaque *opaque = aout->opaque;

    if (opaque->delegate) {
        SDL_AoutPauseAudio(opaque->delegate, pause_on);
        return;
    }

    SDL_LockMutex(opaque->wakeup_mutex);
    opaque->pause_on = pause_on;
    if (!pause_on)
        SDL_CondSignal(opaque->wakeup_cond);
    SDL_UnlockMutex(opaque->wakeup_mutex);
}

static void aout_flush_audio(SDL_Aout *aout)
{
    SDL_Aout_Opaque *opaque = aout->opaque;

    if (opaque->delegate) {
        SDL_AoutFlushAudio(opaque->delegate);
        return;
    }

    SDL_LockMutex(opaque->wakeup_mutex);
    opaque->need_flush = true;
    SDL_CondSignal(opaque->wakeup_cond);
    SDL_UnlockMutex(opaque->wakeup_mutex);
}

static double aout_get_latency_seconds(SDL_Aout *aout)
{
    SDL_Aout_Opaque *opaque = aout->opaque;

    if (opaque->delegate)
        return SDL_AoutGetLatencySeconds(opaque->delegate);

    if (opaque->stream) {
        int32_t frames = AAudioStream_getBufferSizeInFrames(opaque->stream);
        int32_t rate   = AAudioStream_getSampleRate(opaque->stream);
        if (frames > 0 && rate > 0)
            return (double) frames / rate;
    }

    return opaque->spec.freq > 0
        ? (double) opaque->frames_per_buffer / opaque->spec.freq
        : 0.0;
}

static int aout_get_audio_session_id(SDL_Aout *aout)
{
    SDL_Aout_Opaque *opaque = aout->opaque;

    if (opaque->delegate)
        return SDL_AoutGetAudioSessionId(opaque->delegate);

    return opaque->audio_session_id;
}

static int aout_open_audio(SDL_Aout *aout, const SDL_AudioSpec *desired, SDL_AudioSpec *obtained)
{
    SDL_Aout_Opaque *opaque = aout->opaque;
    AAudioStream    *stream = NULL;
    int              actual_rate;
    int              actual_channels;
    int              buffer_size;
    aaudio_format_t  actual_format;
    aaudio_result_t  result;

    assert(desired);

    if (opaque->aaudio_failed || opaque->delegate)
        return SDL_AoutOpenAudio(opaque->fallback, desired, obtained);

    if (desired->format != AUDIO_S16SYS || (desired->channels != 1 && desired->channels != 2)) {
        ALOGE("AAudio: unsupported spec (format 0x%x, channels %d)",
              (int) desired->format, desired->channels);
        goto fallback;
    }

    opaque->spec = *desired;

    stream = aaudio_create_stream(desired->freq, desired->channels, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    if (!stream)
        stream = aaudio_create_stream(desired->freq, desired->channels, AAUDIO_PERFORMANCE_MODE_NONE);
    if (!stream)
        goto fallback;

    actual_rate     = AAudioStream_getSampleRate(stream);
    actual_channels = AAudioStream_getChannelCount(stream);
    actual_format   = AAudioStream_getFormat(stream);
    if (actual_format != AAUDIO_FORMAT_PCM_I16 || actual_rate <= 0 || actual_channels < 1) {
        ALOGE("AAudio: unsupported stream (format %d, %d Hz, %d ch)",
              (int) actual_format, actual_rate, actual_channels);
        AAudioStream_close(stream);
        goto fallback;
    }

    opaque->stream           = stream;
    opaque->spec.freq        = actual_rate;
    opaque->spec.channels    = actual_channels;
    opaque->audio_session_id = aaudio_get_session_id(stream);

    opaque->bytes_per_frame    = actual_channels * 2;
    opaque->frames_per_buffer  = actual_rate * AAUDIO_BUFLEN_MS / 1000;
    if (opaque->frames_per_buffer <= 0)
        opaque->frames_per_buffer = 256;
    opaque->bytes_per_buffer   = opaque->frames_per_buffer * opaque->bytes_per_frame;
    AAudioStream_setBufferSizeInFrames(stream, opaque->frames_per_buffer * 2);

    opaque->buffer = malloc(opaque->bytes_per_buffer);
    if (!opaque->buffer) {
        aaudio_close_stream(opaque);
        goto fallback;
    }

    if (obtained) {
        *obtained          = *desired;
        obtained->format   = AUDIO_S16SYS;
        obtained->freq     = actual_rate;
        obtained->channels = actual_channels;
        obtained->silence  = 0;
        buffer_size        = AAudioStream_getBufferSizeInFrames(stream) * opaque->bytes_per_frame;
        obtained->size     = buffer_size > 0 ? buffer_size : opaque->bytes_per_buffer;
    }

    opaque->pause_on      = true;
    opaque->abort_request = false;
    opaque->audio_tid     = SDL_CreateThread(aout_thread, "ff_aout_aaudio", aout);
    if (!opaque->audio_tid) {
        aaudio_close_stream(opaque);
        freep((void **) &opaque->buffer);
        goto fallback;
    }

    buffer_size = AAudioStream_getBufferSizeInFrames(stream) * opaque->bytes_per_frame;
    return buffer_size > 0 ? buffer_size : opaque->bytes_per_buffer;

fallback:
    if (opaque->fallback) {
        ALOGW("AAudio: falling back to OpenSL ES");
        opaque->aaudio_failed = true;
        opaque->delegate      = opaque->fallback;
        return SDL_AoutOpenAudio(opaque->fallback, desired, obtained);
    }

    return -1;
}

SDL_Aout *SDL_AoutAndroid_CreateForAAudio(SDL_Aout *fallback)
{
    SDL_Aout *aout = SDL_Aout_CreateInternal(sizeof(SDL_Aout_Opaque));
    if (!aout)
        return NULL;

    SDL_Aout_Opaque *opaque = aout->opaque;
    opaque->wakeup_cond = SDL_CreateCond();
    opaque->wakeup_mutex = SDL_CreateMutex();
    opaque->fallback = fallback;
    opaque->audio_session_id = 0;

    if (!opaque->wakeup_cond || !opaque->wakeup_mutex)
        goto fail;

    aout->free_l      = aout_free_l;
    aout->opaque_class = &g_aaudio_class;
    aout->open_audio  = aout_open_audio;
    aout->pause_audio = aout_pause_audio;
    aout->flush_audio = aout_flush_audio;
    aout->close_audio = aout_close_audio;
    aout->func_get_latency_seconds = aout_get_latency_seconds;
    aout->func_get_audio_session_id = aout_get_audio_session_id;

    return aout;

fail:
    SDL_DestroyCondP(&opaque->wakeup_cond);
    SDL_DestroyMutexP(&opaque->wakeup_mutex);
    SDL_Aout_FreeInternal(aout);
    return NULL;
}

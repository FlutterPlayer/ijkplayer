/*
 * ijkplayer_napi.cpp
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

#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <hilog/log.h>

#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>

extern "C" {
#include "ff_ffmsg.h"
#include "ijkplayer.h"
#include "ohos/pipeline_ohos.h"
}

#define LOG_TAG "ijkplayer_napi"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, LOG_TAG, __VA_ARGS__)

namespace {

struct PlayerContext {
    std::string id;
    IjkMediaPlayer *mp = nullptr;
    OHNativeWindow *window = nullptr;
    napi_threadsafe_function message_callback = nullptr;
};

struct MessageData {
    int what;
    int arg1;
    int arg2;
    std::string obj;
};

std::map<std::string, PlayerContext *> g_players;
std::mutex g_player_mutex;

PlayerContext *find_player(const std::string &id)
{
    std::lock_guard<std::mutex> lock(g_player_mutex);
    auto it = g_players.find(id);
    return it == g_players.end() ? nullptr : it->second;
}

void deliver_message(napi_env env, napi_value js_cb, void *context, void *data)
{
    MessageData *message = static_cast<MessageData *>(data);
    if (!env || !js_cb || !message)
        return;

    napi_value event;
    napi_create_object(env, &event);

    napi_value what;
    napi_create_int32(env, message->what, &what);
    napi_set_named_property(env, event, "what", what);

    napi_value arg1;
    napi_create_int32(env, message->arg1, &arg1);
    napi_set_named_property(env, event, "arg1", arg1);

    napi_value arg2;
    napi_create_int32(env, message->arg2, &arg2);
    napi_set_named_property(env, event, "arg2", arg2);

    napi_value obj;
    napi_create_string_utf8(env, message->obj.c_str(), message->obj.size(), &obj);
    napi_set_named_property(env, event, "obj", obj);

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, js_cb, 1, &event, nullptr);
    delete message;
}

int player_message_loop(void *opaque)
{
    // ijkmp_prepare_async starts this thread with the IjkMediaPlayer*, not the
    // PlayerContext*. Resolve the context through weak_thiz once; keep the
    // callback local so releasing the context cannot race with this loop.
    IjkMediaPlayer *mp = static_cast<IjkMediaPlayer *>(opaque);
    PlayerContext *ctx = static_cast<PlayerContext *>(ijkmp_get_weak_thiz(mp));
    napi_threadsafe_function callback = ctx ? ctx->message_callback : nullptr;
    while (true) {
        AVMessage msg;
        int ret = ijkmp_get_msg(mp, &msg, 1);
        if (ret <= 0)
            break;

        if (callback) {
            MessageData *data = new MessageData();
            data->what = msg.what;
            data->arg1 = msg.arg1;
            data->arg2 = msg.arg2;
            if (msg.obj)
                data->obj.assign(static_cast<const char *>(msg.obj), msg.len);
            napi_call_threadsafe_function(callback, data, napi_tsfn_nonblocking);
        }
        msg_free_res(&msg);
    }
    return 0;
}

napi_value make_undefined(napi_env env)
{
    napi_value value;
    napi_get_undefined(env, &value);
    return value;
}

bool get_string_arg(napi_env env, napi_value value, std::string *out)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok)
        return false;
    out->resize(length);
    return napi_get_value_string_utf8(env, value, &(*out)[0], length + 1, &length) == napi_ok;
}

bool get_number_arg(napi_env env, napi_value value, double *out)
{
    return napi_get_value_double(env, value, out) == napi_ok;
}

int option_category_from_string(const std::string &category)
{
    return std::atoi(category.c_str());
}

PlayerContext *player_from_args(napi_env env, napi_value *argv, size_t argc)
{
    std::string id;
    if (argc < 1 || !get_string_arg(env, argv[0], &id))
        return nullptr;
    return find_player(id);
}

napi_value js_create(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string id;
    if (argc < 1 || !get_string_arg(env, argv[0], &id)) {
        napi_throw_error(env, nullptr, "create requires a player id");
        return make_undefined(env);
    }

    if (find_player(id))
        return make_undefined(env);

    PlayerContext *ctx = new PlayerContext();
    ctx->id = id;
    ctx->mp = ijkmp_ohos_create(player_message_loop);
    if (!ctx->mp) {
        delete ctx;
        napi_throw_error(env, nullptr, "failed to create ijkplayer");
        return make_undefined(env);
    }
    ijkmp_set_weak_thiz(ctx->mp, ctx);

    std::lock_guard<std::mutex> lock(g_player_mutex);
    g_players[id] = ctx;
    return make_undefined(env);
}

napi_value js_release(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string id;
    if (argc < 1 || !get_string_arg(env, argv[0], &id))
        return make_undefined(env);

    PlayerContext *ctx = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_player_mutex);
        auto it = g_players.find(id);
        if (it != g_players.end()) {
            ctx = it->second;
            g_players.erase(it);
        }
    }
    if (!ctx)
        return make_undefined(env);

    if (ctx->mp) {
        ijkmp_shutdown(ctx->mp);
        ijkmp_dec_ref_p(&ctx->mp);
    }
    if (ctx->window) {
        OH_NativeWindow_DestroyNativeWindow(ctx->window);
        ctx->window = nullptr;
    }
    if (ctx->message_callback) {
        napi_release_threadsafe_function(ctx->message_callback, napi_tsfn_release);
        ctx->message_callback = nullptr;
    }
    delete ctx;
    return make_undefined(env);
}

napi_value js_set_message_callback(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string id;
    if (argc < 2 || !get_string_arg(env, argv[0], &id))
        return make_undefined(env);
    PlayerContext *ctx = find_player(id);
    if (!ctx)
        return make_undefined(env);

    if (ctx->message_callback) {
        napi_release_threadsafe_function(ctx->message_callback, napi_tsfn_release);
        ctx->message_callback = nullptr;
    }

    napi_valuetype type;
    napi_typeof(env, argv[1], &type);
    if (type != napi_function)
        return make_undefined(env);

    napi_value name;
    napi_create_string_utf8(env, "ijkplayerMessage", NAPI_AUTO_LENGTH, &name);
    napi_create_threadsafe_function(env, argv[1], nullptr, name, 0, 4, nullptr, nullptr, ctx,
                                    deliver_message, &ctx->message_callback);
    return make_undefined(env);
}

napi_value js_set_surface_id(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string id;
    double surface_id = 0;
    if (argc < 2 || !get_string_arg(env, argv[0], &id) || !get_number_arg(env, argv[1], &surface_id))
        return make_undefined(env);
    PlayerContext *ctx = find_player(id);
    if (!ctx)
        return make_undefined(env);

    if (ctx->window) {
        ijkmp_ohos_set_surface(ctx->mp, nullptr);
        OH_NativeWindow_DestroyNativeWindow(ctx->window);
        ctx->window = nullptr;
    }
    if (surface_id <= 0)
        return make_undefined(env);

    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(static_cast<uint64_t>(surface_id), &ctx->window) != 0) {
        LOGE("failed to create native window from surface id %f", surface_id);
        ctx->window = nullptr;
        return make_undefined(env);
    }
    ijkmp_ohos_set_surface(ctx->mp, ctx->window);
    return make_undefined(env);
}

napi_value js_set_data_source(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string url;
    if (!ctx || argc < 2 || !get_string_arg(env, argv[1], &url))
        return make_undefined(env);
    ijkmp_set_data_source(ctx->mp, url.c_str());
    return make_undefined(env);
}

napi_value js_set_option(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string category, key, value;
    if (!ctx || argc < 4 || !get_string_arg(env, argv[1], &category) ||
        !get_string_arg(env, argv[2], &key) || !get_string_arg(env, argv[3], &value))
        return make_undefined(env);
    ijkmp_set_option(ctx->mp, option_category_from_string(category), key.c_str(), value.c_str());
    return make_undefined(env);
}

napi_value js_set_option_long(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string category, key, value;
    if (!ctx || argc < 4 || !get_string_arg(env, argv[1], &category) ||
        !get_string_arg(env, argv[2], &key) || !get_string_arg(env, argv[3], &value))
        return make_undefined(env);
    ijkmp_set_option_int(ctx->mp, option_category_from_string(category), key.c_str(), std::atoll(value.c_str()));
    return make_undefined(env);
}

napi_value js_prepare_async(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    if (ctx)
        ijkmp_prepare_async(ctx->mp);
    return make_undefined(env);
}

napi_value js_start(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    if (ctx)
        ijkmp_start(ctx->mp);
    return make_undefined(env);
}

napi_value js_pause(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    if (ctx)
        ijkmp_pause(ctx->mp);
    return make_undefined(env);
}

napi_value js_stop(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    if (ctx)
        ijkmp_stop(ctx->mp);
    return make_undefined(env);
}

napi_value js_reset(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    if (ctx)
        ijkmp_reset(ctx->mp);
    return make_undefined(env);
}

napi_value js_seek_to(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string msec;
    if (ctx && argc >= 2 && get_string_arg(env, argv[1], &msec))
        ijkmp_seek_to(ctx->mp, std::atol(msec.c_str()));
    return make_undefined(env);
}

napi_value js_set_volume(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string left, right;
    if (ctx && argc >= 3 && get_string_arg(env, argv[1], &left) && get_string_arg(env, argv[2], &right))
        ijkmp_ohos_set_volume(ctx->mp, std::atof(left.c_str()), std::atof(right.c_str()));
    return make_undefined(env);
}

napi_value js_set_loop_count(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    double loop = 0;
    if (ctx && argc >= 2 && get_number_arg(env, argv[1], &loop))
        ijkmp_set_loop(ctx->mp, static_cast<int>(loop));
    return make_undefined(env);
}

napi_value js_set_speed(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    std::string speed;
    if (ctx && argc >= 2 && get_string_arg(env, argv[1], &speed))
        ijkmp_set_property_float(ctx->mp, FFP_PROP_FLOAT_PLAYBACK_RATE, std::atof(speed.c_str()));
    return make_undefined(env);
}

napi_value js_get_current_position(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    napi_value result;
    napi_create_int64(env, ctx ? ijkmp_get_current_position(ctx->mp) : 0, &result);
    return result;
}

napi_value js_get_duration(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    napi_value result;
    napi_create_int64(env, ctx ? ijkmp_get_duration(ctx->mp) : 0, &result);
    return result;
}

napi_value js_get_track_info(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);

    napi_value result;
    IjkMediaMeta *meta = ctx ? ijkmp_get_meta_l(ctx->mp) : nullptr;
    if (!meta) {
        napi_create_array_with_length(env, 0, &result);
        return result;
    }

    int64_t selectedVideo = ijkmp_get_property_int64(ctx->mp, FFP_PROP_INT64_SELECTED_VIDEO_STREAM, -1);
    int64_t selectedAudio = ijkmp_get_property_int64(ctx->mp, FFP_PROP_INT64_SELECTED_AUDIO_STREAM, -1);
    int64_t selectedTimedText = ijkmp_get_property_int64(ctx->mp, FFP_PROP_INT64_SELECTED_TIMEDTEXT_STREAM, -1);

    ijkmeta_lock(meta);
    size_t count = ijkmeta_get_children_count_l(meta);
    napi_create_array_with_length(env, count, &result);
    for (size_t i = 0; i < count; ++i) {
        IjkMediaMeta *stream = ijkmeta_get_child_l(meta, i);
        if (!stream)
            continue;

        const char *type = ijkmeta_get_string_l(stream, IJKM_KEY_TYPE);
        if (!type)
            type = IJKM_VAL_TYPE__UNKNOWN;
        int64_t selected = -1;
        if (0 == std::strcmp(type, IJKM_VAL_TYPE__VIDEO))
            selected = selectedVideo;
        else if (0 == std::strcmp(type, IJKM_VAL_TYPE__AUDIO))
            selected = selectedAudio;
        else if (0 == std::strcmp(type, IJKM_VAL_TYPE__TIMEDTEXT))
            selected = selectedTimedText;

        napi_value track;
        napi_create_object(env, &track);

        napi_value value;
        napi_create_int32(env, (int32_t)i, &value);
        napi_set_named_property(env, track, "index", value);
        napi_create_string_utf8(env, type, NAPI_AUTO_LENGTH, &value);
        napi_set_named_property(env, track, "type", value);
        napi_get_boolean(env, selected == (int64_t)i, &value);
        napi_set_named_property(env, track, "selected", value);

        const char *language = ijkmeta_get_string_l(stream, IJKM_KEY_LANGUAGE);
        napi_create_string_utf8(env, language ? language : "", NAPI_AUTO_LENGTH, &value);
        napi_set_named_property(env, track, "language", value);
        const char *codec = ijkmeta_get_string_l(stream, IJKM_KEY_CODEC_NAME);
        napi_create_string_utf8(env, codec ? codec : "", NAPI_AUTO_LENGTH, &value);
        napi_set_named_property(env, track, "codec", value);
        const char *codecLongName = ijkmeta_get_string_l(stream, IJKM_KEY_CODEC_LONG_NAME);
        napi_create_string_utf8(env, codecLongName ? codecLongName : "", NAPI_AUTO_LENGTH, &value);
        napi_set_named_property(env, track, "codec_long_name", value);

        napi_create_int32(env, (int32_t)ijkmeta_get_int64_l(stream, IJKM_KEY_SAMPLE_RATE, 0), &value);
        napi_set_named_property(env, track, "sample_rate", value);
        napi_create_int64(env, ijkmeta_get_int64_l(stream, IJKM_KEY_CHANNEL_LAYOUT, 0), &value);
        napi_set_named_property(env, track, "channel_layout", value);

        napi_set_element(env, result, (uint32_t)i, track);
    }
    ijkmeta_unlock(meta);
    return result;
}

napi_value js_set_stream_selected(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    double index = -1;
    bool selected = false;
    if (ctx && argc >= 3 && get_number_arg(env, argv[1], &index) &&
        napi_get_value_bool(env, argv[2], &selected) == napi_ok)
        ijkmp_set_stream_selected(ctx->mp, (int)index, selected);
    return make_undefined(env);
}

napi_value js_is_playing(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    PlayerContext *ctx = player_from_args(env, argv, argc);
    napi_value result;
    napi_get_boolean(env, ctx && ijkmp_is_playing(ctx->mp), &result);
    return result;
}

napi_value js_noop(napi_env env, napi_callback_info info)
{
    return make_undefined(env);
}

napi_value register_api(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"create", nullptr, js_create, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, js_release, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSurfaceId", nullptr, js_set_surface_id, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setMessageCallback", nullptr, js_set_message_callback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setDataSource", nullptr, js_set_data_source, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setOption", nullptr, js_set_option, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setOptionLong", nullptr, js_set_option_long, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"prepareAsync", nullptr, js_prepare_async, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, js_start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause", nullptr, js_pause, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, js_stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reset", nullptr, js_reset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seekTo", nullptr, js_seek_to, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVolume", nullptr, js_set_volume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setLoopCount", nullptr, js_set_loop_count, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSpeed", nullptr, js_set_speed, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCurrentPosition", nullptr, js_get_current_position, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getDuration", nullptr, js_get_duration, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getTrackInfo", nullptr, js_get_track_info, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setStreamSelected", nullptr, js_set_stream_selected, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isPlaying", nullptr, js_is_playing, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setDebug", nullptr, js_noop, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    return register_api(env, exports);
}
EXTERN_C_END

static napi_module ijkplayer_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ijkplayer_napi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterIjkPlayerModule(void)
{
    napi_module_register(&ijkplayer_module);
}

/*
 * pipeline_ohos.h
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

#ifndef IJKPLAYER__PIPELINE_OHOS_H
#define IJKPLAYER__PIPELINE_OHOS_H

#include "../ff_ffpipeline.h"
#include "../ijkplayer.h"

IjkMediaPlayer *ijkmp_ohos_create(int (*msg_loop)(void *));
void ijkmp_ohos_set_surface(IjkMediaPlayer *mp, void *native_window);
void ijkmp_ohos_set_volume(IjkMediaPlayer *mp, float left, float right);

IJKFF_Pipeline *ffpipeline_create_ohos(struct FFPlayer *ffp);

#endif

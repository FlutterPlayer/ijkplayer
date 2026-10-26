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

#ifndef IJKSDL_ANDROID__IJKSDL_VOUT_OVERLAY_OHOS_AVCODEC_H
#define IJKSDL_ANDROID__IJKSDL_VOUT_OVERLAY_OHOS_AVCODEC_H

#include "../ijksdl_stdinc.h"
#include "../ijksdl_vout.h"

SDL_VoutOverlay *SDL_VoutOhosAVCodec_CreateOverlay(int width, int height, SDL_Vout *vout);

bool SDL_VoutOverlayOhosAVCodec_isKindOf(SDL_VoutOverlay *overlay);
int  SDL_VoutOverlayOhosAVCodec_releaseFrame_l(SDL_VoutOverlay *overlay, bool render);

#endif

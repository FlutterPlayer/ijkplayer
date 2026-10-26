/*****************************************************************************
 * ijksdl_vout_ohos_nativewindow.h
 *****************************************************************************
 *
 * Copyright (c) 2013 Bilibili
 * copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
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

#ifndef IJKSDL_OHOS__IJKSDL_VOUT_OHOS_NATIVEWINDOW_H
#define IJKSDL_OHOS__IJKSDL_VOUT_OHOS_NATIVEWINDOW_H

#include "../ijksdl_stdinc.h"
#include "../ijksdl_vout.h"

#ifdef __cplusplus
extern "C" {
#endif

SDL_Vout *SDL_VoutOHOS_CreateForNativeWindow(void);
void SDL_VoutOHOS_SetNativeWindow(SDL_Vout *vout, void *native_window);
void *SDL_VoutOHOS_GetNativeWindow(SDL_Vout *vout);

typedef struct SDL_OhosAVCodecBufferProxy SDL_OhosAVCodecBufferProxy;
typedef int (*SDL_VoutOhos_ReleaseOutputFunc)(void *decoder, uint32_t buffer_index, int render);

void SDL_VoutOhos_setReleaseOutputFunc(SDL_Vout *vout, SDL_VoutOhos_ReleaseOutputFunc func);
SDL_OhosAVCodecBufferProxy *SDL_VoutOhos_obtainBufferProxy(SDL_Vout *vout, void *decoder, uint32_t buffer_index);
int SDL_VoutOhos_releaseBufferProxyP(SDL_Vout *vout, SDL_OhosAVCodecBufferProxy **proxy, bool render);
int SDL_VoutOhos_releaseBufferProxyP_l(SDL_Vout *vout, SDL_OhosAVCodecBufferProxy **proxy, bool render);

#ifdef __cplusplus
}
#endif

#endif

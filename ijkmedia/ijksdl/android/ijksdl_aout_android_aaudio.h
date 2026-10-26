/*****************************************************************************
 * ijksdl_aout_android_aaudio.h
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

#ifndef IJKSDL_ANDROID__IJKSDL_AOUT_ANDROID_AAUDIO_H
#define IJKSDL_ANDROID__IJKSDL_AOUT_ANDROID_AAUDIO_H

#include "../ijksdl_aout.h"

/* fallback may be NULL. Ownership of fallback transfers to the returned
 * SDL_Aout on success; on failure the caller keeps ownership. */
SDL_Aout *SDL_AoutAndroid_CreateForAAudio(SDL_Aout *fallback);

#endif

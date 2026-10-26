/*****************************************************************************
 * ijksdl_android_jni.h
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

#ifndef IJKSDL_ANDROID__IJKSDL_ANDROID_JNI_H
#define IJKSDL_ANDROID__IJKSDL_ANDROID_JNI_H

#include <jni.h>
#include "j4a/j4a_base.h"
#include "j4a/j4a_allclasses.h"

JavaVM *SDL_JNI_GetJvm();

// Called from libijkplayer.so's JNI_OnLoad; ijksdl is linked statically.
jint ijksdl_JNI_OnLoad(JavaVM *vm, void *reserved);
void ijksdl_JNI_OnUnload(JavaVM *jvm, void *reserved);

jint    SDL_JNI_SetupThreadEnv(JNIEnv **p_env);
void    SDL_JNI_DetachThreadEnv();

int      SDL_JNI_ThrowException(JNIEnv *env, const char *exception, const char* msg);
int      SDL_JNI_ThrowIllegalStateException(JNIEnv *env, const char* msg);

jobject SDL_JNI_NewObjectAsGlobalRef(JNIEnv *env, jclass clazz, jmethodID methodID, ...);

void    SDL_JNI_DeleteGlobalRefP(JNIEnv *env, jobject *obj_ptr);
void    SDL_JNI_DeleteLocalRefP(JNIEnv *env, jobject *obj_ptr);

#define IJK_FIND_JAVA_CLASS(env__, var__, classsign__) \
    do { \
        jclass clazz = (*env__)->FindClass(env__, classsign__); \
        if (J4A_ExceptionCheck__catchAll(env) || !(clazz)) { \
            ALOGE("FindClass failed: %s", classsign__); \
            return -1; \
        } \
        var__ = (*env__)->NewGlobalRef(env__, clazz); \
        if (J4A_ExceptionCheck__catchAll(env) || !(var__)) { \
            ALOGE("FindClass::NewGlobalRef failed: %s", classsign__); \
            (*env__)->DeleteLocalRef(env__, clazz); \
            return -1; \
        } \
        (*env__)->DeleteLocalRef(env__, clazz); \
    } while(0);

#define JNI_CHECK_GOTO(condition__, env__, exception__, msg__, label__) \
    do { \
        if (!(condition__)) { \
            if (exception__) { \
                SDL_JNI_ThrowException(env__, exception__, msg__); \
            } \
            goto label__; \
        } \
    }while(0)

#define JNI_CHECK_RET_VOID(condition__, env__, exception__, msg__) \
    do { \
        if (!(condition__)) { \
            if (exception__) { \
                SDL_JNI_ThrowException(env__, exception__, msg__); \
            } \
            return; \
        } \
    }while(0)

#define JNI_CHECK_RET(condition__, env__, exception__, msg__, ret__) \
    do { \
        if (!(condition__)) { \
            if (exception__) { \
                SDL_JNI_ThrowException(env__, exception__, msg__); \
            } \
            return ret__; \
        } \
    }while(0)

#endif

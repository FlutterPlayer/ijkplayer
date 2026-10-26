/*
 * IJKFFMoviePlayerDef.m
 *
 * Copyright (c) 2019 Befovy <befovy@gmail.com>
 *
 * This file is part of fijkPlayer.
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

#import "IJKFFMediaPlayer.h"

#import "IJKFFMoviePlayerDef.h"
#import "IJKAudioKit.h"
#import "IJKFFOptions.h"
#import "IJKNotificationManager.h"
#import "ijkplayer/ijkplayer.h"

#import <libkern/OSAtomic.h>
#import <CoreImage/CoreImage.h>

typedef NS_ENUM(NSInteger, IJKSDLFFPlayrRenderType) {
    IJKSDLFFPlayrRenderTypeGlView = 0,
    IJKSDLFFPlayrRenderTypeFboView = 1,
};


@interface IJKFFWeakHolder : NSObject
@property (nonatomic, weak) id object;
@end

@implementation IJKFFWeakHolder
@end

@implementation IJKFFMediaPlayer {
    IjkMediaPlayer* _nativeMediaPlayer;
    IJKFFMoviePlayerMessagePool *_msgPool;

    IJKNotificationManager *_notificationManager;
    NSMutableSet<id<IJKMPEventHandler>> *_eventHandlers;
    
    CVPixelBufferRef _pixelBuffer;

    id<IJKCVPBViewProtocol> _cvPBView;
    IJKSDLFFPlayrRenderType _renderType;
    BOOL _playingBeforeInterruption;
}


@synthesize displayDelegate = _displayDelegate;
@synthesize scalingMode = _scalingMode;
#if TARGET_OS_IOS
@synthesize scaleFactor = _scaleFactor;
#endif
@synthesize rotatePreference = _rotatePreference;
@synthesize xRotateDegrees = _xRotateDegrees;
@synthesize yRotateDegrees = _yRotateDegrees;
@synthesize zRotateDegrees = _zRotateDegrees;
@synthesize colorPreference = _colorPreference;
@synthesize darPreference = _darPreference;
@synthesize preventDisplay = _preventDisplay;
@synthesize directDisplayHDRSupportted = _directDisplayHDRSupportted;
@synthesize allowHDRDirectDisplay = _allowHDRDirectDisplay;

- (IJKFFMoviePlayerMessage *) obtainMessage {
    return [_msgPool obtain];
}

inline static IJKFFMediaPlayer *ffplayerRetain(void *arg) {
    return (__bridge_transfer IJKFFMediaPlayer *) arg;
}

int ff_media_player_msg_loop(void* arg)
{
    @autoreleasepool {
        IjkMediaPlayer *mp = (IjkMediaPlayer*)arg;
        __weak IJKFFMediaPlayer *ffPlayer = ffplayerRetain(ijkmp_set_weak_thiz(mp, NULL));
        while (ffPlayer) {
            @autoreleasepool {
                IJKFFMoviePlayerMessage *msg = [ffPlayer obtainMessage];
                if (!msg)
                    break;
                
                int retval = ijkmp_get_msg(mp, &msg->_msg, 1);
                if (retval < 0)
                    break;
                
                // block-get should never return 0
                assert(retval > 0);
                [ffPlayer performSelectorOnMainThread:@selector(postEvent:) withObject:msg waitUntilDone:NO];
            }
        }
        
        // retained in prepare_async, before SDL_CreateThreadEx
        ijkmp_dec_ref_p(&mp);
        return 0;
    }
}

- (IJKFFMediaPlayer *)init
{
    self = [super init];
    if (self) {
        _renderType = IJKSDLFFPlayrRenderTypeGlView;
         [self nativeSetup];
    }
    return self;
}

- (instancetype)initWithFbo
{
    self = [super init];
    if (self) {
        _renderType = IJKSDLFFPlayrRenderTypeFboView;
        [self nativeSetup];
    }
    return self;
}


- (void) nativeSetup
{
    ijkmp_global_init();
    _msgPool = [[IJKFFMoviePlayerMessagePool alloc] init];
    _eventHandlers = [[NSMutableSet alloc] init];
    
    _nativeMediaPlayer = ijkmp_ios_create(ff_media_player_msg_loop);
    ijkmp_set_option(_nativeMediaPlayer, IJKMP_OPT_CATEGORY_PLAYER, "overlay-format", "fcc-_es2");

    IJKFFWeakHolder *weakHolder = [[IJKFFWeakHolder alloc] init];
    weakHolder.object = self;
    
    ijkmp_set_weak_thiz(_nativeMediaPlayer, (__bridge_retained void *) self);
    ijkmp_set_inject_opaque(_nativeMediaPlayer, (__bridge_retained void *) weakHolder);
    ijkmp_set_ijkio_inject_opaque(_nativeMediaPlayer, (__bridge_retained void *) weakHolder);
    
    _notificationManager = [[IJKNotificationManager alloc] init];

    [[IJKAudioKit sharedInstance] setupAudioSessionWithoutInterruptHandler];
#if TARGET_OS_IOS
    _scaleFactor = 1.0f;
#endif

    [self registerApplicationObservers];

}

- (void)postEvent: (IJKFFMoviePlayerMessage *)msg
{
    if (!msg)
        return;
    
    AVMessage *avmsg = &msg->_msg;
    for (id<IJKMPEventHandler> handler in _eventHandlers) {
        [handler onEvent4Player:self withType:avmsg->what andArg1:avmsg->arg1 andArg2:avmsg->arg2 andExtra:avmsg->obj];
    }
    [_msgPool recycle:msg];
}

- (int) prepareAsync
{
    return ijkmp_prepare_async(_nativeMediaPlayer);
}

- (int) setDataSource:(NSString *)url
{
    return ijkmp_set_data_source(_nativeMediaPlayer, [url UTF8String]);
}

- (int) start
{
    return ijkmp_start(_nativeMediaPlayer);
}

- (int) stop
{
    return ijkmp_stop(_nativeMediaPlayer);
}

- (int) pause
{
    return ijkmp_pause(_nativeMediaPlayer);
}

- (BOOL) isPlaying
{
    return ijkmp_is_playing(_nativeMediaPlayer);
}

- (long) getCurrentPosition
{
    return ijkmp_get_current_position(_nativeMediaPlayer);
}

- (long) getDuration
{
    return ijkmp_get_duration(_nativeMediaPlayer);
}

- (int) seekTo:(long) msec
{
    return ijkmp_seek_to(_nativeMediaPlayer, msec);
}


- (void) setLoop:(int) loop
{
    ijkmp_set_loop(_nativeMediaPlayer, loop);
}

- (int) getLoop
{
    return ijkmp_get_loop(_nativeMediaPlayer);
}

- (void) setSpeed:(float) speed
{
    ijkmp_set_property_float(_nativeMediaPlayer, FFP_PROP_FLOAT_PLAYBACK_RATE, speed);
}

- (void) setStreamSelected:(int) stream selected:(BOOL) selected
{
    ijkmp_set_stream_selected(_nativeMediaPlayer, stream, selected);
}

- (float) getFloatProperty:(int) property defalut:(float) value
{
    return ijkmp_get_property_float(_nativeMediaPlayer, property, value);
}

- (int64_t) getLongProperty:(int) property default:(int64_t) value
{
    return ijkmp_get_property_int64(_nativeMediaPlayer, property, value);
}

- (void)setPlaybackVolume:(float)volume
{
    if (!_nativeMediaPlayer)
        return;
    ijkmp_set_playback_volume(_nativeMediaPlayer, volume);
}

- (float)playbackVolume
{
    if (!_nativeMediaPlayer)
        return 0.0f;
    return ijkmp_get_property_float(_nativeMediaPlayer, FFP_PROP_FLOAT_PLAYBACK_VOLUME, 1.0f);
}

- (void) shutdown
{
    _ignoreAudioInterrupt = YES;
    [self unregisterApplicationObservers];
    ijkmp_shutdown(_nativeMediaPlayer);
    
    __unused id weakPlayer = (__bridge_transfer IJKFFMediaPlayer*)ijkmp_set_weak_thiz(_nativeMediaPlayer, NULL);
    __unused id weakHolder = (__bridge_transfer IJKFFWeakHolder*)ijkmp_set_inject_opaque(_nativeMediaPlayer, NULL);
    __unused id weakijkHolder = (__bridge_transfer IJKFFWeakHolder*)ijkmp_set_ijkio_inject_opaque(_nativeMediaPlayer, NULL);

    [_eventHandlers removeAllObjects];
    ijkmp_dec_ref_p(&_nativeMediaPlayer);

    CVPixelBufferRef buffer = _pixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(buffer, nil,
                                              (void **)&_pixelBuffer)) {
         buffer = _pixelBuffer;
    }
    if (buffer != nil) {
        CVPixelBufferRelease(buffer);
        buffer = nil;
    }
    _cvPBView = nil;
}

- (int) reset
{
    ijkmp_stop(_nativeMediaPlayer);
    ijkmp_reset(_nativeMediaPlayer);
    return 0;
}


- (void)setOptionValue:(NSString *)value
                forKey:(NSString *)key
            ofCategory:(IJKFFOptionCategory)category
{
    ijkmp_set_option(_nativeMediaPlayer, category, [key UTF8String], [value UTF8String]);
}

- (void)setOptionIntValue:(int64_t)value
                   forKey:(NSString *)key
               ofCategory:(IJKFFOptionCategory)category
{
    ijkmp_set_option_int(_nativeMediaPlayer, category, [key UTF8String], value);
}


- (void) addIJKMPEventHandler:(id<IJKMPEventHandler>) handler
{
    [_eventHandlers addObject:handler];
}

- (void) removeIJKMPEventHandler:(id<IJKMPEventHandler>) handler
{
    [_eventHandlers removeObject:handler];
}

#if IJK_IOS
- (UIImage *)snapshot {
    return nil;
}
#else
- (NSImage *)snapshot {
    return nil;
}
#endif

- (void) setupCVPixelBufferView:(id<IJKCVPBViewProtocol>) cvPBView
{
    _cvPBView = cvPBView;
    // self acts as the (headless) FSVideoRenderingProtocol renderer;
    // the vout delivers CVPixelBuffers via displayAttach:.
    ijkmp_ios_set_glview(_nativeMediaPlayer, self);
}

- (void) onSnapshot:(CVPixelBufferRef) pixelbuffer
{
    if (_cacheSnapshot) {
        CVPixelBufferRef newBuffer = CVPixelBufferRetain(pixelbuffer);
        CVPixelBufferRef oldBuffer = _pixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(oldBuffer, newBuffer,
                                                 (void **)&_pixelBuffer)) {
            oldBuffer = _pixelBuffer;
        }
        if (oldBuffer != nil) {
            CVPixelBufferRelease(oldBuffer);
        }
    }
}

// FSVideoRenderingProtocol: the vout calls this when a frame is ready
- (BOOL)displayAttach:(FSOverlayAttach *)attach
{
    CVPixelBufferRef pixelbuffer = attach.videoPicture;
    if (pixelbuffer != nil && _cvPBView != nil) {
        [self onSnapshot:pixelbuffer];
        [_cvPBView display_pixelbuffer:pixelbuffer];
    }
    return YES;
}

- (void)setNeedsRefreshCurrentPic
{
    // headless renderer: nothing to refresh
}

- (CGImageRef)snapshot:(FSSnapshotType)aType
{
    // CGImage snapshot not supported on the headless renderer
    return NULL;
}

- (NSString *)name
{
    return @"IJKFFMediaPlayer";
}


// IJKSDL Fbo view call this delegate when display frame
- (void)display_pixelbuffer:(CVPixelBufferRef)pixelbuffer {
    if (_cvPBView) {
        [_cvPBView display_pixelbuffer:pixelbuffer];
    }
    [self onSnapshot: pixelbuffer];
}

- (void) takeSnapshot:(OnSnapshotBlock) block
{
    CVPixelBufferRef snapshot = _pixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(snapshot, nil,
                                              (void **)&_pixelBuffer)) {
         snapshot = _pixelBuffer;
    }
    if (snapshot != nil) {
        CVPixelBufferRetain(snapshot);
    }
    if (!OSAtomicCompareAndSwapPtrBarrier(nil, snapshot, (void **)&_pixelBuffer)) {
        CVPixelBufferRelease(snapshot);
    }
    
    if (block != nil) {
        if (snapshot != nil) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:snapshot];

               CIContext *context = [CIContext contextWithOptions:nil];
               CGImageRef imageRef = [context createCGImage:ciImage
                        fromRect:CGRectMake(0, 0,
                                            CVPixelBufferGetWidth(snapshot),
                                            CVPixelBufferGetHeight(snapshot))];

#if TARGET_OS_IOS
               UIImage *uiImage = [UIImage imageWithCGImage:imageRef];
#else
               UIImage *uiImage = [[UIImage alloc] initWithCGImage:imageRef size:NSZeroSize];
#endif
               CGImageRelease(imageRef);

               block(uiImage, nil);
        } else {
            block(nil, [[NSError alloc] initWithDomain:@"no snapshot" code:IJKMPEC_SNAPSHOT userInfo:nil]);
        }
    }
    if (snapshot != nil) {
        CVPixelBufferRelease(snapshot);
    }
}

- (void)registerApplicationObservers
{
#if TARGET_OS_IOS
    [_notificationManager addObserver:self
                             selector:@selector(audioSessionInterrupt:)
                                 name:AVAudioSessionInterruptionNotification
                               object:nil];
#endif
}

- (void)unregisterApplicationObservers
{
    [_notificationManager removeAllObservers:self];
}


- (void)audioSessionInterrupt:(NSNotification *)notification
{
#if TARGET_OS_IOS
    if (_ignoreAudioInterrupt) {
        return;
    }
    int reason = [[[notification userInfo] valueForKey:AVAudioSessionInterruptionTypeKey] intValue];
    switch (reason) {
        case AVAudioSessionInterruptionTypeBegan: {
            if (_nativeMediaPlayer && ijkmp_get_state(_nativeMediaPlayer) == MP_STATE_STARTED) {
                _playingBeforeInterruption = YES;
            } else{
                _playingBeforeInterruption = NO;
            }
            NSLog(@"IJKFFMediaPlayer:audioSessionInterrupt: begin, %d\n", _playingBeforeInterruption);
            [self pause];
            [[IJKAudioKit sharedInstance] setActive:NO];
            break;
        }
        case AVAudioSessionInterruptionTypeEnded: {
            NSLog(@"IJKFFMediaPlayer:audioSessionInterrupt: end\n");
            [[IJKAudioKit sharedInstance] setActive:YES];
            if (_playingBeforeInterruption) {
                [self start];
            }
            break;
        }
    }
#endif
}

//开始录制
- (int) startRecordVideo:(NSString*)fileRealPath{
    return ijkmp_start_record(_nativeMediaPlayer, [fileRealPath UTF8String]);
}
//结束录制
- (int) stopRecordVideo{
    NSLog(@"结束录制");
    return ijkmp_stop_record(_nativeMediaPlayer);
}
@end

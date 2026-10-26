//
//  IJKFFCMediaPlayer.m
//  IJKPlayer
//
//  Created by befovy on 2019/11/1.
//  Copyright © 2019 befovy. All rights reserved.
//

#include "IJKFFCMediaPlayer.h"
#import "IJKFFMoviePlayerDef.h"
#import "IJKAudioKit.h"
#import "ijkplayer/ijkplayer.h"
#import <CoreVideo/CoreVideo.h>
#import "FSVideoRenderingProtocol.h"

struct IJKFFCMediaPlayer {
    IjkMediaPlayer* nativeMediaPlayer;
    
    void *msgPool;
    void *glView;
    void *eventCbs;
    void *userData;
    IJKFFOverlayCb overlayCb;
    
};


@interface IJKFFEventCbWrapper : NSObject
@property IJKFFEventCb cb;
@property void * userdata;
@end

@implementation IJKFFEventCbWrapper

- (IJKFFEventCbWrapper *) initWithCb: (IJKFFEventCb) cb andUserData:(void *)userdata
{
    self = [super init];
    if (self) {
        _cb = cb;
        _userdata = userdata;
    }
    return self;
}

@end

@interface IJKFFCMPGlView : NSObject<FSVideoRenderingProtocol>
@end

@implementation IJKFFCMPGlView {
    IJKFFCMediaPlayer *_player;
    IJKFFOverlay *_overlay;
    uint16_t _pitches[4];
    uint8_t *_pixels[4];
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
@synthesize allowHDRDirectDisplay = _allowHDRDirectDisplay;


- (IJKFFCMPGlView *) initWithPlayer:(IJKFFCMediaPlayer *)player
{
    self = [super init];
    if (self) {
        _player = player;

        _overlay = mallocz(sizeof(IJKFFOverlay));
        _overlay->pitches = _pitches;
        _overlay->pixels = _pixels;
    }
    return self;
}

- (void)dealloc
{
    if (_overlay) {
        free(_overlay);
        _overlay = nil;
    }
    _player = nil;
}

- (BOOL)displayAttach:(FSOverlayAttach *)attach {
    if (!_player->overlayCb)
        return YES;

    CVPixelBufferRef pixelBuffer = attach.videoPicture;
    if (!pixelBuffer)
        return YES; // refresh attach without a picture: nothing to forward

    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    _overlay->w = attach.w;
    _overlay->h = attach.h;
    _overlay->format = 0; // not carried by FSOverlayAttach
    _overlay->sar_num = attach.sarNum;
    _overlay->sar_dem = attach.sarDen;

    if (planeCount == 0) {
        _overlay->planes = 1;
        _overlay->pixels[0] = CVPixelBufferGetBaseAddress(pixelBuffer);
        _overlay->pitches[0] = (uint16_t)CVPixelBufferGetBytesPerRow(pixelBuffer);
    } else {
        if (planeCount > 4)
            planeCount = 4;
        _overlay->planes = (int)planeCount;
        for (int idx = 0; idx < planeCount; idx++) {
            _overlay->pixels[idx] = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, idx);
            _overlay->pitches[idx] = (uint16_t)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, idx);
        }
    }

    _player->overlayCb(_player->userData, _overlay);
    return YES;
}

- (NSString *)name {
    return @"IJKFFCMPGlView";
}

- (void)setNeedsRefreshCurrentPic {
    // headless forwarder: nothing cached to redraw
}

- (CGImageRef)snapshot:(FSSnapshotType)aType {
    return NULL;
}

- (BOOL)directDisplayHDRSupportted HDR_API_AVAILABLE {
    return NO;
}

@end

int ffc_media_player_msg_loop(void* arg)
{
    @autoreleasepool {
        IjkMediaPlayer *mp = (IjkMediaPlayer*)arg;
        IJKFFCMediaPlayer *ffPlayer = ijkmp_set_weak_thiz(mp, NULL);
        while (ffPlayer) {
            @autoreleasepool {
                IJKFFMoviePlayerMessagePool *pool = (__bridge IJKFFMoviePlayerMessagePool*)(ffPlayer->msgPool);
                IJKFFMoviePlayerMessage *msg = [pool obtain];
                if (!msg)
                    break;
                
                int retval = ijkmp_get_msg(mp, &msg->_msg, 1);
                if (retval < 0)
                    break;
                
                // block-get should never return 0
                assert(retval > 0);
                // todo
                //[ffPlayer performSelectorOnMainThread:@selector(postEvent:) withObject:msg waitUntilDone:NO];
                
                NSMutableOrderedSet<IJKFFEventCbWrapper*> *eventCbs = (__bridge NSMutableOrderedSet<IJKFFEventCbWrapper*> *) ffPlayer->eventCbs;
                struct AVMessage *avmsg = &(msg->_msg);
                for (IJKFFEventCbWrapper *cbw in eventCbs) {
                    cbw.cb(cbw.userdata, avmsg->what, avmsg->arg1, avmsg->arg2, avmsg->obj);
                }
                printf("msg pool: %d %d %d\n", msg->_msg.what, msg->_msg.arg1, msg->_msg.arg2);
            }
        }
        
        // retained in prepare_async, before SDL_CreateThreadEx
        ijkmp_dec_ref_p(&mp);
        return 0;
    }
}

IJKFFCMediaPlayer *ijkcmp_create(void)
{
    IJKFFCMediaPlayer *player = malloc(sizeof(IJKFFCMediaPlayer));
    
    ijkmp_global_init();
    IJKFFMoviePlayerMessagePool *pool = [[IJKFFMoviePlayerMessagePool alloc] init];
    
    player->msgPool = (__bridge_retained void*) pool;
    // player->eventHandlers = [[NSMutableSet alloc] init];

    IjkMediaPlayer *nativeMediaPlayer = ijkmp_ios_create(ffc_media_player_msg_loop);
    player->nativeMediaPlayer = nativeMediaPlayer;
    ijkmp_set_option(nativeMediaPlayer, IJKMP_OPT_CATEGORY_PLAYER, "overlay-format", "fcc-_es2");

    NSMutableOrderedSet<IJKFFEventCbWrapper*> *eventCbs = [[NSMutableOrderedSet alloc] init];
    player->eventCbs = (__bridge_retained void*) eventCbs;
    
    ijkmp_set_weak_thiz(nativeMediaPlayer, player);
    ijkmp_set_inject_opaque(nativeMediaPlayer, player);
    ijkmp_set_ijkio_inject_opaque(nativeMediaPlayer, player);
    [[IJKAudioKit sharedInstance] setupAudioSession];
    
    printf("ijkcmp_create\n");
    
    return player;
}

int ijkcmp_set_data_source(IJKFFCMediaPlayer *mp, const char * url)
{
    if (mp)
        return ijkmp_set_data_source(mp->nativeMediaPlayer, url);
    else
        return -1;
}

int ijkcmp_prepareAsync(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_prepare_async(mp->nativeMediaPlayer);
    else
        return -1;
}

int ijkcmp_start(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_start(mp->nativeMediaPlayer);
    else
        return -1;
}

int ijkcmp_stop(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_stop(mp->nativeMediaPlayer);
    else
        return -1;
}

int ijkcmp_pause(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_pause(mp->nativeMediaPlayer);
    else
        return -1;
}

int ijkcmp_reset(IJKFFCMediaPlayer *mp)
{
    if (mp) {
        ijkmp_stop(mp->nativeMediaPlayer);
        ijkmp_reset(mp->nativeMediaPlayer);
        return 0;
    } else
        return -1;
}

bool ijkcmp_is_playing(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_is_playing(mp->nativeMediaPlayer);
    else
        return false;
}


void ijkcmp_shutdown(IJKFFCMediaPlayer *mp)
{
    if (mp) {
        ijkmp_shutdown(mp->nativeMediaPlayer);
     
        ijkmp_set_inject_opaque(mp->nativeMediaPlayer, NULL);
        ijkmp_set_ijkio_inject_opaque(mp->nativeMediaPlayer, NULL);
        
        __unused IJKFFMoviePlayerMessagePool *pool = (__bridge_transfer IJKFFMoviePlayerMessagePool *) mp->msgPool;
        NSMutableOrderedSet<IJKFFEventCbWrapper*> *eventCbs = (__bridge_transfer NSMutableOrderedSet<IJKFFEventCbWrapper*> *) mp->eventCbs;
        [eventCbs removeAllObjects];
        //[mp->eventHandlers removeAllObjects];
        ijkmp_dec_ref_p(&mp->nativeMediaPlayer);
    }
}

int64_t ijkcmp_get_current_position(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_get_current_position(mp->nativeMediaPlayer);
    else
        return 0;
}


int64_t ijkcmp_get_duration(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_get_duration(mp->nativeMediaPlayer);
    else
        return 0;
}

int ijkcmp_seek_to(IJKFFCMediaPlayer *mp, int64_t msec)
{
    if (mp)
        return ijkmp_seek_to(mp->nativeMediaPlayer, msec);
    else
        return -1;
}

void ijkcmp_set_loop(IJKFFCMediaPlayer *mp, int loop)
{
    if (mp)
        ijkmp_set_loop(mp->nativeMediaPlayer, loop);
}

int ijkcmp_get_loop(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_get_loop(mp->nativeMediaPlayer);
    else
        return -1;
}

void ijkcmp_set_speed(IJKFFCMediaPlayer *mp, float speed)
{
    if (mp)
        ijkmp_set_playback_rate(mp->nativeMediaPlayer, speed);
}

void ijkcmp_set_playback_volume(IJKFFCMediaPlayer *mp, float volume)
{
    if (mp)
        ijkmp_set_playback_volume(mp->nativeMediaPlayer, volume);
}

float ijkcmp_get_playback_volume(IJKFFCMediaPlayer *mp)
{
    if (mp)
        return ijkmp_get_property_float(mp->nativeMediaPlayer, FFP_PROP_FLOAT_PLAYBACK_VOLUME, 1.0f);
    else
        return 0.0f;
}

void ijkcmp_set_stream_selected(IJKFFCMediaPlayer *mp, int strean, bool selected)
{
    if (mp)
        ijkmp_set_stream_selected(mp->nativeMediaPlayer, strean, selected);
    
}

float ijkcmp_get_float_property(IJKFFCMediaPlayer *mp, int property, float dfault)
{
    if (mp)
        return ijkmp_get_property_float(mp->nativeMediaPlayer, property, dfault);
    else
        return -1.0;
}


int64_t ijkcmp_get_long_property(IJKFFCMediaPlayer *mp, int property, int64_t dfault)
{
    if (mp)
        return ijkmp_get_property_int64(mp->nativeMediaPlayer, property, dfault);
    else
        return -1;
}


void ijkcmp_set_option(IJKFFCMediaPlayer *mp, const char *value, const char *key, int category)
{
    if (mp)
        ijkmp_set_option(mp->nativeMediaPlayer, category, key, value);
}

void ijkcmp_set_int_option(IJKFFCMediaPlayer *mp, int64_t value, const char *key, int category)
{
    if (mp)
        ijkmp_set_option_int(mp->nativeMediaPlayer, category, key, value);
}

void ijkcmp_set_overlay_cb(IJKFFCMediaPlayer *mp, void *userdata, IJKFFOverlayCb cb)
{
    if (mp) {
        if (mp->glView == nil) {
            IJKFFCMPGlView *glview = [[IJKFFCMPGlView alloc] initWithPlayer:mp];
            mp->glView = (__bridge void*) glview;
            ijkmp_ios_set_glview(mp->nativeMediaPlayer, glview);
        }
        mp->overlayCb = cb;
        mp->userData = userdata;
    }
}

void ijkcmp_add_event_listener(IJKFFCMediaPlayer *mp, void *userdata, IJKFFEventCb cb)
{
    if (mp) {
        NSMutableOrderedSet<IJKFFEventCbWrapper*> *eventCbs = (__bridge NSMutableOrderedSet<IJKFFEventCbWrapper*> *) mp->eventCbs;
        IJKFFEventCbWrapper *wrapper = [[IJKFFEventCbWrapper alloc] initWithCb:cb andUserData:userdata];
        [eventCbs addObject:wrapper];
    }
}

void ijkcmp_remove_event_listener(IJKFFCMediaPlayer *mp, void *userdata, IJKFFEventCb cb)
{
    if (mp) {
        NSMutableOrderedSet<IJKFFEventCbWrapper*> *eventCbs = (__bridge NSMutableOrderedSet<IJKFFEventCbWrapper*> *) mp->eventCbs;
        IJKFFEventCbWrapper *tobeRemoved = nil;
        for (IJKFFEventCbWrapper *wrapper in eventCbs) {
            if (wrapper.cb == cb && wrapper.userdata == userdata) {
                tobeRemoved = wrapper;
                break;
            }
        }
        if (tobeRemoved != nil) {
            [eventCbs removeObject:tobeRemoved];
        }
    }
}

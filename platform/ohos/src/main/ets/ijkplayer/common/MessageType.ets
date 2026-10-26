/*
 * MessageType.ets
 *
 * Copyright (c) 2024 FlutterPlayer
 *
 * This file is part of ijkPlayer.
 */

export class MessageType {
  static readonly MEDIA_ERROR: number = 100;
  static readonly MEDIA_PREPARED: number = 200;
  static readonly MEDIA_PLAYBACK_COMPLETE: number = 300;
  static readonly MEDIA_VIDEO_SIZE_CHANGED: number = 400;
  static readonly MEDIA_SAR_CHANGED: number = 401;
  static readonly MEDIA_VIDEO_RENDERING_START: number = 402;
  static readonly MEDIA_AUDIO_RENDERING_START: number = 403;
  static readonly MEDIA_VIDEO_ROTATION_CHANGED: number = 404;
  static readonly MEDIA_BUFFERING_START: number = 500;
  static readonly MEDIA_BUFFERING_END: number = 501;
  static readonly MEDIA_BUFFERING_UPDATE: number = 502;
  static readonly MEDIA_CURRENT_POSITION_UPDATE: number = 510;
  static readonly MEDIA_SEEK_COMPLETE: number = 600;
  static readonly MEDIA_PLAYBACK_STATE_CHANGED: number = 700;
  static readonly MEDIA_TIMED_TEXT: number = 800;
}

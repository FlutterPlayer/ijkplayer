/*
 * IjkMediaPlayer.ets
 *
 * Copyright (c) 2024 FlutterPlayer
 *
 * This file is part of ijkPlayer.
 */

import {
  create,
  release,
  setSurfaceId,
  setMessageCallback,
  setDataSource,
  setOption,
  setOptionLong,
  prepareAsync,
  start,
  pause,
  stop,
  reset,
  seekTo,
  setVolume,
  setLoopCount,
  setSpeed,
  getCurrentPosition,
  getDuration,
  getTrackInfo,
  setStreamSelected,
  isPlaying,
  setDebug
} from 'libijkplayer_napi.so';

export interface PlayerMessage {
  what: number;
  arg1: number;
  arg2: number;
  obj: string;
}

export interface OnMessageCallback {
  onMessage(what: number, arg1: number, arg2: number, obj: string): void;
}

export interface PlayerTrack {
  index: number;
  type: string;
  selected: boolean;
  language: string;
  codec: string;
  codec_long_name: string;
  sample_rate: number;
  channel_layout: number;
}

export class IjkMediaPlayer {
  private id: string;
  private callback: OnMessageCallback | null = null;
  private created: boolean = false;

  constructor(id?: string) {
    this.id = id !== undefined ? id : `ijkplayer_${Date.now()}`;
  }

  native_setup(): void {
    if (!this.created) {
      create(this.id);
      this.created = true;
    }
  }

  setSurfaceId(surfaceId: number): void {
    this.native_setup();
    setSurfaceId(this.id, surfaceId);
  }

  setDebug(open: boolean): void {
    setDebug(this.id, open);
  }

  setOption(category: string, key: string, value: string): void {
    setOption(this.id, category, key, value);
  }

  setOptionLong(category: string, key: string, value: string): void {
    setOptionLong(this.id, category, key, value);
  }

  setDataSource(url: string): void {
    setDataSource(this.id, url);
  }

  prepareAsync(): void {
    prepareAsync(this.id);
  }

  start(): void {
    start(this.id);
  }

  pause(): void {
    pause(this.id);
  }

  stop(): void {
    stop(this.id);
  }

  reset(): void {
    reset(this.id);
  }

  seekTo(msec: string): void {
    seekTo(this.id, msec);
  }

  setVolume(leftVolume: string, rightVolume: string): void {
    setVolume(this.id, leftVolume, rightVolume);
  }

  setLoopCountNum(loopCount: number): void {
    setLoopCount(this.id, loopCount);
  }

  setSpeed(speed: string): void {
    setSpeed(this.id, speed);
  }

  getCurrentPosition(): number {
    return getCurrentPosition(this.id);
  }

  getDuration(): number {
    return getDuration(this.id);
  }

  getTrackInfo(): PlayerTrack[] {
    return getTrackInfo(this.id);
  }

  selectTrack(index: number, selected: boolean): void {
    setStreamSelected(this.id, index, selected);
  }

  isPlaying(): boolean {
    return isPlaying(this.id);
  }

  setOnMessageCallback(callback: OnMessageCallback): void {
    this.callback = callback;
  }

  setMessageListener(): void {
    setMessageCallback(this.id, (message: PlayerMessage) => {
      if (this.callback) {
        this.callback.onMessage(message.what, message.arg1, message.arg2, message.obj);
      }
    });
  }

  releaseAsync(): void {
    setMessageCallback(this.id, null);
    release(this.id);
    this.created = false;
    this.callback = null;
  }
}

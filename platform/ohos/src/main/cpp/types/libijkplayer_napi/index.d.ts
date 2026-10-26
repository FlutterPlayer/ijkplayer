export interface PlayerMessage {
  what: number;
  arg1: number;
  arg2: number;
  obj: string;
}

export function create(id: string): void;
export function release(id: string): void;
export function setSurfaceId(id: string, surfaceId: number): void;
export function setMessageCallback(id: string, callback: ((message: PlayerMessage) => void) | null): void;
export function setDataSource(id: string, url: string): void;
export function setOption(id: string, category: string, key: string, value: string): void;
export function setOptionLong(id: string, category: string, key: string, value: string): void;
export function prepareAsync(id: string): void;
export function start(id: string): void;
export function pause(id: string): void;
export function stop(id: string): void;
export function reset(id: string): void;
export function seekTo(id: string, msec: string): void;
export function setVolume(id: string, leftVolume: string, rightVolume: string): void;
export function setLoopCount(id: string, loopCount: number): void;
export function setSpeed(id: string, speed: string): void;
export function getCurrentPosition(id: string): number;
export function getDuration(id: string): number;
export function isPlaying(id: string): boolean;
export function setDebug(id: string, open: boolean): void;

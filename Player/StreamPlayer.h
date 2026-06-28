/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef StreamPlayer_h
#define StreamPlayer_h

#import <Foundation/Foundation.h>

@class StreamPlayer;

@protocol StreamPlayerDelegate <NSObject>
@optional
- (void)streamPlayerDidStartPlaying:(StreamPlayer *)player;
- (void)streamPlayerDidStop:(StreamPlayer *)player;
- (void)streamPlayer:(StreamPlayer *)player didFailWithError:(NSError *)error;
- (void)streamPlayer:(StreamPlayer *)player didUpdateStatus:(NSString *)status;
/// ICY metadata (e.g., StreamTitle) was updated during streaming
- (void)streamPlayer:(StreamPlayer *)player didUpdateMetadata:(NSDictionary *)metadata;
@end

/**
 * StreamPlayer
 *
 * Audio stream player using FFmpeg (libavformat/libavcodec/libswresample)
 * and libao. Handles HTTP streaming URLs with progressive decode/playback.
 * Singleton — one instance shared across the application.
 */
@interface StreamPlayer : NSObject
{
@private
    // FFmpeg/libao internals (opaque pointers)
    void *_formatCtx;      // AVFormatContext *
    void *_codecCtx;       // AVCodecContext *
    void *_swrCtx;         // SwrContext *
    void *_frame;          // AVFrame *
    void *_packet;         // AVPacket *
    void *_aoDev;          // ao_device *
    int _audioStreamIndex;

    // Playback state
    NSThread *_playbackThread;
    BOOL _shouldStop;
    BOOL _isPlaying;
    int _decodeErrorCount;

    // Audio buffer
    void *_audioBuffer;
    int _audioBufferSize;

    // Properties
    float _volume;
    BOOL _muted;
    NSString *_currentURL;

    // Delegate (assigned — not retained to avoid cycles)
    id<StreamPlayerDelegate> _delegate;

    // ICY metadata tracking
    NSDictionary *_lastMetadata;
    int _metadataCheckCounter;
}

@property (nonatomic, assign) id<StreamPlayerDelegate> delegate;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, assign) float volume;   // 0.0 — 1.0
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, readonly, copy) NSString *currentURL;

+ (instancetype)sharedPlayer;

- (BOOL)openURL:(NSString *)urlString error:(NSError **)error;
- (void)play;
- (void)stop;
- (void)close;

@end

#endif /* StreamPlayer_h */

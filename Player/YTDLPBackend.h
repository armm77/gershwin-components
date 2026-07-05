/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef YTDLPBackend_h
#define YTDLPBackend_h

#import <Foundation/Foundation.h>

@class YTDLPBackend;

@protocol YTDLPBackendDelegate <NSObject>
@optional
/// A URL was successfully resolved to a direct stream URL.
- (void)ytdlpBackend:(YTDLPBackend *)backend didResolveURL:(NSString *)streamURL
              title:(NSString *)title thumbnail:(NSString *)thumbnailURL
            duration:(NSTimeInterval)duration;
/// Resolution failed.
- (void)ytdlpBackend:(YTDLPBackend *)backend didFailWithError:(NSString *)error;
/// Resolution was cancelled by the user.
- (void)ytdlpBackendDidCancel:(YTDLPBackend *)backend;
@end

/**
 * YTDLPBackend
 *
 * Wraps yt-dlp(1) to resolve URLs from streaming sites (YouTube, SoundCloud, etc.)
 * into playable media URLs.  Runs yt-dlp as a subprocess with NSTask.
 *
 * Usage:
 *   YTDLPBackend *yt = [[YTDLPBackend alloc] init];
 *   yt.delegate = self;
 *   [yt resolveURL:@"https://youtube.com/watch?v=..."];
 *
 * To cancel an in-flight resolution:
 *   [yt cancel];
 */
@interface YTDLPBackend : NSObject
{
    NSTask *_task;
    NSPipe *_outputPipe;
    NSPipe *_errorPipe;
    BOOL _isRunning;
    NSString *_formatSpec;
}

/// Delegate for resolution callbacks.
@property (nonatomic, assign) id<YTDLPBackendDelegate> delegate;

/// The format string passed to yt-dlp -f (default @"best/best").
/// Common values: @"best", @"bestaudio", @"worst",
/// @"best[height<=720]/best".
@property (nonatomic, copy) NSString *formatSpec;

/// Path to the yt-dlp binary.  Defaults to @"yt-dlp" (found via $PATH).
@property (nonatomic, copy) NSString *ytdlpPath;

/// Resolve a URL asynchronously.  Results arrive via the delegate.
- (void)resolveURL:(NSString *)url;

/// Cancel a running resolution.  The delegate receives
/// -ytdlpBackendDidCancel: when the process has been terminated.
- (void)cancel;

/// @return YES if a resolution is in progress.
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Convenience: check whether yt-dlp is available at the configured path.
- (BOOL)checkAvailability;

/// Convenience: extract the video ID from common URL patterns, or return nil.
+ (NSString *)extractVideoIDFromURL:(NSString *)url;

@end

#endif /* YTDLPBackend_h */

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLMStreamDownloader : NSObject

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, assign) NSTimeInterval connectTimeout;
@property (nonatomic, assign) NSTimeInterval totalTimeout;

- (instancetype)initWithURL:(NSURL *)url;
- (void)startWithDataCallback:(void (^)(NSData *data, int64_t bytesReceived, int64_t totalBytes))dataCallback
            completionCallback:(void (^)(NSError *_Nullable error))completionCallback;
- (void)cancel;
- (BOOL)isCancelled;

@end

NS_ASSUME_NONNULL_END

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Decompresses a single compressed stream on the fly using libarchive.
// Producer-consumer pattern: feed compressed data in, get decompressed data out.
@interface CLMArchiveExtractor : NSObject

@property (nonatomic, copy) void (^outputHandler)(NSData *decompressedData);
@property (nonatomic, copy) void (^completionHandler)(NSError *_Nullable error);

- (instancetype)init;
- (void)startExtracting;
- (void)feedCompressedData:(NSData *)data;
- (void)finish;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

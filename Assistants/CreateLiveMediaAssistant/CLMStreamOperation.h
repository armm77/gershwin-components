/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CLMStreamOperation;

@protocol CLMStreamOperationDelegate <NSObject>
- (void)streamOperation:(CLMStreamOperation *)op
       progressUpdated:(float)progress
          bytesReceived:(int64_t)bytes
            totalBytes:(int64_t)total;
- (void)streamOperation:(CLMStreamOperation *)op
          statusUpdated:(NSString *)status;
- (void)streamOperation:(CLMStreamOperation *)op
     didCompleteWithError:(nullable NSError *)error;
@end

// Determines whether the downloaded data needs on-the-fly decompression
typedef NS_ENUM(NSInteger, CLMStreamContentType) {
    CLMStreamContentTypeUnknown,
    CLMStreamContentTypeRaw,       // .iso, .img - write directly
    CLMStreamContentTypeCompressed // .iso.gz, .img.xz, etc. - decompress first
};

@interface CLMStreamOperation : NSOperation

@property (nonatomic, weak) id<CLMStreamOperationDelegate> delegate;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) int64_t bytesProcessed;
@property (nonatomic, readonly) int64_t totalBytes;

- (instancetype)initWithURL:(NSURL *)url
                 devicePath:(NSString *)devicePath;
+ (CLMStreamContentType)contentTypeForURL:(NSURL *)url;
+ (BOOL)isImageAssetName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END

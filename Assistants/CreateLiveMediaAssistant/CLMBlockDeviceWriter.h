/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLMBlockDeviceWriter : NSObject

@property (nonatomic, readonly) NSString *devicePath;
@property (nonatomic, readonly, getter=isOpen) BOOL open;
@property (nonatomic, readonly) int64_t bytesWritten;

- (instancetype)initWithDevicePath:(NSString *)devicePath;
- (BOOL)openWithError:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
- (BOOL)writeBytes:(const void *)bytes length:(size_t)length error:(NSError **)error;
- (BOOL)synchronizeWithError:(NSError **)error;
- (BOOL)closeWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

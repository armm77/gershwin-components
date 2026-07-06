/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@protocol BrightnessKeySource <NSObject>
- (void)start:(void (^)(int delta))handler;

@optional
- (void)stop;
@end

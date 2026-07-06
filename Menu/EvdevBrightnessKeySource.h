/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "BrightnessKeySource.h"

@interface EvdevBrightnessKeySource : NSObject <BrightnessKeySource>
- (instancetype)init;
- (void)start:(void (^)(int delta))handler;
- (void)stop;
@end

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "BacklightBackend.h"

@interface SysfsBacklightBackend : NSObject <BacklightBackend>
- (instancetype)init;
@end

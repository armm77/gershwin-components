/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@protocol BacklightBackend <NSObject>
- (int)current;
- (int)maximum;
- (void)set:(int)value;
@end

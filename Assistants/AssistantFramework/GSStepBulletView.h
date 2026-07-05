/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface GSStepBulletView : NSView
{
    @private
    NSInteger _state;
    NSColor *_baseColor;
}

@property (nonatomic, assign) NSInteger state; // 0=future, 1=current, 2=completed
@property (nonatomic, strong) NSColor *baseColor;

@end

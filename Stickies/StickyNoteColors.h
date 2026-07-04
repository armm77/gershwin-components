/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSColor.h>

@interface StickyNoteColors : NSObject
{
}

+ (NSArray *)stickyNoteColors;
+ (NSColor *)colorWithName:(NSString *)name;
+ (NSString *)nameForColor:(NSColor *)color;

@end
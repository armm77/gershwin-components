/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StickyNoteColors.h"

static NSColor *yellowColor = nil;
static NSColor *blueColor = nil;
static NSColor *greenColor = nil;
static NSColor *pinkColor = nil;
static NSColor *purpleColor = nil;
static NSColor *grayColor = nil;

@implementation StickyNoteColors

+ (void)initialize
{
    if (self == [StickyNoteColors class]) {
        yellowColor = [[NSColor colorWithDeviceRed:1.0 green:0.988 blue:0.678 alpha:1.0] retain];
        blueColor = [[NSColor colorWithDeviceRed:0.702 green:0.871 blue:1.0 alpha:1.0] retain];
        greenColor = [[NSColor colorWithDeviceRed:0.757 green:1.0 blue:0.718 alpha:1.0] retain];
        pinkColor = [[NSColor colorWithDeviceRed:1.0 green:0.718 blue:0.780 alpha:1.0] retain];
        purpleColor = [[NSColor colorWithDeviceRed:0.871 green:0.718 blue:1.0 alpha:1.0] retain];
        grayColor = [[NSColor colorWithDeviceRed:0.871 green:0.871 blue:0.871 alpha:1.0] retain];
    }
}

+ (NSArray *)stickyNoteColors
{
    return [NSArray arrayWithObjects:yellowColor, blueColor, greenColor, pinkColor, purpleColor, grayColor, nil];
}

+ (NSColor *)colorWithName:(NSString *)name
{
    if ([name isEqualToString:@"yellow"]) return yellowColor;
    if ([name isEqualToString:@"blue"]) return blueColor;
    if ([name isEqualToString:@"green"]) return greenColor;
    if ([name isEqualToString:@"pink"]) return pinkColor;
    if ([name isEqualToString:@"purple"]) return purpleColor;
    if ([name isEqualToString:@"gray"]) return grayColor;
    return yellowColor;
}

+ (NSString *)nameForColor:(NSColor *)color
{
    if ([color isEqual:yellowColor]) return @"yellow";
    if ([color isEqual:blueColor]) return @"blue";
    if ([color isEqual:greenColor]) return @"green";
    if ([color isEqual:pinkColor]) return @"pink";
    if ([color isEqual:purpleColor]) return @"purple";
    if ([color isEqual:grayColor]) return @"gray";
    return @"yellow";
}

@end
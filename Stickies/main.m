/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/NSApplication.h>
#import "StickiesAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        StickiesAppDelegate *delegate = [[StickiesAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface SystemProfilerController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDelegate, NSTableViewDataSource>

+ (SystemProfilerController *)sharedController;

@end

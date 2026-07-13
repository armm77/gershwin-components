/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface BuildApplication : NSApplication <NSApplicationDelegate>
{
    NSString *makefilePath;
    NSString *catalogBuildName;
}

@property (retain) NSString *makefilePath;
@property (retain) NSArray *extraArgs;
@property (retain) NSString *catalogBuildName;
@property BOOL autoInstallLaunch;
@property BOOL keepBuildDir;

@end
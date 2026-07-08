/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildApplication.h"
#import "BuildController.h"

@implementation BuildApplication

@synthesize makefilePath;
@synthesize extraArgs;

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath: self.makefilePath];
    [controller setExtraArgs: self.extraArgs];
    [controller showWindow];
}

@end
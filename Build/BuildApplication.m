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

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    NSLog(@"BuildApplication: willTerminate (reason=%@)", [notification userInfo]);
}

- (BOOL)isMakefileName:(NSString *)name
{
    return [name isEqualToString:@"GNUmakefile"]
        || [name isEqualToString:@"GNUmakefile.in"]
        || [name isEqualToString:@"Makefile"]
        || [name isEqualToString:@"makefile"];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    NSString *name = [filename lastPathComponent];
    if (![self isMakefileName:name]) {
        return NO;
    }
    self.makefilePath = filename;
    self.extraArgs = @[];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *filename in filenames) {
        NSString *name = [filename lastPathComponent];
        if ([self isMakefileName:name]) {
            self.makefilePath = filename;
            self.extraArgs = @[];
            return;
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath: self.makefilePath];
    [controller setExtraArgs: self.extraArgs];
    [controller showWindow];
}

@end
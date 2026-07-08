/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface BuildController : NSObject <NSWindowDelegate>
{
    NSWindow *window;
    NSTextField *statusLabel;
    NSProgressIndicator *progressBar;
    NSScrollView *outputScrollView;
    NSTextView *outputView;
    NSTask *buildTask;
    NSPipe *outputPipe;
    NSString *makefilePath;
    NSTask *installTask;
    NSPipe *installPipe;
    BOOL installShouldLaunch;
}

@property (strong) NSString *makefilePath;
@property (strong) NSMutableString *buildOutput;
@property BOOL consoleMode;
@property (strong) NSArray *extraArgs;

- (void)showWindow;
- (void)startBuild;

@end
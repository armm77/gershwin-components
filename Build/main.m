/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "BuildApplication.h"
#import "BuildController.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        // Process command line arguments
        // Use -makefilePath flag so NSApp doesn't treat it as a file to open
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        NSString *makefilePath = nil;
        NSMutableArray *extraArgs = [NSMutableArray array];
        BOOL nextIsMakefile = NO;
        for (NSUInteger i = 1; i < [args count]; i++) {
            NSString *arg = [args objectAtIndex: i];
            if ([arg isEqualToString: @"-makefilePath"]) {
                nextIsMakefile = YES;
            } else if (nextIsMakefile) {
                makefilePath = arg;
                nextIsMakefile = NO;
            } else {
                [extraArgs addObject: arg];
            }
        }

        BOOL hasDisplay = (getenv("DISPLAY") != NULL);

        if (!hasDisplay) {
            // Console mode, run build directly without GUI
            if (makefilePath) {
                NSTask *task = [[NSTask alloc] init];
                NSString *dir = [makefilePath stringByDeletingLastPathComponent];
                if ([dir length] == 0) dir = @".";
                [task setCurrentDirectoryPath: dir];
                NSString *gmakePath = [NSTask launchPathForTool: @"gmake"];
                if (!gmakePath) {
                    fprintf(stderr, "Error: gmake not found in PATH\n");
                    exit(1);
                }
                [task setLaunchPath: gmakePath];
                NSMutableArray *taskArgs = [NSMutableArray arrayWithObjects: @"-f", makefilePath, nil];
                [taskArgs addObjectsFromArray: extraArgs];
                [task setArguments: taskArgs];
                [task setEnvironment: [[NSProcessInfo processInfo] environment]];
                NSPipe *pipe = [[NSPipe alloc] init];
                [task setStandardOutput: pipe];
                [task setStandardError: pipe];
                NSFileHandle *handle = [pipe fileHandleForReading];
                [task launch];
                while (1) {
                    NSData *data = [handle availableData];
                    if (data.length == 0) {
                        if ([task isRunning]) {
                            [NSThread sleepForTimeInterval: 0.1];
                        } else {
                            break;
                        }
                    } else {
                        NSString *str = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
                        write(STDERR_FILENO, [str UTF8String], [str length]);
                    }
                }
                exit([task terminationStatus]);
            } else {
                fprintf(stderr, "Usage: %s -makefilePath <GNUmakefile> [extra gmake args...]\n",
                        [[args objectAtIndex: 0] UTF8String]);
                exit(1);
            }
        } else {
            // GUI mode
            BuildApplication *app = (BuildApplication *)[BuildApplication sharedApplication];
            [app setDelegate: app];
            [(BuildApplication *)app setMakefilePath: makefilePath];
            [(BuildApplication *)app setExtraArgs: extraArgs];
            [app run];
        }
        return 0;
    }
}
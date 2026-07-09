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
            } else if ([arg isEqualToString: @"-GSFilePath"]) {
                nextIsMakefile = YES;
            } else if ([arg isEqualToString: @"-h"] || [arg isEqualToString: @"-help"]) {
                fprintf(stdout, "Usage: %s [-makefilePath <GNUmakefile>] [extra gmake args...]\n"
                                "\n"
                                "Options:\n"
                                "  -makefilePath <path>  Path to the GNUmakefile to build\n"
                                "  -h, -help            Show this help message\n"
                                "\n"
                                "The build always runs 'make clean' first.\n"
                                "In GUI mode, use the file dialog if no path is given.\n",
                        [[args objectAtIndex: 0] UTF8String]);
                exit(0);
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
                NSString *dir = [makefilePath stringByDeletingLastPathComponent];
                if ([dir length] == 0) dir = @".";
                NSString *makePath = [NSTask launchPathForTool: @"gmake"];
                if (!makePath) makePath = [NSTask launchPathForTool: @"make"];

                // Run pre-build steps (autoreconf, configure)
                NSFileManager *fm = [NSFileManager defaultManager];
                NSString *configureAc = [dir stringByAppendingPathComponent: @"configure.ac"];
                NSString *configureIn = [dir stringByAppendingPathComponent: @"configure.in"];
                NSString *configure = [dir stringByAppendingPathComponent: @"configure"];
                NSString *makefileIn = [dir stringByAppendingPathComponent: @"GNUmakefile.in"];

                if ([fm fileExistsAtPath: configureAc] || [fm fileExistsAtPath: configureIn]) {
                    NSString *src = [fm fileExistsAtPath: configureAc] ? configureAc : configureIn;
                    BOOL needsAutoreconf = NO;
                    if (![fm fileExistsAtPath: configure]) {
                        needsAutoreconf = YES;
                    } else {
                        NSDictionary *sAttr = [fm attributesOfItemAtPath: src error: NULL];
                        NSDictionary *cAttr = [fm attributesOfItemAtPath: configure error: NULL];
                        if (sAttr && cAttr && [[sAttr fileModificationDate] laterDate: [cAttr fileModificationDate]] == [sAttr fileModificationDate])
                            needsAutoreconf = YES;
                    }
                    if (needsAutoreconf) {
                        NSString *ar = [NSTask launchPathForTool: @"autoreconf"];
                        if (ar) {
                            fprintf(stderr, "Running autoreconf -i in %s\n", [dir UTF8String]);
                            system([[NSString stringWithFormat: @"cd '%@' && autoreconf -i 2>&1", dir] UTF8String]);
                        }
                    }
                }

                if ([fm fileExistsAtPath: makefileIn]) {
                    NSString *makefileLocal = [dir stringByAppendingPathComponent: @"GNUmakefile"];
                    BOOL needsConfigure = ![fm fileExistsAtPath: makefileLocal];
                    if (!needsConfigure) {
                        NSDictionary *inAttr = [fm attributesOfItemAtPath: makefileIn error: NULL];
                        NSDictionary *mkAttr = [fm attributesOfItemAtPath: makefileLocal error: NULL];
                        if (inAttr && mkAttr && [[inAttr fileModificationDate] laterDate: [mkAttr fileModificationDate]] == [inAttr fileModificationDate])
                            needsConfigure = YES;
                    }
                    if (needsConfigure) {
                        if ([fm isExecutableFileAtPath: configure]) {
                            fprintf(stderr, "Running ./configure in %s\n", [dir UTF8String]);
                            system([[NSString stringWithFormat: @"cd '%@' && ./configure 2>&1", dir] UTF8String]);
                        } else if ([fm fileExistsAtPath: configure]) {
                            fprintf(stderr, "Running sh configure in %s\n", [dir UTF8String]);
                            system([[NSString stringWithFormat: @"cd '%@' && sh configure 2>&1", dir] UTF8String]);
                        }
                    }
                }

                if (!makePath) {
                    fprintf(stderr, "Error: neither gmake nor make found in PATH\n");
                    exit(1);
                }

                NSTask *task = [[NSTask alloc] init];
                [task setCurrentDirectoryPath: dir];
                [task setLaunchPath: makePath];
                NSMutableArray *taskArgs = [NSMutableArray arrayWithObjects: @"-f", makefilePath, @"clean", nil];
                [taskArgs addObjectsFromArray: extraArgs];
                [taskArgs addObject: @"all"];
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
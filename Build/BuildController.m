/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildController.h"

@implementation BuildController

@synthesize makefilePath;

- (id)init
{
    self = [super init];
    if (self) {
        self.buildOutput = [[NSMutableString alloc] init];
        self.consoleMode = NO;
    }
    return self;
}

- (void)showWindow
{
    if (!getenv("DISPLAY")) {
        // Headless mode, just start build without GUI
        if (makefilePath) {
            [self startBuild];
        }
        return;
    }

    // Create window
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                         styleMask: NSTitledWindowMask | NSClosableWindowMask
                                           backing: NSBackingStoreBuffered
                                             defer: NO];

    [window setTitle: @"Build"];
    [window setDelegate: self];

    // Create status label
    statusLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 240, 360, 24)];
    [statusLabel setStringValue: @"Building..."];
    [statusLabel setEditable: NO];
    [statusLabel setBordered: NO];
    [statusLabel setDrawsBackground: NO];
    [statusLabel setAlignment: NSCenterTextAlignment];
    [statusLabel setFont: [NSFont fontWithName: @"Courier" size: 12.0]];
    [[window contentView] addSubview: statusLabel];

    // Create progress bar
    progressBar = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(20, 200, 360, 20)];
    [progressBar setStyle: NSProgressIndicatorBarStyle];
    [progressBar setIndeterminate: NO];
    [progressBar setMinValue: 0.0];
    [progressBar setMaxValue: 100.0];
    [progressBar setDoubleValue: 0.0];
    [[window contentView] addSubview: progressBar];

    // Create output text view
    outputScrollView = [[NSScrollView alloc] initWithFrame: NSMakeRect(20, 20, 360, 160)];
    [outputScrollView setBorderType: NSBezelBorder];
    [outputScrollView setHasVerticalScroller: YES];
    [outputScrollView setHasHorizontalScroller: YES];
    [outputScrollView setAutohidesScrollers: YES];

    outputView = [[NSTextView alloc] initWithFrame: [[outputScrollView contentView] frame]];
    [outputView setEditable: NO];
    [outputView setRichText: NO];
    [outputView setFont: [NSFont fontWithName: @"Courier" size: 10.0]];
    [outputScrollView setDocumentView: outputView];
    [[window contentView] addSubview: outputScrollView];

    [window makeKeyAndOrderFront: self];

    // Start build if makefile path is provided, otherwise show file dialog
    if (makefilePath) {
        [self startBuild];
    } else {
        [self showFileOpenDialog];
    }
}

- (void)startBuild
{
    // Clear previous output
    [self.buildOutput setString: @""];

    if (!makefilePath) {
        if (statusLabel) [statusLabel setStringValue: @"Error: No GNUmakefile specified"];
        return;
    }

    // Resolve to absolute path if needed
    if (![makefilePath hasPrefix: @"/"]) {
        NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        makefilePath = [currentDir stringByAppendingPathComponent: makefilePath];
        makefilePath = [makefilePath stringByStandardizingPath];
        self.makefilePath = makefilePath;
    }

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath: makefilePath]) {
        if (statusLabel) [statusLabel setStringValue: [NSString stringWithFormat: @"Error: GNUmakefile not found: %@", makefilePath]];
        return;
    }

    // Get directory containing the makefile
    NSString *directory = [makefilePath stringByDeletingLastPathComponent];
    if ([directory length] == 0) {
        directory = @".";
    }

    // Create task
    buildTask = [[NSTask alloc] init];
    [buildTask setCurrentDirectoryPath: directory];
    NSString *gmakePath = [NSTask launchPathForTool: @"gmake"];
    if (!gmakePath) {
        if (statusLabel) [statusLabel setStringValue: @"Error: gmake not found in PATH"];
        return;
    }
    [buildTask setLaunchPath: gmakePath];
    NSMutableArray *taskArgs = [NSMutableArray arrayWithObjects: @"-f", makefilePath, nil];
    if (self.extraArgs) {
        [taskArgs addObjectsFromArray: self.extraArgs];
    }
    [buildTask setArguments: taskArgs];
    [buildTask setEnvironment: [[NSProcessInfo processInfo] environment]];

    // Create output pipe and connect to task
    outputPipe = [[NSPipe alloc] init];
    [buildTask setStandardOutput: outputPipe];
    [buildTask setStandardError: outputPipe];

    // Set up notification for task termination
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(taskDidTerminate:)
                                                 name: NSTaskDidTerminateNotification
                                               object: buildTask];

    // Set up notification for output
    NSFileHandle *outputHandle = [outputPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(outputAvailable:)
                                                 name: NSFileHandleReadCompletionNotification
                                               object: outputHandle];

    [outputHandle readInBackgroundAndNotify];

    // Start the task
    @try {
        [buildTask launch];
    } @catch (NSException *exception) {
        if (statusLabel) [statusLabel setStringValue: [NSString stringWithFormat: @"Error: Failed to start build: %@", [exception reason]]];
        return;
    }
}

- (void)showFileOpenDialog
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setTitle: @"Select GNUmakefile"];
    [openPanel setCanChooseFiles: YES];
    [openPanel setCanChooseDirectories: YES];
    [openPanel setAllowsMultipleSelection: NO];

    NSString *defaultDir = @"/Developer/Library/Sources";
    if ([[NSFileManager defaultManager] fileExistsAtPath: defaultDir]) {
        [openPanel setDirectoryURL: [NSURL fileURLWithPath: defaultDir]];
    }

    [openPanel beginSheetModalForWindow: window
                      completionHandler: ^(NSInteger result) {
        if (result == NSModalResponseOK) {
            NSArray *urls = [openPanel URLs];
            if ([urls count] > 0) {
                NSString *path = [[urls objectAtIndex: 0] path];
                BOOL isDir = NO;
                [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir];
                if (isDir) {
                    for (NSString *name in @[@"GNUmakefile", @"GNUmakefile.in"]) {
                        NSString *mf = [path stringByAppendingPathComponent: name];
                        if ([[NSFileManager defaultManager] fileExistsAtPath: mf]) {
                            self.makefilePath = mf;
                            [self startBuild];
                            return;
                        }
                    }
                } else {
                    self.makefilePath = path;
                    [self startBuild];
                }
            }
        }
    }];
}

- (void)outputAvailable:(NSNotification *)notification
{
    NSData *data = [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem];
    if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        [self.buildOutput appendString: output];

        // Write to stdout for verbose output
        NSFileHandle *stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
        [stdoutHandle writeData: data];

        // Update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update output view
            if (outputView) {
                [outputView setString: self.buildOutput];
                [outputView scrollRangeToVisible: NSMakeRange([[outputView string] length], 0)];
            }
        });

        // Continue reading
        [[notification object] readInBackgroundAndNotify];
    }
}

- (void)taskDidTerminate:(NSNotification *)notification
{
    NSTask *task = [notification object];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildFinished: task];
    });
}

- (void)buildFinished:(NSTask *)task
{
    int status = [task terminationStatus];

    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSTaskDidTerminateNotification
                                                  object: task];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSFileHandleReadCompletionNotification
                                                  object: nil];
    buildTask = nil;
    outputPipe = nil;

    if (self.consoleMode) {
        if (status == 0) {
            exit(0);
        } else {
            exit(status);
        }
    }

    if (statusLabel) {
        [statusLabel setStringValue: (status == 0) ? @"Build completed successfully" : @"Build failed"];
    }
    if (progressBar) {
        [progressBar setDoubleValue: (status == 0) ? 100.0 : 0.0];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: (status == 0) ? @"Build Succeeded" : @"Build Failed"];
    [alert setInformativeText: (status == 0)
        ? @"The build completed successfully."
        : [self formatErrorOutput: self.buildOutput]];

    if (status == 0) {
        [alert addButtonWithTitle: @"Install and Launch"];
        [alert addButtonWithTitle: @"Install"];
    }
    [alert addButtonWithTitle: @"OK"];

    NSInteger button = [alert runModal];

    if (status == 0 && button != NSAlertThirdButtonReturn) {
        [self startInstallWithLaunch: (button == NSAlertFirstButtonReturn)];
        return;
    }

    [self.buildOutput setString: @""];
    [NSApp terminate: self];
}

- (void)startInstallWithLaunch:(BOOL)shouldLaunch
{
    if (!makefilePath) return;

    installShouldLaunch = shouldLaunch;

    if (statusLabel) [statusLabel setStringValue: @"Installing..."];
    if (progressBar) {
        [progressBar setIndeterminate: YES];
        [progressBar startAnimation: self];
    }
    [self.buildOutput setString: @""];
    if (outputView) [outputView setString: @""];

    NSString *directory = [makefilePath stringByDeletingLastPathComponent];
    if ([directory length] == 0) directory = @".";

    NSString *gmakePath = [NSTask launchPathForTool: @"gmake"];
    if (!gmakePath) {
        if (statusLabel) [statusLabel setStringValue: @"Error: gmake not found in PATH"];
        return;
    }

    installTask = [[NSTask alloc] init];
    [installTask setCurrentDirectoryPath: directory];
    [installTask setLaunchPath: @"/usr/bin/sudo"];
    [installTask setArguments: @[@"-E", gmakePath, @"-f", makefilePath, @"install"]];
    [installTask setEnvironment: [[NSProcessInfo processInfo] environment]];

    installPipe = [[NSPipe alloc] init];
    [installTask setStandardOutput: installPipe];
    [installTask setStandardError: installPipe];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(installDidTerminate:)
                                                 name: NSTaskDidTerminateNotification
                                               object: installTask];

    NSFileHandle *handle = [installPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(installOutputAvailable:)
                                                 name: NSFileHandleReadCompletionNotification
                                               object: handle];
    [handle readInBackgroundAndNotify];

    @try {
        [installTask launch];
    } @catch (NSException *exception) {
        if (statusLabel) [statusLabel setStringValue: [NSString stringWithFormat: @"Install failed: %@", [exception reason]]];
        installTask = nil;
        installPipe = nil;
    }
}

- (void)installOutputAvailable:(NSNotification *)notification
{
    NSData *data = [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem];
    if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        [self.buildOutput appendString: output];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (outputView) {
                [outputView setString: self.buildOutput];
                [outputView scrollRangeToVisible: NSMakeRange([[outputView string] length], 0)];
            }
        });

        [[notification object] readInBackgroundAndNotify];
    }
}

- (void)installDidTerminate:(NSNotification *)notification
{
    NSTask *task = [notification object];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installFinished: task];
    });
}

- (void)installFinished:(NSTask *)task
{
    int status = [task terminationStatus];

    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSTaskDidTerminateNotification
                                                  object: task];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSFileHandleReadCompletionNotification
                                                  object: nil];
    installTask = nil;
    installPipe = nil;

    if (progressBar) {
        [progressBar stopAnimation: self];
        [progressBar setIndeterminate: NO];
    }

    if (status == 0) {
        if (statusLabel) [statusLabel setStringValue: @"Install completed"];

        if (installShouldLaunch) {
            NSString *appName = [self appNameFromMakefile];
            if (appName) {
                [[NSWorkspace sharedWorkspace] findApplications];
                NSString *appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication: appName];
                if (appPath) {
                    [[NSWorkspace sharedWorkspace] launchApplication: appPath];
                    [self performSelector: @selector(terminateAfterDelay)
                               withObject: nil
                               afterDelay: 2.0];
                    return;
                }
                if (statusLabel) [statusLabel setStringValue: @"Launch failed - app not found"];
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText: @"Launch Failed"];
                [alert setInformativeText: [NSString stringWithFormat:
                    @"Could not find installed \"%@\" application.", appName]];
                [alert addButtonWithTitle: @"OK"];
                [alert runModal];
            }
        } else {
            NSString *title = @"Install Succeeded";
            NSString *msg = @"The application was installed successfully.";
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText: title];
            [alert setInformativeText: msg];
            [alert addButtonWithTitle: @"OK"];
            [alert runModal];
        }
    } else {
        if (statusLabel) [statusLabel setStringValue: @"Install failed"];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText: @"Install Failed"];
        [alert setInformativeText: [self formatErrorOutput: self.buildOutput]];
        [alert addButtonWithTitle: @"OK"];
        [alert runModal];
    }

    [self terminateAfterDelay];
}

- (void)terminateAfterDelay
{
    [self.buildOutput setString: @""];
    [NSApp terminate: self];
}

- (NSString *)appNameFromMakefile
{
    NSString *content = [NSString stringWithContentsOfFile: makefilePath
                                                  encoding: NSUTF8StringEncoding
                                                     error: NULL];
    if (!content) return nil;

    NSArray *lines = [content componentsSeparatedByString: @"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix: @"APP_NAME"]) {
            NSScanner *scanner = [NSScanner scannerWithString: trimmed];
            [scanner scanUpToString: @"=" intoString: NULL];
            [scanner scanString: @"=" intoString: NULL];
            NSString *name = nil;
            [scanner scanUpToString: @"\n" intoString: &name];
            name = [name stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
            if ([name length] > 0) return name;
        }
    }
    return nil;
}

- (NSString *)formatErrorOutput:(NSString *)output
{
    NSArray *lines = [output componentsSeparatedByString: @"\n"];

    // Remove empty lines at the end
    NSMutableArray *cleanLines = [NSMutableArray array];
    for (NSString *line in lines) {
        if ([line length] > 0) {
            [cleanLines addObject: line];
        }
    }

    NSUInteger totalLines = [cleanLines count];
    if (totalLines == 0) {
        return @"No output captured";
    }

    NSMutableString *formattedOutput = [NSMutableString string];

    // First 5 lines
    NSUInteger firstCount = MIN(5, totalLines);
    for (NSUInteger i = 0; i < firstCount; i++) {
        [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex: i]];
    }

    if (totalLines > 5) {
        [formattedOutput appendString:@"...\n"];

        // Last 25 lines
        NSUInteger lastCount = MIN(25, totalLines - 5);
        NSUInteger startIndex = totalLines - lastCount;
        for (NSUInteger i = startIndex; i < totalLines; i++) {
            [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex: i]];
        }
    }

    return formattedOutput;
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (buildTask && [buildTask isRunning]) {
        [buildTask terminate];
    }
    if (installTask && [installTask isRunning]) {
        [installTask terminate];
    }

    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [NSApp terminate: self];
}

@end
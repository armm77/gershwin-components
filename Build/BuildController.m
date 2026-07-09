/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildController.h"

#pragma mark - Metrics (from AppearanceMetrics.h)

static const CGFloat kWinWidth = 400.0;
static const CGFloat kSideMargin = 24.0;
static const CGFloat kBottomMargin = 20.0;
static const CGFloat kBtnHeight = 20.0;
static const CGFloat kBtnWide = 100.0;
static const CGFloat kBtnHSpace = 10.0;
static const CGFloat kBarHeight = 20.0;
static const CGFloat kLineHeight = 18.0;

#pragma mark - BWLogWindowController

@interface BWLogWindowController : NSWindowController
{
    NSScrollView *_scrollView;
    NSTextView *_logView;
}
- (void)appendLog:(NSString *)text;
- (void)clearLog;
@end

@implementation BWLogWindowController

- (instancetype)init
{
    NSRect screenFrame = NSMakeRect(0, 0, 800, 600);
    NSScreen *screen = [NSScreen mainScreen];
    if (screen) {
        screenFrame = [screen frame];
    }
    CGFloat logHeight = screenFrame.size.height / 4.0;
    NSRect logFrame = NSMakeRect(screenFrame.origin.x,
                                  screenFrame.origin.y,
                                  screenFrame.size.width,
                                  logHeight);
    NSWindow *logWindow = [[NSWindow alloc]
        initWithContentRect:logFrame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    [logWindow setTitle:@"Build Log"];
    [logWindow setMinSize:NSMakeSize(400, 100)];

    self = [super initWithWindow:logWindow];
    if (self)
    {
        NSView *contentView = [logWindow contentView];
        NSRect frame = [contentView bounds];

        _scrollView = [[NSScrollView alloc] initWithFrame:frame];
        [_scrollView setHasVerticalScroller:YES];
        [_scrollView setHasHorizontalScroller:NO];
        [_scrollView setBorderType:NSNoBorder];
        [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        NSSize contentSize = [_scrollView contentSize];
        _logView = [[NSTextView alloc]
            initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        [_logView setMinSize:NSMakeSize(0.0, contentSize.height)];
        [_logView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [_logView setVerticallyResizable:YES];
        [_logView setHorizontallyResizable:NO];
        [_logView setEditable:NO];
        [_logView setSelectable:YES];
        [_logView setFont:[NSFont userFixedPitchFontOfSize:10]];
        [_logView setTextColor:[NSColor darkGrayColor]];
        [_logView setBackgroundColor:[NSColor whiteColor]];
        [[_logView textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
        [[_logView textContainer] setWidthTracksTextView:YES];

        [_scrollView setDocumentView:_logView];
        [contentView addSubview:_scrollView];
    }
    return self;
}

- (void)appendLog:(NSString *)text
{
    if (!text || !_logView) return;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont userFixedPitchFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor darkGrayColor]
    };
    NSAttributedString *astr = [[NSAttributedString alloc] initWithString:text
                                                               attributes:attrs];
    [[_logView textStorage] appendAttributedString:astr];
    [_logView scrollRangeToVisible:NSMakeRange([[_logView string] length], 0)];
}

- (void)clearLog
{
    if (!_logView) return;
    [[_logView textStorage] replaceCharactersInRange:
        NSMakeRange(0, [[_logView string] length]) withString:@""];
}

@end

#pragma mark - BuildController

@implementation BuildController

@synthesize makefilePath;

- (id)init
{
    self = [super init];
    if (self) {
        self.buildOutput = [[NSMutableString alloc] init];
        self.consoleMode = NO;
        _logController = [[BWLogWindowController alloc] init];
        [[_logController window] setDelegate:self];
    }
    return self;
}

- (void)setupMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    /* Application Menu */
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:appName
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appMenu addItemWithTitle:@"About"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];

    /* Edit Menu */
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];

    /* Window Menu */
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window"
                                                           action:nil
                                                    keyEquivalent:@""];
    [mainMenu addItem:windowMenuItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Build Log"
                          action:@selector(showLog:)
                   keyEquivalent:@"l"];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front"
                          action:@selector(arrangeInFront:)
                   keyEquivalent:@""];
    [windowMenuItem setSubmenu:windowMenu];
    [NSApp setWindowsMenu:windowMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)createProgressWindow
{
    if (_window) return;

    CGFloat contentW = kWinWidth - 2 * kSideMargin;
    CGFloat btnRight = kWinWidth - kSideMargin;
    CGFloat textW = kWinWidth - kSideMargin - kSideMargin;

    CGFloat winH = kBottomMargin + kBtnHeight + kBtnHSpace + kBarHeight + kBtnHSpace + kLineHeight + 15;
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWinWidth, winH)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    CGFloat y = kBottomMargin;

    /* Cancel button (lower-right) */
    CGFloat cancelX = btnRight - kBtnWide;
    _cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(cancelX, y, kBtnWide, kBtnHeight)];
    [_cancelButton setTitle:@"Cancel"];
    [_cancelButton setTarget:self];
    [_cancelButton setAction:@selector(cancelClicked:)];
    [_cancelButton setKeyEquivalent:@"\e"];
    [_cancelButton setEnabled:NO];
    [[_window contentView] addSubview:_cancelButton];

    y += kBtnHeight + kBtnHSpace;

    /* Progress bar */
    CGFloat barX = kSideMargin;
    CGFloat barW = contentW;
    _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(barX, y, barW, kBarHeight)];
    [_progressBar setStyle:NSProgressIndicatorBarStyle];
    [_progressBar setIndeterminate:NO];
    [_progressBar setMinValue:0.0];
    [_progressBar setMaxValue:100.0];
    [_progressBar setDoubleValue:0.0];
    [[_window contentView] addSubview:_progressBar];

    y += kBarHeight + kBtnHSpace;

    /* Status field */
    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(kSideMargin, y, textW, kLineHeight)];
    [_statusField setStringValue:@"Ready"];
    [_statusField setBezeled:NO];
    [_statusField setDrawsBackground:NO];
    [_statusField setEditable:NO];
    [_statusField setSelectable:NO];
    [_statusField setAlignment:NSTextAlignmentLeft];
    [_statusField setFont:[NSFont systemFontOfSize:11.0]];
    [[_window contentView] addSubview:_statusField];

    [_window setTitle:@"Build"];
    [_window setDelegate:self];
    [_window center];
    [_window orderFront:nil];
}

- (void)showWindow
{
    if (!getenv("DISPLAY")) {
        if (makefilePath) {
            [self startBuild];
        }
        return;
    }

    [self setupMenu];

    if (makefilePath) {
        [self createProgressWindow];
        [self startBuild];
    } else {
        [self showFileOpenDialog];
    }
}

#pragma mark - Actions

- (void)cancelClicked:(id)sender
{
    if (buildTask && [buildTask isRunning]) {
        [buildTask terminate];
    }
    if (installTask && [installTask isRunning]) {
        [installTask terminate];
    }
}

- (void)showLog:(id)sender
{
    NSLog(@"showLog: called");
    if (!_logController) {
        NSLog(@"showLog: _logController is nil");
        return;
    }
    NSWindow *logWin = [_logController window];
    if (!logWin) {
        NSLog(@"showLog: logWin is nil");
        return;
    }
    NSLog(@"showLog: ordering front log window %@", logWin);
    dispatch_async(dispatch_get_main_queue(), ^{
        [logWin orderFront:nil];
        [logWin makeKeyWindow];
        NSLog(@"showLog: window shown");
    });
    NSLog(@"showLog: done (deferred)");
}

#pragma mark - Build

- (BOOL)runSyncTask:(NSString *)launchPath arguments:(NSArray *)args
          directory:(NSString *)dir logPrefix:(NSString *)prefix
{
    NSTask *task = [[NSTask alloc] init];
    [task setCurrentDirectoryPath:dir];
    [task setLaunchPath:launchPath];
    [task setArguments:args];
    [task setEnvironment:[[NSProcessInfo processInfo] environment]];

    NSPipe *pipe = [[NSPipe alloc] init];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    NSString *log = [NSString stringWithFormat:@"=== %@ ===\n", prefix];
    [_logController appendLog:log];
    write(STDOUT_FILENO, [log UTF8String], [log length]);

    @try {
        [task launch];

        NSFileHandle *handle = [pipe fileHandleForReading];
        while ([task isRunning]) {
            NSData *data = [handle availableData];
            if ([data length] > 0) {
                NSString *outStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                [self.buildOutput appendString:outStr];
                [_logController appendLog:outStr];
                write(STDOUT_FILENO, [data bytes], [data length]);
            }
        }
        // Read remaining data
        NSData *remaining = [handle readDataToEndOfFile];
        if ([remaining length] > 0) {
            NSString *outStr = [[NSString alloc] initWithData:remaining encoding:NSUTF8StringEncoding];
            [self.buildOutput appendString:outStr];
            [_logController appendLog:outStr];
            write(STDOUT_FILENO, [remaining bytes], [remaining length]);
        }

        return [task terminationStatus] == 0;
    } @catch (NSException *exception) {
        NSString *err = [NSString stringWithFormat:@"%@ failed: %@\n", prefix, [exception reason]];
        [_logController appendLog:err];
        write(STDOUT_FILENO, [err UTF8String], [err length]);
        return NO;
    }
}

- (NSString *)resolveMakePath
{
    NSString *path = [NSTask launchPathForTool:@"gmake"];
    return path ?: [NSTask launchPathForTool:@"make"];
}

- (void)runPrebuildStepsInDirectory:(NSString *)directory
{
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. autoreconf if needed
    BOOL needsAutoreconf = NO;
    NSString *configureAc = [directory stringByAppendingPathComponent:@"configure.ac"];
    NSString *configureIn = [directory stringByAppendingPathComponent:@"configure.in"];
    NSString *configure = [directory stringByAppendingPathComponent:@"configure"];
    NSString *makefileIn = [directory stringByAppendingPathComponent:@"GNUmakefile.in"];

    if ([fm fileExistsAtPath:configureAc] || [fm fileExistsAtPath:configureIn]) {
        NSString *src = [fm fileExistsAtPath:configureAc] ? configureAc : configureIn;
        if (![fm fileExistsAtPath:configure]) {
            needsAutoreconf = YES;
        } else {
            NSDictionary *srcAttr = [fm attributesOfItemAtPath:src error:NULL];
            NSDictionary *cfgAttr = [fm attributesOfItemAtPath:configure error:NULL];
            if (srcAttr && cfgAttr &&
                [[srcAttr fileModificationDate] laterDate:[cfgAttr fileModificationDate]] == [srcAttr fileModificationDate]) {
                needsAutoreconf = YES;
            }
        }
    }

    if (needsAutoreconf) {
        if (_statusField) [_statusField setStringValue:@"Running autoreconf…"];
        NSString *autoreconfPath = [NSTask launchPathForTool:@"autoreconf"];
        if (autoreconfPath) {
            BOOL ok = [self runSyncTask:autoreconfPath
                              arguments:@[@"-i"]
                              directory:directory
                              logPrefix:@"autoreconf"];
            if (!ok) {
                if (_statusField) [_statusField setStringValue:@"autoreconf failed"];
                return;
            }
        }
    }

    // 2. Run configure if present
    if ([fm fileExistsAtPath:makefileIn]) {
        // If GNUmakefile.in exists but no GNUmakefile yet (or .in is newer), run configure
        NSString *makefilePathLocal = [directory stringByAppendingPathComponent:@"GNUmakefile"];
        BOOL needsConfigure = ![fm fileExistsAtPath:makefilePathLocal];
        if (!needsConfigure) {
            NSDictionary *inAttr = [fm attributesOfItemAtPath:makefileIn error:NULL];
            NSDictionary *mkAttr = [fm attributesOfItemAtPath:makefilePathLocal error:NULL];
            if (inAttr && mkAttr &&
                [[inAttr fileModificationDate] laterDate:[mkAttr fileModificationDate]] == [inAttr fileModificationDate]) {
                needsConfigure = YES;
            }
        }
        if (needsConfigure) {
            if ([fm isExecutableFileAtPath:configure]) {
                if (_statusField) [_statusField setStringValue:@"Running configure…"];
                [self runSyncTask:configure
                        arguments:@[]
                        directory:directory
                        logPrefix:@"configure"];
            } else if ([fm fileExistsAtPath:configure]) {
                if (_statusField) [_statusField setStringValue:@"Running configure (sh)…"];
                [self runSyncTask:@"/bin/sh"
                        arguments:@[configure]
                        directory:directory
                        logPrefix:@"configure"];
            }
        }
    }
}

- (void)startBuild
{
    [self.buildOutput setString:@""];
    [_logController clearLog];

    if (!makefilePath) {
        if (_statusField) [_statusField setStringValue:@"Error: No GNUmakefile specified"];
        else fprintf(stderr, "Error: No GNUmakefile specified\n");
        return;
    }

    if (![makefilePath hasPrefix:@"/"]) {
        NSString *currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        makefilePath = [currentDir stringByAppendingPathComponent:makefilePath];
        makefilePath = [makefilePath stringByStandardizingPath];
        self.makefilePath = makefilePath;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:makefilePath]) {
        NSString *msg = [NSString stringWithFormat:@"Error: GNUmakefile not found: %@", makefilePath];
        if (_statusField) [_statusField setStringValue:msg];
        else fprintf(stderr, "%s\n", [msg UTF8String]);
        return;
    }

    NSString *directory = [makefilePath stringByDeletingLastPathComponent];
    if ([directory length] == 0) directory = @".";

    NSString *makePath = [self resolveMakePath];
    if (!makePath) {
        if (_statusField) [_statusField setStringValue:@"Error: neither gmake nor make found in PATH"];
        else fprintf(stderr, "Error: neither gmake nor make found in PATH\n");
        return;
    }

    if (_cancelButton) [_cancelButton setEnabled:YES];
    if (_progressBar) {
        [_progressBar setIndeterminate:YES];
        [_progressBar startAnimation:nil];
    }

    [self runPrebuildStepsInDirectory:directory];

    if (_statusField) [_statusField setStringValue:@"Building…"];
    if (_window) [_window setTitle:@"Building…"];
    else fprintf(stderr, "Building…\n");
    [_logController appendLog:@"=== Build started ===\n"];

    buildTask = [[NSTask alloc] init];
    [buildTask setCurrentDirectoryPath:directory];
    [buildTask setLaunchPath:makePath];
    NSMutableArray *taskArgs = [NSMutableArray arrayWithObjects:@"-f", makefilePath, @"clean", nil];
    if (self.extraArgs) {
        [taskArgs addObjectsFromArray:self.extraArgs];
    }
    [taskArgs addObject:@"all"];
    [buildTask setArguments:taskArgs];
    [buildTask setEnvironment:[[NSProcessInfo processInfo] environment]];

    outputPipe = [[NSPipe alloc] init];
    [buildTask setStandardOutput:outputPipe];
    [buildTask setStandardError:outputPipe];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(taskDidTerminate:)
                                                 name:NSTaskDidTerminateNotification
                                               object:buildTask];

    NSFileHandle *outputHandle = [outputPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(outputAvailable:)
                                                 name:NSFileHandleReadCompletionNotification
                                               object:outputHandle];
    [outputHandle readInBackgroundAndNotify];

    @try {
        [buildTask launch];
    } @catch (NSException *exception) {
        [_statusField setStringValue:[NSString stringWithFormat:@"Error: Failed to start build: %@", [exception reason]]];
        [_cancelButton setEnabled:NO];
    }
}

- (void)showFileOpenDialog
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setTitle:@"Select GNUmakefile"];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setAllowsMultipleSelection:NO];

    NSString *defaultDir = @"/Developer/Library/Sources";
    if ([[NSFileManager defaultManager] fileExistsAtPath:defaultDir]) {
        [openPanel setDirectoryURL:[NSURL fileURLWithPath:defaultDir]];
    }

    NSInteger result = [openPanel runModal];
    if (result != NSModalResponseOK) {
        [NSApp terminate:self];
        return;
    }

    NSArray *urls = [openPanel URLs];
    if ([urls count] > 0) {
        NSString *path = [[urls objectAtIndex:0] path];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
        if (isDir) {
            for (NSString *name in @[@"GNUmakefile", @"GNUmakefile.in"]) {
                NSString *mf = [path stringByAppendingPathComponent:name];
                if ([[NSFileManager defaultManager] fileExistsAtPath:mf]) {
                    self.makefilePath = mf;
                    [self createProgressWindow];
                    [self startBuild];
                    return;
                }
            }
        } else {
            self.makefilePath = path;
            [self createProgressWindow];
            [self startBuild];
        }
    }
}

- (void)outputAvailable:(NSNotification *)notification
{
    NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.buildOutput appendString:output];

        write(STDOUT_FILENO, [data bytes], [data length]);

        dispatch_async(dispatch_get_main_queue(), ^{
            [_logController appendLog:output];
        });

        [[notification object] readInBackgroundAndNotify];
    }
}

- (void)taskDidTerminate:(NSNotification *)notification
{
    NSTask *task = [notification object];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self buildFinished:task];
    });
}

- (void)buildFinished:(NSTask *)task
{
    int status = [task terminationStatus];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSTaskDidTerminateNotification
                                                  object:task];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleReadCompletionNotification
                                                  object:nil];

    [_progressBar stopAnimation:nil];
    [_progressBar setIndeterminate:NO];
    [_cancelButton setEnabled:NO];

    if (self.consoleMode) {
        exit(status == 0 ? 0 : status);
    }

    if (status == 0) {
        [_progressBar setDoubleValue:100.0];
        [_statusField setStringValue:@"Build completed successfully"];
        [_window setTitle:@"Build"];
    } else {
        [_statusField setStringValue:@"Build failed"];
        [_window setTitle:@"Build"];
    }

    [_logController appendLog:[NSString stringWithFormat:
        @"\n=== Build %@ (exit %d) ===\n\n", status == 0 ? @"succeeded" : @"failed", status]];

    if (_window) [_window orderOut:nil];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:(status == 0) ? @"Build Succeeded" : @"Build Failed"];
    [alert setInformativeText:(status == 0)
        ? @"The build completed successfully."
        : [self formatErrorOutput:self.buildOutput]];
    if (status == 0) {
        NSImage *check = [NSImage imageNamed:@"check"];
        if (check) [alert setIcon:check];
    }

    if (status == 0) {
        [alert addButtonWithTitle:@"Install and Launch"];
        [alert addButtonWithTitle:@"Install"];
    }
    [alert addButtonWithTitle: (status == 0) ? @"OK" : @"Cancel"];
    if (status != 0) {
        [alert addButtonWithTitle:@"Show Build Log"];
    }

    NSInteger button = [alert runModal];
    NSLog(@"buildFinished: button=%ld (status=%d)", (long)button, status);

    if (status == 0 && button == NSAlertFirstButtonReturn) {
        NSLog(@"buildFinished: Install and Launch");
        [self startInstallWithLaunch:YES];
    } else if (status == 0 && button == NSAlertSecondButtonReturn) {
        NSLog(@"buildFinished: Install");
        [self startInstallWithLaunch:NO];
    } else if (status == 0 && button == NSAlertThirdButtonReturn) {
        NSLog(@"buildFinished: OK -> quit");
        [NSApp stop:self];
        [NSApp terminate:self];
    } else if (status != 0 && button == NSAlertSecondButtonReturn) {
        NSLog(@"buildFinished: Show Build Log");
        [self showLog:nil];
    } else if (status != 0 && button == NSAlertFirstButtonReturn) {
        NSLog(@"buildFinished: Cancel -> quit");
        [NSApp stop:self];
        [NSApp terminate:self];
    }
    NSLog(@"buildFinished: done");
}

#pragma mark - Install

- (void)startInstallWithLaunch:(BOOL)shouldLaunch
{
    if (!makefilePath) return;

    installShouldLaunch = shouldLaunch;

    if (_window) {
        [_window orderFront:nil];
        [_window setTitle:@"Installing…"];
    }
    [_cancelButton setEnabled:YES];
    [_statusField setStringValue:@"Installing…"];
    [_progressBar setIndeterminate:YES];
    [_progressBar startAnimation:nil];
    [self.buildOutput setString:@""];
    [_logController appendLog:@"\n=== Install started ===\n"];

    NSString *directory = [makefilePath stringByDeletingLastPathComponent];
    if ([directory length] == 0) directory = @".";

    NSString *gmakePath = [NSTask launchPathForTool:@"gmake"];
    if (!gmakePath) {
        [_statusField setStringValue:@"Error: gmake not found in PATH"];
        return;
    }

    installTask = [[NSTask alloc] init];
    [installTask setCurrentDirectoryPath:directory];
    [installTask setLaunchPath:@"/usr/bin/sudo"];
    [installTask setArguments:@[@"-E", gmakePath, @"-f", makefilePath, @"install"]];
    [installTask setEnvironment:[[NSProcessInfo processInfo] environment]];

    installPipe = [[NSPipe alloc] init];
    [installTask setStandardOutput:installPipe];
    [installTask setStandardError:installPipe];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(installDidTerminate:)
                                                 name:NSTaskDidTerminateNotification
                                               object:installTask];

    NSFileHandle *handle = [installPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(installOutputAvailable:)
                                                 name:NSFileHandleReadCompletionNotification
                                               object:handle];
    [handle readInBackgroundAndNotify];

    @try {
        [installTask launch];
    } @catch (NSException *exception) {
        [_statusField setStringValue:[NSString stringWithFormat:@"Install failed: %@", [exception reason]]];
        [_cancelButton setEnabled:NO];
        installTask = nil;
        installPipe = nil;
    }
}

- (void)installOutputAvailable:(NSNotification *)notification
{
    NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.buildOutput appendString:output];

        write(STDOUT_FILENO, [data bytes], [data length]);

        dispatch_async(dispatch_get_main_queue(), ^{
            [_logController appendLog:output];
        });

        [[notification object] readInBackgroundAndNotify];
    }
}

- (void)installDidTerminate:(NSNotification *)notification
{
    NSTask *task = [notification object];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installFinished:task];
    });
}

- (void)installFinished:(NSTask *)task
{
    int status = [task terminationStatus];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSTaskDidTerminateNotification
                                                  object:task];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleReadCompletionNotification
                                                  object:nil];
    installTask = nil;
    installPipe = nil;

    [_progressBar stopAnimation:nil];
    [_progressBar setIndeterminate:NO];
    [_cancelButton setEnabled:NO];
    [_window setTitle:@"Build"];

    [_logController appendLog:[NSString stringWithFormat:
        @"\n=== Install %@ (exit %d) ===\n", status == 0 ? @"succeeded" : @"failed", status]];

    if (_window) [_window orderOut:nil];

    NSString *title;
    NSString *msg;
    if (status == 0) {
        [_statusField setStringValue:@"Install completed"];
        title = @"Install Succeeded";
        msg = @"The application was installed successfully.";
    } else {
        [_statusField setStringValue:@"Install failed"];
        title = @"Install Failed";
        msg = [self formatErrorOutput:self.buildOutput];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    [alert setInformativeText:msg];
    if (status == 0) {
        NSImage *check = [NSImage imageNamed:@"check"];
        if (check) [alert setIcon:check];
        [alert addButtonWithTitle:@"OK"];
    } else {
        [alert addButtonWithTitle:@"Cancel"];
        [alert addButtonWithTitle:@"Show Build Log"];
    }
    NSInteger button = [alert runModal];

    if (status != 0) {
        if (button == NSAlertSecondButtonReturn) {
            [self showLog:nil];
            return;
        } else {
            [NSApp stop:self];
            [NSApp terminate:self];
        }
    }

    if (status == 0) {
        if (installShouldLaunch) {
            NSString *appName = [self appNameFromMakefile];
            if (appName) {
                [[NSWorkspace sharedWorkspace] findApplications];
                NSString *appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:appName];
                if (appPath) {
                    [[NSWorkspace sharedWorkspace] launchApplication:appPath];
                    [self performSelector:@selector(terminateAfterDelay)
                               withObject:nil
                               afterDelay:3.0];
                    return;
                }
            }
        }
        [NSApp terminate:self];
        return;
    }
}

- (void)terminateAfterDelay
{
    [NSApp terminate:self];
}

#pragma mark - Helpers

- (NSString *)appNameFromMakefile
{
    NSString *content = [NSString stringWithContentsOfFile:makefilePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    if (!content) return nil;

    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"APP_NAME"]) {
            NSScanner *scanner = [NSScanner scannerWithString:trimmed];
            [scanner scanUpToString:@"=" intoString:NULL];
            [scanner scanString:@"=" intoString:NULL];
            NSString *name = nil;
            [scanner scanUpToString:@"\n" intoString:&name];
            name = [name stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
            if ([name length] > 0) return name;
        }
    }
    return nil;
}

- (NSString *)formatErrorOutput:(NSString *)output
{
    NSArray *lines = [output componentsSeparatedByString:@"\n"];

    NSMutableArray *cleanLines = [NSMutableArray array];
    for (NSString *line in lines) {
        if ([line length] > 0) {
            [cleanLines addObject:line];
        }
    }

    NSUInteger totalLines = [cleanLines count];
    if (totalLines == 0) {
        return @"No output captured";
    }

    NSMutableString *formattedOutput = [NSMutableString string];

    NSUInteger firstCount = MIN(5, totalLines);
    for (NSUInteger i = 0; i < firstCount; i++) {
        [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex:i]];
    }

    if (totalLines > 5) {
        [formattedOutput appendString:@"...\n"];

        NSUInteger lastCount = MIN(25, totalLines - 5);
        NSUInteger startIndex = totalLines - lastCount;
        for (NSUInteger i = startIndex; i < totalLines; i++) {
            [formattedOutput appendFormat:@"%@\n", [cleanLines objectAtIndex:i]];
        }
    }

    return formattedOutput;
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *closingWindow = [notification object];
    if (closingWindow == _window) {
        if (buildTask && [buildTask isRunning]) {
            [buildTask terminate];
        }
        if (installTask && [installTask isRunning]) {
            [installTask terminate];
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [NSApp terminate:self];
    } else if (closingWindow == [_logController window]) {
        BOOL busy = (buildTask && [buildTask isRunning]) || (installTask && [installTask isRunning]);
        if (!busy) {
            [NSApp terminate:self];
        }
    }
}

@end

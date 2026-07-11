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

@interface BuildController ()
@property (strong) NSArray *blacklist;
- (BOOL)isItemBlacklisted:(NSString *)item;
@end

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

    // Count source files from makefile(s) for progress tracking
    _totalFileCount = 0;
    _compiledFileCount = 0;
    NSString *target = [self productNameFromMakefile];
    _totalFileCount = [self countSourceFilesInMakefile:makefilePath
                                                target:target
                                                 depth:0];

    if (_progressBar) {
        if (_totalFileCount > 0) {
            [_progressBar setIndeterminate:NO];
            [_progressBar setMinValue:0];
            [_progressBar setMaxValue:_totalFileCount];
            [_progressBar setDoubleValue:0];
        } else {
            [_progressBar setIndeterminate:YES];
        }
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

        if (_totalFileCount > 0) {
            // Count "Compiling file" lines for progress
            NSUInteger compiled = 0;
            NSUInteger pos = 0;
            while (pos < [output length]) {
                NSRange r = [output rangeOfString:@"Compiling file "
                                         options:0
                                           range:NSMakeRange(pos, [output length] - pos)];
                if (r.location == NSNotFound) break;
                compiled++;
                pos = r.location + r.length;
            }
            if (compiled > 0) {
                _compiledFileCount += compiled;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_progressBar setDoubleValue:MIN(_compiledFileCount, _totalFileCount)];
                });
            }
        }

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

    BOOL canLaunch = NO;
    if (status == 0) {
        NSString *ext = [self productExtensionFromMakefile];
        canLaunch = [ext isEqualToString:@"app"] || [ext isEqualToString:@"prefPane"];
    }

    if (status == 0) {
        if (canLaunch) {
            [alert addButtonWithTitle:@"Install and Launch"];
        }
        [alert addButtonWithTitle:@"Install"];
    }
    [alert addButtonWithTitle: (status == 0) ? @"OK" : @"Cancel"];
    if (status != 0) {
        [alert addButtonWithTitle:@"Show Build Log"];
    }

    NSInteger button = [alert runModal];
    NSLog(@"buildFinished: button=%ld (status=%d, canLaunch=%d)", (long)button, status, canLaunch);

    if (status == 0 && canLaunch && button == NSAlertFirstButtonReturn) {
        NSLog(@"buildFinished: Install and Launch");
        [self startInstallWithLaunch:YES];
    } else if (status == 0 && button == (canLaunch ? NSAlertSecondButtonReturn : NSAlertFirstButtonReturn)) {
        NSLog(@"buildFinished: Install");
        [self startInstallWithLaunch:NO];
    } else if (status == 0) {
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

    if (status != 0) {
        [_statusField setStringValue:@"Install failed"];

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Install Failed"];
        [alert setInformativeText:[self formatErrorOutput:self.buildOutput]];
        [alert addButtonWithTitle:@"Cancel"];
        [alert addButtonWithTitle:@"Show Build Log"];
        NSInteger button = [alert runModal];

        if (button == NSAlertSecondButtonReturn) {
            [self showLog:nil];
            return;
        }
        [NSApp stop:self];
        [NSApp terminate:self];
        return;
    }

    [_statusField setStringValue:@"Install completed"];

    if (installShouldLaunch) {
        NSString *name = [self productNameFromMakefile];
        NSString *ext = [self productExtensionFromMakefile];
        if (name) {
            NSString *productPath = nil;
            if ([ext isEqualToString:@"prefPane"]) {
                NSString *bundlesDir = [NSSearchPathForDirectoriesInDomains(
                    NSLibraryDirectory, NSSystemDomainMask, YES) lastObject];
                bundlesDir = [bundlesDir stringByAppendingPathComponent:@"Bundles"];
                productPath = [[bundlesDir stringByAppendingPathComponent:name]
                    stringByAppendingPathExtension:ext];
                if (![[NSFileManager defaultManager] fileExistsAtPath:productPath]) {
                    productPath = nil;
                }
            } else {
                [[NSWorkspace sharedWorkspace] findApplications];
                productPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:name];
            }
            if (productPath) {
                if ([ext isEqualToString:@"prefPane"]) {
                    [[NSWorkspace sharedWorkspace] launchApplication:@"SystemPreferences"];
                } else {
                    NSString *exec = [productPath stringByAppendingPathComponent:
                        [[productPath lastPathComponent] stringByDeletingPathExtension]];
                    if ([[NSFileManager defaultManager] isExecutableFileAtPath:exec]) {
                        [NSTask launchedTaskWithLaunchPath:exec arguments:@[]];
                    }
                }
                [self performSelector:@selector(terminateAfterDelay)
                           withObject:nil
                           afterDelay:3.0];
                return;
            }
        }

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Launch Failed"];
        [alert setInformativeText:@"The application was installed, but could not be launched.."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }

    [NSApp terminate:self];
}

- (void)terminateAfterDelay
{
    [NSApp terminate:self];
}

#pragma mark - Helpers

- (NSString *)productNameFromMakefile
{
    NSString *content = [NSString stringWithContentsOfFile:makefilePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    if (!content) return nil;

    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"APP_NAME"] || [trimmed hasPrefix:@"BUNDLE_NAME"] ||
            [trimmed hasPrefix:@"TOOL_NAME"]) {
            NSString *name = [self parseVariableValue:trimmed];
            if ([name length] > 0) return name;
        }
    }
    return nil;
}

- (NSInteger)countSourceFilesInMakefile:(NSString *)path
                                  target:(NSString *)target
                                   depth:(NSInteger)depth
{
    if (depth > 3) return 0;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    if (!content) return 0;

    // Join backslash continuation lines
    NSMutableString *joined = [NSMutableString stringWithString:content];
    [joined replaceOccurrencesOfString:@"\\\n"
                            withString:@" "
                               options:0
                                 range:NSMakeRange(0, [joined length])];

    NSInteger count = 0;
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSArray *varNames = @[
        @"OBJC_FILES", @"OBJCXX_FILES", @"C_FILES", @"CC_FILES",
        @"CPP_FILES", @"CXX_FILES", @"OBJCPP_FILES"
    ];
    NSArray *lines = [joined componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];

        // Count source file variables
        for (NSString *var in varNames) {
            NSString *prefixed = target ? [NSString stringWithFormat:@"%@_%@", target, var] : nil;
            if ((prefixed && [trimmed hasPrefix:prefixed]) || [trimmed hasPrefix:var]) {
                NSString *value = [self parseVariableValue:trimmed];
                if ([value length] > 0) {
                    NSArray *parts = [value componentsSeparatedByCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                    for (NSString *part in parts) {
                        if ([part length] > 0 && ![part isEqualToString:@"\\"]) {
                            count++;
                        }
                    }
                }
            }
        }

        // Recurse into local includes (skip system includes with $()
        if ([trimmed hasPrefix:@"include "]) {
            NSString *incPath = [[trimmed substringFromIndex:8]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([incPath hasPrefix:@"$("]) continue;
            if (![incPath isAbsolutePath]) {
                incPath = [dir stringByAppendingPathComponent:incPath];
            }
            incPath = [incPath stringByStandardizingPath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:incPath]) {
                count += [self countSourceFilesInMakefile:incPath
                                                   target:target
                                                    depth:depth + 1];
            }
        }
    }

    return count;
}

- (NSString *)productExtensionFromMakefile
{
    NSString *content = [NSString stringWithContentsOfFile:makefilePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    if (!content) return nil;

    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    BOOL hasBundleName = NO;
    NSString *ext = nil;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"BUNDLE_NAME"]) {
            hasBundleName = YES;
        } else if ([trimmed hasPrefix:@"BUNDLE_EXTENSION"]) {
            ext = [self parseVariableValue:trimmed];
        } else if ([trimmed hasPrefix:@"APP_NAME"]) {
            return @"app";
        } else if ([trimmed hasPrefix:@"TOOL_NAME"]) {
            return @"tool";
        }
    }

    if (hasBundleName) {
        if ([ext length] > 0) {
            // Strip leading dot if present
            if ([ext hasPrefix:@"."]) {
                ext = [ext substringFromIndex:1];
            }
            return ext;
        }
        return @"bundle";
    }

    return @"app";
}

- (NSString *)scanMissingHeaders:(NSArray *)lines
{
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *line in lines) {
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString *header;
        if ([scanner scanUpToString:@"fatal error: '" intoString:NULL]) {
            if ([scanner scanString:@"fatal error: '" intoString:NULL]) {
                if ([scanner scanUpToString:@"' file not found" intoString:&header]) {
                    if ([header length] > 0) {
                        [missing addObject:header];
                    }
                }
            }
        }
    }
    if ([missing count] > 0) {
        return [self formatMissingItems:@"header" items:missing];
    }
    return nil;
}

- (NSString *)scanMissingLibraries:(NSArray *)lines
{
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *line in lines) {
        // GNU ld: /bin/ld: cannot find -lmpv: No such file or directory
        // Apple ld: ld: library not found for -lmpv
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString *lib;
        [scanner scanUpToString:@"cannot find -l" intoString:NULL];
        if ([scanner scanString:@"cannot find -l" intoString:NULL]) {
            NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@": \t"];
            if ([scanner scanUpToCharactersFromSet:stop intoString:&lib]) {
                if ([lib length] > 0) {
                    [missing addObject:lib];
                }
            }
        } else {
            scanner = [NSScanner scannerWithString:line];
            [scanner scanUpToString:@"library not found for -l" intoString:NULL];
            if ([scanner scanString:@"library not found for -l" intoString:NULL]) {
                NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@": \t"];
                if ([scanner scanUpToCharactersFromSet:stop intoString:&lib]) {
                    if ([lib length] > 0) {
                        [missing addObject:lib];
                    }
                }
            }
        }
    }
    if ([missing count] > 0) {
        return [self formatMissingItems:@"library" items:missing];
    }
    return nil;
}

- (BOOL)isItemBlacklisted:(NSString *)item
{
    if (!self.blacklist) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Blacklist" ofType:@"plist"];
        if (path) {
            self.blacklist = [NSArray arrayWithContentsOfFile:path];
        }
        if (!self.blacklist) {
            self.blacklist = @[];
        }
    }
    NSString *stem = [[item lowercaseString] stringByDeletingPathExtension];
    for (NSString *blacklisted in self.blacklist) {
        NSString *b = [blacklisted lowercaseString];
        if ([stem isEqualToString:b]) return YES;
        if ([stem hasPrefix:b]) return YES;
    }
    return NO;
}

- (NSString *)formatMissingItems:(NSString *)kind items:(NSArray *)items
{
    NSMutableArray *allowed = [NSMutableArray array];
    NSMutableArray *blocked = [NSMutableArray array];
    for (NSString *item in items) {
        if ([self isItemBlacklisted:item]) {
            [blocked addObject:item];
        } else {
            [allowed addObject:item];
        }
    }

    NSMutableString *friendly = [NSMutableString string];

    if ([blocked count] > 0) {
        [friendly appendString:@"The build failed because it requires an unsupported technology:\n\n"];
        for (NSString *item in blocked) {
            [friendly appendFormat:@"  • %@\n", item];
        }
    }

    if ([allowed count] > 0) {
        if ([blocked count] > 0) {
            [friendly appendString:@"\nAdditionally, a required package is missing:\n\n"];
        } else {
            [friendly appendFormat:@"The build failed because a required %@ is missing:\n\n", kind];
        }
        for (NSString *item in allowed) {
            [friendly appendFormat:@"  • %@\n", item];
        }
    }

    if ([allowed count] > 0) {
        [friendly appendString:@"\nAfter installing the corresponding development package, try building again."];
    } else if ([blocked count] > 0) {
        [friendly appendString:@"\nPlease consider an alternative, as this technology is not planned to be supported on this system."];
    }
    return friendly;
}

- (NSString *)formatErrorOutput:(NSString *)output
{
    NSArray *lines = [output componentsSeparatedByString:@"\n"];

    NSString *headerMsg = [self scanMissingHeaders:lines];
    if (headerMsg) return headerMsg;

    NSString *libMsg = [self scanMissingLibraries:lines];
    if (libMsg) return libMsg;

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

- (NSString *)parseVariableValue:(NSString *)line
{
    NSScanner *scanner = [NSScanner scannerWithString:line];
    [scanner scanUpToString:@"=" intoString:NULL];
    [scanner scanString:@"=" intoString:NULL];
    NSString *value = nil;
    [scanner scanUpToString:@"\n" intoString:&value];
    return [value stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
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

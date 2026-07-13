/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CatalogController.h"
#import "CatalogEntry.h"
#import "BuildController.h"

/* Layout constants following AppearanceMetrics.h conventions */
static const CGFloat kSideMargin = 24.0;
static const CGFloat kBottomMargin = 20.0;
static const CGFloat kTopMargin = 15.0;
static const CGFloat kBtnHeight = 20.0;
static const CGFloat kBtnWide = 100.0;
static const CGFloat kBtnHSpace = 10.0;
static const CGFloat kSpace16 = 16.0;
static const CGFloat kRowHeight = 20.0;

static const CGFloat kWinWidth = 420.0;
static const CGFloat kWinHeight = 260.0;

@implementation CatalogController

- (id)init
{
    self = [super init];
    if (self) {
        _entries = [[CatalogEntry loadCatalog] retain];
    }
    return self;
}

- (void)dealloc
{
    [_entries release];
    [_window release];
    [_tableView release];
    [_buildButton release];
    [super dealloc];
}

- (void)showWindow
{
    if (_window) {
        [_window orderFront:nil];
        return;
    }

    CGFloat left = kSideMargin;
    CGFloat right = kSideMargin;
    CGFloat contentW = kWinWidth - left - right;
    CGFloat bottom = kBottomMargin;
    CGFloat top = kTopMargin;
    CGFloat btnW = kBtnWide;
    CGFloat btnH = kBtnHeight;

    CGFloat listH = kWinHeight - top - kSpace16 - btnH - bottom;

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWinWidth, kWinHeight)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Build"];
    [_window setMinSize:NSMakeSize(300, 200)];
    [_window setDelegate:(id)self];

    NSView *contentView = [_window contentView];
    CGFloat y = bottom;

    /* Build button (lower-right) */
    CGFloat buildX = kWinWidth - right - btnW;
    _buildButton = [[NSButton alloc] initWithFrame:NSMakeRect(buildX, y, btnW, btnH)];
    [_buildButton setTitle:@"Build"];
    [_buildButton setTarget:self];
    [_buildButton setAction:@selector(buildClicked:)];
    [_buildButton setEnabled:NO];
    [_buildButton setKeyEquivalent:@"\r"];
    [contentView addSubview:_buildButton];

    /* Open button (to the left of Build) */
    CGFloat openX = buildX - kBtnHSpace - btnW;
    NSButton *openButton = [[NSButton alloc] initWithFrame:NSMakeRect(openX, y, btnW, btnH)];
    [openButton setTitle:@"Open\u2026"];
    [openButton setTarget:self];
    [openButton setAction:@selector(openClicked:)];
    [contentView addSubview:openButton];

    y += btnH + kSpace16;

    /* Table view */
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(left, y, contentW, listH)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:NO];
    [scrollView setBorderType:NSBezelBorder];
    [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentW, listH)];
    [_tableView setRowHeight:kRowHeight];
    [_tableView setAllowsMultipleSelection:NO];
    [_tableView setAllowsEmptySelection:NO];
    [_tableView setHeaderView:nil];

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [[column headerCell] setStringValue:@"App"];
    [column setEditable:NO];
    [column setWidth:contentW];
    [_tableView addTableColumn:column];

    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setTarget:self];
    [_tableView setAction:@selector(tableClicked:)];

    [scrollView setDocumentView:_tableView];
    [contentView addSubview:scrollView];

    if ([_entries count] > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [_buildButton setEnabled:YES];
    }

    [_window center];
    [_window orderFront:nil];
}

#pragma mark - List actions

- (void)tableClicked:(id)sender
{
    NSInteger row = [_tableView selectedRow];
    [_buildButton setEnabled:(row >= 0)];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_entries count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)[_entries count]) return nil;
    CatalogEntry *entry = [_entries objectAtIndex:row];
    if (entry.desc) {
        return [NSString stringWithFormat:@"%@ \u2014 %@", entry.name, entry.desc];
    }
    return entry.name;
}

#pragma mark - Actions

- (void)buildClicked:(id)sender
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= (NSInteger)[_entries count]) return;

    CatalogEntry *entry = [_entries objectAtIndex:row];

    NSString *template = [NSString stringWithFormat:@"/tmp/Build-catalog-%@-XXXXXXXX",
                          [entry.name stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    char *tmpPath = strdup([template UTF8String]);
    if (!mkdtemp(tmpPath)) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:@"Could not create temporary directory."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        free(tmpPath);
        return;
    }
    NSString *cloneDir = [[NSString stringWithUTF8String:tmpPath] stringByStandardizingPath];
    free(tmpPath);

    /* Dismiss catalog and show progress window immediately so the user
       sees feedback while the clone runs. */
    [_window orderOut:nil];

    NSString *guessedMakefile = [cloneDir stringByAppendingPathComponent:@"GNUmakefile"];

    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath:guessedMakefile];
    [controller setExtraArgs:@[]];
    [controller setBuildDir:cloneDir];
    [controller showProgressWindow];
    [NSApp updateWindows];

    /* Clone the repository */
    NSTask *gitTask = [[NSTask alloc] init];
    [gitTask setLaunchPath:@"/usr/bin/git"];
    [gitTask setArguments:@[@"clone", @"--depth=1", entry.gitURL, cloneDir]];
    [gitTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [gitTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];

    @try {
        [gitTask launch];
        [gitTask waitUntilExit];
    } @catch (NSException *e) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:[NSString stringWithFormat:@"git clone failed: %@", [e reason]]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    if ([gitTask terminationStatus] != 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:@"git clone returned an error."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *makefilePath = nil;
    for (NSString *name in @[@"GNUmakefile", @"GNUmakefile.in", @"Makefile"]) {
        NSString *mf = [cloneDir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:mf]) {
            makefilePath = mf;
            break;
        }
    }

    if (!makefilePath) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No Makefile Found"];
        [alert setInformativeText:@"The cloned repository does not contain a GNUmakefile or Makefile."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    [controller setMakefilePath:makefilePath];
    [controller startBuild];
}

- (void)openClicked:(id)sender
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
    if (result != NSModalResponseOK) return;

    NSArray *urls = [openPanel URLs];
    if ([urls count] == 0) return;

    NSString *path = [[urls objectAtIndex:0] path];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];

    NSString *makefilePath = nil;
    if (isDir) {
        for (NSString *name in @[@"GNUmakefile", @"GNUmakefile.in", @"Makefile"]) {
            NSString *mf = [path stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] fileExistsAtPath:mf]) {
                makefilePath = mf;
                break;
            }
        }
    } else {
        makefilePath = path;
    }

    if (makefilePath) {
        [self startBuildWithMakefilePath:makefilePath];
    }
}

- (void)startBuildWithMakefilePath:(NSString *)makefilePath
{
    [_window orderOut:nil];

    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath:makefilePath];
    [controller showWindow];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [NSApp terminate:self];
}

@end

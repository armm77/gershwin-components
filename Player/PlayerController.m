/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "PlayerController.h"
#import "AppearanceMetrics.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSSound.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSOpenPanel.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSArray.h>
#import "ItemFlowView.h"

// Forward declarations for internal methods used by DropTargetView
@interface PlayerController () // class extension
- (void)restoreWindowTitle;
- (void)handleDroppedFiles:(NSArray *)filePaths;
- (NSArray *)scanFolderForMediaFiles:(NSString *)folderPath;
@end

// Default window size (content rect, excl. titlebar)
#define DEFAULT_WINDOW_WIDTH   520.0
#define DEFAULT_WINDOW_HEIGHT  370.0

// Minimum content area size
#define PLAYER_CONTENT_MIN_WIDTH   METRICS_WIN_MIN_WIDTH
#define PLAYER_CONTENT_MIN_HEIGHT  320.0

// Height of the cover-art / video area as a fraction of window height
#define COVER_AREA_FRACTION  0.5

// Height of the metadata text block (3 lines + spacing)
#define METADATA_HEIGHT      56.0

// Control bar heights
#define CONTROL_BAR_HEIGHT   22.0
#define SLIDER_BAR_HEIGHT    20.0

// Overlay bar height in fullscreen
#define OVERLAY_BAR_HEIGHT   50.0

// Overlay auto-hide delay (seconds)
#define OVERLAY_HIDE_DELAY   3.0

#pragma mark - DropTargetView (drag-and-drop content view)

@interface DropTargetView : NSView
{
@public
    PlayerController *_controller; // non-retained (back-pointer)
}
@end

@implementation DropTargetView

- (instancetype)initWithFrame:(NSRect)frame controller:(PlayerController *)controller
{
    self = [super initWithFrame:frame];
    if (self) {
        _controller = controller;
        [self registerForDraggedTypes:@[NSFilenamesPboardType]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        [[_controller mainWindow] setTitle:@"Drop files here to add to playlist…"];
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [_controller restoreWindowTitle];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        if ([files count] > 0 && _controller) {
            [_controller handleDroppedFiles:files];
            return YES;
        }
    }
    return NO;
}

@end

#pragma mark -

@implementation PlayerController

@synthesize mainWindow;
@synthesize videoView;
@synthesize flowView;
@synthesize playButton;
@synthesize stopButton;
@synthesize previousButton;
@synthesize nextButton;
@synthesize openButton;
@synthesize fullscreenButton;
@synthesize timeSlider;
@synthesize currentTimeLabel;
@synthesize totalTimeLabel;
@synthesize titleLabel;
@synthesize artistLabel;
@synthesize albumLabel;
@synthesize detailsLabel;
@synthesize progressIndicator;

#pragma mark - Init / Dealloc

- (id)init
{
    self = [super init];
    if (self) {
        playbackState = PlayerPlaybackStateStopped;
        currentFilePath = nil;
        avPlayer = nil;
        playerItem = nil;
        urlAsset = nil;
        audioPlayer = nil;
        playbackTimer = nil;
        overlayHideTimer = nil;
        overlayBar = nil;
        playlist = [[NSMutableArray alloc] init];
        coverImages = [[NSMutableDictionary alloc] init];
        currentIndex = -1;
        isVideo = NO;
        isFullscreen = NO;
        srandom((unsigned int)time(NULL));
        // Load persisted preferences via NSUserDefaults (GNUstep standard)
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        repeatEnabled = [defaults boolForKey:@"PlayerRepeatEnabled"];
        shuffleEnabled = [defaults boolForKey:@"PlayerShuffleEnabled"];
        coverAreaHeight = 200.0;
    }
    return self;
}

- (void)dealloc
{
    if (playbackTimer) {
        [playbackTimer invalidate];
        [playbackTimer release];
    }
    if (overlayHideTimer) {
        [overlayHideTimer invalidate];
        [overlayHideTimer release];
    }
    if (avPlayer) {
        [avPlayer pause];
        [avPlayer release];
    }
    if (playerItem) {
        [playerItem release];
    }
    if (urlAsset) {
        [urlAsset release];
    }
    if (audioPlayer) {
        [audioPlayer stop];
        [audioPlayer release];
    }
    [currentFilePath release];
    [playlist release];
    [coverImages release];
    [detailsLabel release];
    [overlayBar release];
    [super dealloc];
}

#pragma mark - Menu Creation

- (void)createMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // ===== APPLICATION MENU =====
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"Player"
                                                        action:NULL
                                                 keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Player"];
    NSMenuItem *aboutItem = (NSMenuItem *)
        [appMenu addItemWithTitle:@"About Player"
                           action:@selector(orderFrontStandardAboutPanel:)
                    keyEquivalent:@""];
    [aboutItem setTarget:NSApp];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences..."
                       action:NULL
                keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Player"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Hide Others"
                       action:@selector(hideOtherApplications:)
                keyEquivalent:@"h"];
    [[appMenu itemAtIndex:[appMenu numberOfItems] - 1]
        setKeyEquivalentModifierMask:NSAlternateKeyMask | NSCommandKeyMask];
    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Player"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    [appMenu release];
    [appMenuItem release];

    // ===== FILE MENU =====
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File"
                                                         action:NULL
                                                  keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *openItem = (NSMenuItem *)
        [fileMenu addItemWithTitle:@"Open File..."
                            action:@selector(openFile:)
                     keyEquivalent:@"o"];
    [openItem setTarget:self];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *closeItem = (NSMenuItem *)
        [fileMenu addItemWithTitle:@"Close Window"
                            action:@selector(performClose:)
                     keyEquivalent:@"w"];
    [closeItem setTarget:self];
    [fileMenuItem setSubmenu:fileMenu];
    [mainMenu addItem:fileMenuItem];
    [fileMenu release];
    [fileMenuItem release];

    // ===== EDIT MENU =====
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                         action:NULL
                                                  keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo"
                        action:@selector(undo:)
                 keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo"
                        action:@selector(redo:)
                 keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut"
                        action:@selector(cut:)
                 keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"
                        action:@selector(copy:)
                 keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"
                        action:@selector(paste:)
                 keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All"
                        action:@selector(selectAll:)
                 keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];
    [editMenu release];
    [editMenuItem release];

    // ===== PLAYBACK MENU =====
    NSMenuItem *playbackMenuItem = [[NSMenuItem alloc] initWithTitle:@"Playback"
                                                             action:NULL
                                                      keyEquivalent:@""];
    NSMenu *playbackMenu = [[NSMenu alloc] initWithTitle:@"Playback"];
    NSMenuItem *playPauseItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Play / Pause"
                                action:@selector(playPause:)
                         keyEquivalent:@" "];
    [playPauseItem setTarget:self];
    NSMenuItem *stopItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Stop"
                                action:@selector(stop:)
                         keyEquivalent:@"."];
    [stopItem setTarget:self];
    [stopItem setKeyEquivalentModifierMask:NSCommandKeyMask];
    [playbackMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *prevItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Previous Track"
                                action:@selector(previousTrack:)
                         keyEquivalent:@","];
    [prevItem setTarget:self];
    [prevItem setKeyEquivalentModifierMask:NSCommandKeyMask];
    NSMenuItem *nextItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Next Track"
                                action:@selector(nextTrack:)
                         keyEquivalent:@"."];
    [nextItem setTarget:self];
    [nextItem setKeyEquivalentModifierMask:NSCommandKeyMask];
    [playbackMenu addItem:[NSMenuItem separatorItem]];
    repeatMenuItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Repeat"
                                action:@selector(toggleRepeat:)
                         keyEquivalent:@"r"];
    [repeatMenuItem setTarget:self];
    [repeatMenuItem setState:repeatEnabled ? NSOnState : NSOffState];
    shuffleMenuItem = (NSMenuItem *)
        [playbackMenu addItemWithTitle:@"Shuffle"
                                action:@selector(toggleShuffle:)
                         keyEquivalent:@"s"];
    [shuffleMenuItem setTarget:self];
    [shuffleMenuItem setState:shuffleEnabled ? NSOnState : NSOffState];
    [playbackMenuItem setSubmenu:playbackMenu];
    [mainMenu addItem:playbackMenuItem];
    [playbackMenu release];
    [playbackMenuItem release];

    // ===== VIEW MENU =====
    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View"
                                                         action:NULL
                                                  keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *fsItem = (NSMenuItem *)
        [viewMenu addItemWithTitle:@"Enter Fullscreen"
                            action:@selector(toggleFullscreen:)
                     keyEquivalent:@"f"];
    [fsItem setTarget:self];
    [[viewMenu addItemWithTitle:@"Zoom"
                         action:@selector(performZoom:)
                  keyEquivalent:@""] setTarget:mainWindow];
    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];
    [viewMenu release];
    [viewMenuItem release];

    // ===== WINDOW MENU =====
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window"
                                                           action:NULL
                                                    keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenuItem setSubmenu:windowMenu];
    [mainMenu addItem:windowMenuItem];
    [windowMenu release];
    [windowMenuItem release];

    // ===== HELP MENU =====
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] initWithTitle:@"Help"
                                                         action:NULL
                                                  keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenu addItemWithTitle:@"Player Help"
                        action:nil
                 keyEquivalent:@"?"];
    [helpMenuItem setSubmenu:helpMenu];
    [mainMenu addItem:helpMenuItem];
    [helpMenu release];
    [helpMenuItem release];

    [NSApp setMainMenu:mainMenu];
    [mainMenu release];
}

#pragma mark - UI Creation

- (void)createUI
{
    [self createMenu];

    CGFloat windowWidth = DEFAULT_WINDOW_WIDTH;
    CGFloat windowHeight = DEFAULT_WINDOW_HEIGHT;
    coverAreaHeight = floorf(windowHeight * COVER_AREA_FRACTION);

    NSRect windowFrame = NSMakeRect(100, 100, windowWidth, windowHeight);
    mainWindow = [[NSWindow alloc] initWithContentRect:windowFrame
                                             styleMask:NSTitledWindowMask |
                                                       NSClosableWindowMask |
                                                       NSMiniaturizableWindowMask |
                                                       NSResizableWindowMask
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [mainWindow setTitle:@"Player"];
    [mainWindow setDelegate:self];
    [mainWindow setMinSize:NSMakeSize(PLAYER_CONTENT_MIN_WIDTH, PLAYER_CONTENT_MIN_HEIGHT)];
    [mainWindow setAcceptsMouseMovedEvents:YES];
    [mainWindow setContentMinSize:NSMakeSize(PLAYER_CONTENT_MIN_WIDTH, PLAYER_CONTENT_MIN_HEIGHT)];

    // Replace the default content view with a drop-target view for drag-and-drop
    DropTargetView *dropView = [[DropTargetView alloc]
        initWithFrame:[[mainWindow contentView] frame]
           controller:self];
    [mainWindow setContentView:dropView];
    [dropView release];
    NSView *contentView = [mainWindow contentView];

    // ===== ITEM FLOW (COVER ART CAROUSEL) =====
    // Fills top portion, stretches horizontally and vertically
    NSRect coverFrame = NSMakeRect(0, 0, windowWidth, coverAreaHeight);
    flowView = [[ItemFlowView alloc] initWithFrame:coverFrame];
    [flowView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [flowView setDataSource:self];
    [flowView setDelegate:self];
    [contentView addSubview:flowView];

    // Video view (identical frame, hidden until video content)
    videoView = [[NSView alloc] initWithFrame:coverFrame];
    [videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [videoView setHidden:YES];
    [contentView addSubview:videoView];

    // Progress spinner (centered on the cover area)
    NSRect progressFrame = NSMakeRect(0, 0, 24, 24);
    progressIndicator = [[NSProgressIndicator alloc] initWithFrame:progressFrame];
    [progressIndicator setStyle:NSProgressIndicatorSpinningStyle];
    [progressIndicator setHidden:YES];
    [progressIndicator setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin |
                                           NSViewMinYMargin | NSViewMaxYMargin];
    [contentView addSubview:progressIndicator];

    // ===== TIME SLIDER ROW =====
    // Placed just below the cover area; stretches horizontally.
    // We'll position everything in layoutSubviews so we just add as subviews here.
    currentTimeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [currentTimeLabel setStringValue:@"0:00"];
    [currentTimeLabel setEditable:NO];
    [currentTimeLabel setSelectable:NO];
    [currentTimeLabel setBezeled:NO];
    [currentTimeLabel setDrawsBackground:NO];
    [currentTimeLabel setAlignment:NSRightTextAlignment];
    [currentTimeLabel setFont:METRICS_FONT_SYSTEM_REGULAR_11];
    [contentView addSubview:currentTimeLabel];

    timeSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    [timeSlider setMinValue:0.0];
    [timeSlider setMaxValue:100.0];
    [timeSlider setDoubleValue:0.0];
    [timeSlider setContinuous:YES];
    [timeSlider setTarget:self];
    [timeSlider setAction:@selector(seekToTime:)];
    [contentView addSubview:timeSlider];

    totalTimeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [totalTimeLabel setStringValue:@"0:00"];
    [totalTimeLabel setEditable:NO];
    [totalTimeLabel setSelectable:NO];
    [totalTimeLabel setBezeled:NO];
    [totalTimeLabel setDrawsBackground:NO];
    [totalTimeLabel setFont:METRICS_FONT_SYSTEM_REGULAR_11];
    [contentView addSubview:totalTimeLabel];

    // ===== PLAYBACK CONTROLS ROW =====
    // Centered in the window, fixed size
    previousButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [previousButton setImage:[self iconPrevious]];
    [previousButton setImagePosition:NSImageOnly];
    [previousButton setButtonType:NSMomentaryLight];
    [previousButton setTarget:self];
    [previousButton setAction:@selector(previousTrack:)];
    [previousButton setEnabled:NO];
    [contentView addSubview:previousButton];

    playButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [playButton setImage:[self iconPlay]];
    [playButton setAlternateImage:[self iconPause]];
    [playButton setImagePosition:NSImageOnly];
    [playButton setButtonType:NSMomentaryLight];
    [playButton setTarget:self];
    [playButton setAction:@selector(playPause:)];
    [playButton setEnabled:NO];
    [contentView addSubview:playButton];

    stopButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [stopButton setImage:[self iconStop]];
    [stopButton setImagePosition:NSImageOnly];
    [stopButton setButtonType:NSMomentaryLight];
    [stopButton setTarget:self];
    [stopButton setAction:@selector(stop:)];
    [stopButton setEnabled:NO];
    [contentView addSubview:stopButton];

    nextButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [nextButton setImage:[self iconNext]];
    [nextButton setImagePosition:NSImageOnly];
    [nextButton setButtonType:NSMomentaryLight];
    [nextButton setTarget:self];
    [nextButton setAction:@selector(nextTrack:)];
    [nextButton setEnabled:NO];
    [contentView addSubview:nextButton];

    // ===== BOTTOM CONTROLS ROW =====
    openButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [openButton setTitle:@"Open..."];
    [openButton setButtonType:NSMomentaryLight];
    [openButton setTarget:self];
    [openButton setAction:@selector(openFile:)];
    [contentView addSubview:openButton];

    fullscreenButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [fullscreenButton setImage:[self iconFullscreen]];
    [fullscreenButton setImagePosition:NSImageOnly];
    [fullscreenButton setButtonType:NSMomentaryLight];
    [fullscreenButton setTarget:self];
    [fullscreenButton setAction:@selector(toggleFullscreen:)];
    [contentView addSubview:fullscreenButton];

    // ===== METADATA LABELS =====
    titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [titleLabel setStringValue:@"No file loaded"];
    [titleLabel setEditable:NO];
    [titleLabel setSelectable:NO];
    [titleLabel setBezeled:NO];
    [titleLabel setDrawsBackground:NO];
    [titleLabel setFont:METRICS_FONT_SYSTEM_BOLD_13];
    [contentView addSubview:titleLabel];

    artistLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [artistLabel setStringValue:@""];
    [artistLabel setEditable:NO];
    [artistLabel setSelectable:NO];
    [artistLabel setBezeled:NO];
    [artistLabel setDrawsBackground:NO];
    [artistLabel setFont:METRICS_FONT_SYSTEM_REGULAR_11];
    [contentView addSubview:artistLabel];

    albumLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [albumLabel setStringValue:@""];
    [albumLabel setEditable:NO];
    [albumLabel setSelectable:NO];
    [albumLabel setBezeled:NO];
    [albumLabel setDrawsBackground:NO];
    [albumLabel setFont:METRICS_FONT_SYSTEM_REGULAR_11];
    [contentView addSubview:albumLabel];

    detailsLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [detailsLabel setStringValue:@""];
    [detailsLabel setEditable:NO];
    [detailsLabel setSelectable:NO];
    [detailsLabel setBezeled:NO];
    [detailsLabel setDrawsBackground:NO];
    [detailsLabel setFont:METRICS_FONT_SYSTEM_REGULAR_11];
    [contentView addSubview:detailsLabel];

    // Initial layout
    [self layoutSubviews];
}

#pragma mark - Button Icons

- (NSImage *)createIconWithBlock:(void(^)(void))drawBlock size:(NSSize)size
{
    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img lockFocus];
    // Scale the icon content to 60 % centered within the image rect
    NSAffineTransform *t = [NSAffineTransform transform];
    [t translateXBy:size.width / 2.0 yBy:size.height / 2.0];
    [t scaleBy:0.6];
    [t translateXBy:-size.width / 2.0 yBy:-size.height / 2.0];
    [t concat];

    [[NSColor controlTextColor] set];
    drawBlock();
    [img unlockFocus];
    return [img autorelease];
}

- (NSImage *)iconPrevious
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineJoinStyle:NSRoundLineJoinStyle];
        // Vertical bar on left
        [p appendBezierPathWithRect:NSMakeRect(1, 1, 3, 14)];
        // Triangle pointing left
        [p moveToPoint:NSMakePoint(17, 1)];
        [p lineToPoint:NSMakePoint(6, 8)];
        [p lineToPoint:NSMakePoint(17, 15)];
        [p closePath];
        [p fill];
    } size:NSMakeSize(18, 16)];
}

- (NSImage *)iconPlay
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineJoinStyle:NSRoundLineJoinStyle];
        [p moveToPoint:NSMakePoint(3, 1)];
        [p lineToPoint:NSMakePoint(15, 8)];
        [p lineToPoint:NSMakePoint(3, 15)];
        [p closePath];
        [p fill];
    } size:NSMakeSize(18, 16)];
}

- (NSImage *)iconPause
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p appendBezierPathWithRect:NSMakeRect(2, 1, 5, 14)];
        [p appendBezierPathWithRect:NSMakeRect(11, 1, 5, 14)];
        [p fill];
    } size:NSMakeSize(18, 16)];
}

- (NSImage *)iconStop
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineJoinStyle:NSRoundLineJoinStyle];
        [p appendBezierPathWithRect:NSMakeRect(2, 2, 14, 12)];
        [p fill];
    } size:NSMakeSize(18, 16)];
}

- (NSImage *)iconNext
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineJoinStyle:NSRoundLineJoinStyle];
        // Triangle pointing right
        [p moveToPoint:NSMakePoint(1, 1)];
        [p lineToPoint:NSMakePoint(12, 8)];
        [p lineToPoint:NSMakePoint(1, 15)];
        [p closePath];
        // Vertical bar on right
        [p appendBezierPathWithRect:NSMakeRect(14, 1, 3, 14)];
        [p fill];
    } size:NSMakeSize(18, 16)];
}

- (NSImage *)iconFullscreen
{
    return [self createIconWithBlock:^{
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineWidth:1.6];
        [p setLineCapStyle:NSRoundLineCapStyle];
        [p setLineJoinStyle:NSRoundLineJoinStyle];
        // Top-left: arrow from interior pointing up-left
        [p moveToPoint:NSMakePoint(10, 10)];
        [p lineToPoint:NSMakePoint(2, 2)];
        [p moveToPoint:NSMakePoint(2, 8)];
        [p lineToPoint:NSMakePoint(2, 2)];
        [p lineToPoint:NSMakePoint(8, 2)];
        // Bottom-right: arrow from interior pointing down-right
        [p moveToPoint:NSMakePoint(6, 6)];
        [p lineToPoint:NSMakePoint(14, 14)];
        [p moveToPoint:NSMakePoint(14, 8)];
        [p lineToPoint:NSMakePoint(14, 14)];
        [p lineToPoint:NSMakePoint(8, 14)];
        [p stroke];
    } size:NSMakeSize(16, 16)];
}

#pragma mark - Layout Engine

- (void)layoutSubviews
{
    if (isFullscreen) {
        [self layoutFullscreenMode];
    } else {
        [self layoutNormalMode];
    }
}

- (void)layoutNormalMode
{
    NSView *content = [mainWindow contentView];
    NSRect bounds = [content bounds];
    CGFloat W = bounds.size.width;
    CGFloat H = bounds.size.height;

    // Restore controls hidden by fullscreen mode
    [currentTimeLabel setHidden:NO];
    [timeSlider setHidden:NO];
    [totalTimeLabel setHidden:NO];
    [previousButton setHidden:NO];
    [playButton setHidden:NO];
    [stopButton setHidden:NO];
    [nextButton setHidden:NO];
    [openButton setHidden:NO];
    [fullscreenButton setHidden:NO];
    [titleLabel setHidden:NO];
    [artistLabel setHidden:NO];
    [albumLabel setHidden:NO];
    [detailsLabel setHidden:NO];

    // ---- Cover / video area (COVER_AREA_FRACTION) ----
    coverAreaHeight = MAX(120.0, floorf(H * COVER_AREA_FRACTION));
    CGFloat coverBottom = H - coverAreaHeight; // top of content below cover
    NSRect coverFrame = NSMakeRect(0, coverBottom, W, coverAreaHeight);
    [flowView setFrame:coverFrame];
    [videoView setFrame:coverFrame];

    // Center spinner on cover area
    NSSize spinSize = [progressIndicator frame].size;
    [progressIndicator setFrameOrigin:NSMakePoint(
        NSMidX(coverFrame) - spinSize.width / 2.0,
        NSMidY(coverFrame) - spinSize.height / 2.0)];

    CGFloat margin = METRICS_CONTENT_SIDE_MARGIN;
    CGFloat y = coverBottom;  // descending cursor

    // ---- Metadata area (directly below cover) ----
    y -= METRICS_SPACE_12;
    CGFloat metaW = W - 2 * margin;
    CGFloat lineH = 15.0;
    CGFloat lineGap = 1.0;

    y -= lineH;
    [titleLabel setFrame:NSMakeRect(margin, y, metaW, lineH)];
    [titleLabel setAutoresizingMask:NSViewWidthSizable];

    y -= lineGap + lineH;
    [artistLabel setFrame:NSMakeRect(margin, y, metaW, lineH)];
    [artistLabel setAutoresizingMask:NSViewWidthSizable];

    y -= lineGap + lineH;
    [albumLabel setFrame:NSMakeRect(margin, y, metaW, lineH)];
    [albumLabel setAutoresizingMask:NSViewWidthSizable];

    y -= lineGap + lineH;
    [detailsLabel setFrame:NSMakeRect(margin, y, metaW, lineH)];
    [detailsLabel setAutoresizingMask:NSViewWidthSizable];

    // ---- Time slider row ----
    y -= METRICS_SPACE_8;
    CGFloat timeLabelW = 42.0;
    CGFloat sliderW = W - 2 * margin - 2 * timeLabelW - 8;

    [currentTimeLabel setFrame:NSMakeRect(margin, y, timeLabelW, 16)];
    [currentTimeLabel setAutoresizingMask:NSViewMaxXMargin];

    [timeSlider setFrame:NSMakeRect(margin + timeLabelW + 4, y, sliderW, SLIDER_BAR_HEIGHT)];
    [timeSlider setAutoresizingMask:NSViewWidthSizable];

    [totalTimeLabel setFrame:NSMakeRect(margin + timeLabelW + 4 + sliderW + 4, y, timeLabelW, 16)];
    [totalTimeLabel setAutoresizingMask:NSViewMinXMargin];
    y -= SLIDER_BAR_HEIGHT;

    // ---- Playback controls row (centered) ----
    y -= METRICS_SPACE_12;
    CGFloat btnW = 36.0;
    CGFloat btnH = CONTROL_BAR_HEIGHT;
    CGFloat gap = 6.0;
    CGFloat fourBtnW = 4 * btnW + 3 * gap;
    CGFloat ctrlStartX = floorf((W - fourBtnW) / 2.0);

    [previousButton setFrame:NSMakeRect(ctrlStartX, y, btnW, btnH)];
    [playButton setFrame:NSMakeRect(ctrlStartX + btnW + gap, y, btnW, btnH)];
    [stopButton setFrame:NSMakeRect(ctrlStartX + 2 * (btnW + gap), y, btnW, btnH)];
    [nextButton setFrame:NSMakeRect(ctrlStartX + 3 * (btnW + gap), y, btnW, btnH)];
    y -= btnH;

    // ---- Bottom row: Open, Fullscreen ----
    y -= METRICS_SPACE_12;
    CGFloat bottomBtnH = METRICS_BUTTON_HEIGHT;
    CGFloat openW = 68.0;
    CGFloat fsBtnW = 28.0;

    [openButton setFrame:NSMakeRect(margin, y, openW, bottomBtnH)];
    [openButton setAutoresizingMask:NSViewMaxXMargin];

    // Fullscreen button on the right
    CGFloat rightEdge = W - margin;
    [fullscreenButton setFrame:NSMakeRect(rightEdge - fsBtnW, y, fsBtnW, bottomBtnH)];
    [fullscreenButton setAutoresizingMask:NSViewMinXMargin];

    // Hide overlay if in normal mode
    if (overlayBar && ![overlayBar isHidden]) {
        [overlayBar setHidden:YES];
    }
}

- (void)layoutFullscreenMode
{
    NSView *content = [mainWindow contentView];
    NSRect bounds = [content bounds];
    CGFloat W = bounds.size.width;
    CGFloat H = bounds.size.height;

    // Cover art fills entire screen
    NSRect fullFrame = NSMakeRect(0, 0, W, H);
    [flowView setFrame:fullFrame];
    [flowView setNeedsDisplay:YES];
    [videoView setFrame:fullFrame];
    [videoView setNeedsDisplay:YES];

    // Center spinner
    NSSize spinSize = [progressIndicator frame].size;
    [progressIndicator setFrameOrigin:NSMakePoint(
        NSMidX(fullFrame) - spinSize.width / 2.0,
        NSMidY(fullFrame) - spinSize.height / 2.0)];

    // Hide all normal controls (they live in the overlay bar now)
    [currentTimeLabel setHidden:YES];
    [timeSlider setHidden:YES];
    [totalTimeLabel setHidden:YES];
    [previousButton setHidden:YES];
    [playButton setHidden:YES];
    [stopButton setHidden:YES];
    [nextButton setHidden:YES];
    [openButton setHidden:YES];
    [fullscreenButton setHidden:YES];
    [titleLabel setHidden:YES];
    [artistLabel setHidden:YES];
    [albumLabel setHidden:YES];
    [detailsLabel setHidden:YES];

    // Create overlay bar if needed
    if (!overlayBar) {
        overlayBar = [[NSView alloc] initWithFrame:NSZeroRect];
        [overlayBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [overlayBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [content addSubview:overlayBar];
    }
    [overlayBar setHidden:NO];

    // Layout overlay bar at bottom
    CGFloat barH = OVERLAY_BAR_HEIGHT;
    CGFloat barY = 0;
    CGFloat barW = W;
    [overlayBar setFrame:NSMakeRect(0, barY, barW, barH)];

    // Fullscreen button in overlay bar (right side)
    CGFloat fsBtnW = 28.0;
    CGFloat margin = 16.0;
    [fullscreenButton setHidden:NO];
    [fullscreenButton setFrame:NSMakeRect(barW - fsBtnW - margin,
                                           (barH - CONTROL_BAR_HEIGHT) / 2.0,
                                           fsBtnW, CONTROL_BAR_HEIGHT)];

    // Play/Pause centered
    CGFloat btnW = 36.0;
    CGFloat gap = 8.0;
    CGFloat centerX = floorf(W / 2.0);
    CGFloat btnStartX = centerX - (4 * btnW + 3 * gap) / 2.0;

    [previousButton setHidden:NO];
    [previousButton setFrame:NSMakeRect(btnStartX, (barH - CONTROL_BAR_HEIGHT) / 2.0,
                                         btnW, CONTROL_BAR_HEIGHT)];

    [playButton setHidden:NO];
    [playButton setFrame:NSMakeRect(btnStartX + btnW + gap,
                                     (barH - CONTROL_BAR_HEIGHT) / 2.0,
                                     btnW, CONTROL_BAR_HEIGHT)];

    [stopButton setHidden:NO];
    [stopButton setFrame:NSMakeRect(btnStartX + 2 * (btnW + gap),
                                    (barH - CONTROL_BAR_HEIGHT) / 2.0,
                                    btnW, CONTROL_BAR_HEIGHT)];

    [nextButton setHidden:NO];
    [nextButton setFrame:NSMakeRect(btnStartX + 3 * (btnW + gap),
                                    (barH - CONTROL_BAR_HEIGHT) / 2.0,
                                    btnW, CONTROL_BAR_HEIGHT)];

    // Time slider above the buttons in the bar
    CGFloat sliderBarMargin = 60.0;
    CGFloat timeLabelW = 40.0;
    CGFloat sliderW = barW - 2 * sliderBarMargin - 2 * timeLabelW - 2 * 4;
    [currentTimeLabel setHidden:NO];
    [currentTimeLabel setFrame:NSMakeRect(sliderBarMargin,
                                          barH - 14 - 4, timeLabelW, 14)];
    [timeSlider setHidden:NO];
    [timeSlider setFrame:NSMakeRect(sliderBarMargin + timeLabelW + 4,
                                    barH - 16 - 2, sliderW, 16)];
    [totalTimeLabel setHidden:NO];
    [totalTimeLabel setFrame:NSMakeRect(sliderBarMargin + timeLabelW + 4 + sliderW + 4,
                                        barH - 14 - 4, timeLabelW, 14)];

    // Mouse tracking for auto-hide of overlay
    [self showOverlay];
}

#pragma mark - Fullscreen

- (IBAction)toggleFullscreen:(id)sender
{
    if (isFullscreen) {
        [self exitFullscreen];
    } else {
        [self enterFullscreen];
    }
}

- (void)enterFullscreen
{
    if (isFullscreen) return;
    isFullscreen = YES;

    // In GNUstep we cannot dynamically change the window styleMask,
    // so we achieve fullscreen by raising the window level and
    // resizing to fill the screen.
    [mainWindow setLevel:NSScreenSaverWindowLevel];

    // Store normal frame and resize to fill screen
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    [mainWindow setFrame:screenFrame display:YES animate:NO];

    // Update menu item title and bind Escape key
    [[[[[NSApp mainMenu] itemWithTitle:@"View"] submenu] itemWithTitle:@"Enter Fullscreen"]
        setTitle:@"Exit Fullscreen"];
    [[[[[NSApp mainMenu] itemWithTitle:@"View"] submenu] itemWithTitle:@"Exit Fullscreen"]
        setKeyEquivalent:@"\e"];

    [self layoutSubviews];
    [self showOverlay];
    [self scheduleOverlayHide];
}

- (void)exitFullscreen
{
    if (!isFullscreen) return;
    isFullscreen = NO;

    // Restore window level
    [mainWindow setLevel:NSNormalWindowLevel];

    // Restore normal size
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    CGFloat w = DEFAULT_WINDOW_WIDTH;
    CGFloat h = DEFAULT_WINDOW_HEIGHT;
    NSRect frame = NSMakeRect(
        NSMidX(screenFrame) - w / 2.0,
        NSMidY(screenFrame) - h / 2.0,
        w, h);
    [mainWindow setFrame:frame display:YES animate:NO];

    // Restore menu title and clear Escape key
    [[[[[NSApp mainMenu] itemWithTitle:@"View"] submenu] itemWithTitle:@"Exit Fullscreen"]
        setTitle:@"Enter Fullscreen"];
    [[[[[NSApp mainMenu] itemWithTitle:@"View"] submenu] itemWithTitle:@"Enter Fullscreen"]
        setKeyEquivalent:@""];

    // Cancel overlay hide timer
    if (overlayHideTimer) {
        [overlayHideTimer invalidate];
        [overlayHideTimer release];
        overlayHideTimer = nil;
    }
    // Hide overlay bar
    if (overlayBar) {
        [overlayBar setHidden:YES];
    }

    [self layoutSubviews];
}

#pragma mark - Overlay Controls (Fullscreen)

- (void)showOverlay
{
    if (!isFullscreen) return;
    if (overlayBar) {
        [overlayBar setAlphaValue:1.0];
        [overlayBar setHidden:NO];
    }
}

- (void)hideOverlay
{
    if (!isFullscreen) return;
    if (overlayBar) {
        [overlayBar setAlphaValue:0.0];
        [overlayBar setHidden:YES];
    }
}

- (void)scheduleOverlayHide
{
    if (overlayHideTimer) {
        [overlayHideTimer invalidate];
        [overlayHideTimer release];
    }
    overlayHideTimer = [[NSTimer scheduledTimerWithTimeInterval:OVERLAY_HIDE_DELAY
                                                         target:self
                                                       selector:@selector(overlayAutoHideTimerFired:)
                                                       userInfo:nil
                                                        repeats:NO] retain];
}

- (void)overlayAutoHideTimerFired:(NSTimer *)timer
{
    [self hideOverlay];
    overlayHideTimer = nil;
}

- (void)mouseMoved:(NSEvent *)event
{
    if (!isFullscreen) return;

    NSPoint loc = [event locationInWindow];

    // Show overlay when mouse is in the bottom 80px
    if (loc.y < 80.0) {
        [self showOverlay];
        [self scheduleOverlayHide];
    }
}

#pragma mark - Window Delegate

- (void)windowDidResize:(NSNotification *)notification
{
    [self layoutSubviews];
}

- (BOOL)windowShouldClose:(id)sender
{
    [NSApp terminate:self];
    return YES;
}

#pragma mark - Application Delegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];

    [NSApp setDelegate:self];

    [self createUI];

    if ([arguments count] > 1) {
        [self handleCommandLineArguments];
        return;
    }

    if (mainWindow) {
        [mainWindow makeKeyAndOrderFront:self];
    }
    [self updateStatus:@"Ready — open a media file to start playing"];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (playbackTimer) {
        [playbackTimer invalidate];
        [playbackTimer release];
        playbackTimer = nil;
    }
    if (overlayHideTimer) {
        [overlayHideTimer invalidate];
        [overlayHideTimer release];
        overlayHideTimer = nil;
    }
    if (avPlayer) {
        [avPlayer pause];
    }
    if (audioPlayer) {
        [audioPlayer stop];
    }
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename
{
    [self loadFile:filename];
    return YES;
}

#pragma mark - Playback Actions

- (IBAction)openFile:(id)sender
{
    [self showOpenPanel];
}

- (IBAction)playPause:(id)sender
{
    [self togglePlayPause];
}

- (IBAction)stop:(id)sender
{
    [self stopPlayback];
}

- (IBAction)previousTrack:(id)sender
{
    if ([playlist count] == 0) return;

    int newIndex;
    if (shuffleEnabled) {
        // Pick a random track (different from current)
        if ([playlist count] == 1) {
            newIndex = 0;
        } else {
            do {
                newIndex = random() % (int)[playlist count];
            } while (newIndex == currentIndex);
        }
    } else {
        newIndex = currentIndex - 1;
        if (newIndex < 0)
            newIndex = (repeatEnabled) ? (int)[playlist count] - 1 : 0;
    }
    [self playFromPlaylistAtIndex:newIndex];
}

- (IBAction)nextTrack:(id)sender
{
    if ([playlist count] == 0) return;

    int newIndex;
    if (shuffleEnabled) {
        // Pick a random track (different from current)
        if ([playlist count] == 1) {
            newIndex = 0;
        } else {
            do {
                newIndex = random() % (int)[playlist count];
            } while (newIndex == currentIndex);
        }
    } else {
        newIndex = currentIndex + 1;
        if (newIndex >= (int)[playlist count])
            newIndex = (repeatEnabled) ? 0 : (int)[playlist count] - 1;
    }
    [self playFromPlaylistAtIndex:newIndex];
}

- (IBAction)seekToTime:(id)sender
{
    if (!avPlayer && !audioPlayer) return;

    double percentage = [timeSlider doubleValue] / 100.0;

    if (avPlayer) {
        AVAsset *asset = [playerItem asset];
        CMTime duration = [asset duration];
        double durSec = CMTimeGetSeconds(duration);
        if (durSec > 0) {
            CMTime seekTime = CMTimeMakeWithSeconds(percentage * durSec, 1);
            [avPlayer seekToTime:seekTime];
        }
    } else if (audioPlayer) {
        // Seek using NSSound's setCurrentTime: on the underlying sound object
        NSSound *sound = [audioPlayer valueForKey:@"sound"];
        if (sound && [sound respondsToSelector:@selector(setCurrentTime:)]) {
            // Get duration to calculate target time from percentage
            NSTimeInterval dur = [sound duration];
            if (dur > 0) {
                NSTimeInterval targetTime = percentage * dur;
                [sound setCurrentTime:targetTime];
            }
        }
    }
}

- (IBAction)toggleRepeat:(id)sender
{
    repeatEnabled = !repeatEnabled;
    [repeatMenuItem setState:repeatEnabled ? NSOnState : NSOffState];
    [[NSUserDefaults standardUserDefaults] setBool:repeatEnabled forKey:@"PlayerRepeatEnabled"];
    [self updateStatus:repeatEnabled ? @"Repeat on" : @"Repeat off"];
}

- (IBAction)toggleShuffle:(id)sender
{
    shuffleEnabled = !shuffleEnabled;
    [shuffleMenuItem setState:shuffleEnabled ? NSOnState : NSOffState];
    [[NSUserDefaults standardUserDefaults] setBool:shuffleEnabled forKey:@"PlayerShuffleEnabled"];
    [self updateStatus:shuffleEnabled ? @"Shuffle on" : @"Shuffle off"];
}

#pragma mark - Playback Control

- (void)loadFile:(NSString *)filePath
{
    if (!filePath || ![filePath length]) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:filePath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Not Found"];
        [alert setInformativeText:[NSString stringWithFormat:
            @"The file '%@' could not be found.", [filePath lastPathComponent]]];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
        return;
    }

    [self stopPlayback];

    [currentFilePath release];
    currentFilePath = [filePath retain];

    isVideo = [self isVideoFile:filePath];

    [self updateStatus:[NSString stringWithFormat:@"Loading %@...", [filePath lastPathComponent]]];
    [progressIndicator setHidden:NO];
    [progressIndicator startAnimation:self];

    if (isVideo) {
        [videoView setHidden:NO];
        [flowView setHidden:YES];

        NSURL *url = [NSURL fileURLWithPath:filePath];
        urlAsset = [[AVURLAsset alloc] initWithURL:url options:nil];
        playerItem = [[AVPlayerItem alloc] initWithAsset:urlAsset];
        avPlayer = [[AVPlayer alloc] initWithPlayerItem:playerItem];
        [avPlayer setActionAtItemEnd:AVPlayerActionAtItemEndPause];

        // In GNUstep, video rendering isn't available yet,
        // so fall back to cover art + audio playback
        [videoView setHidden:YES];
        [flowView setHidden:NO];
    } else {
        [videoView setHidden:YES];
        [flowView setHidden:NO];

        NSURL *url = [NSURL fileURLWithPath:filePath];

        // Create AVURLAsset for metadata and cover art extraction
        [urlAsset release];
        urlAsset = [[AVURLAsset alloc] initWithURL:url options:nil];

        NSError *error = nil;
        audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];

        if (!audioPlayer) {
            [progressIndicator setHidden:YES];
            [progressIndicator stopAnimation:self];
            NSString *errMsg = error ? [error localizedDescription] : @"Unknown error";
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Failed to Load File"];
            [alert setInformativeText:[NSString stringWithFormat:
                @"Unable to play '%@': %@", [filePath lastPathComponent], errMsg]];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            [alert release];
            [self updateStatus:@"Failed to load file"];
            return;
        }

        [audioPlayer setVolume:0.8];
    }

    [self updateMetadata];
    [self addToPlaylist:filePath];

    // Extract and cache cover art for the ItemFlow view
    NSDebugLLog(@"gwcomp", @"[Player] requesting cover art for %@", filePath);
    NSImage *cover = [self extractCoverArtForFile:filePath];
    if (cover) {
        NSDebugLLog(@"gwcomp", @"[Player] cover art obtained, caching for ItemFlow");
        [coverImages setObject:cover forKey:filePath];
    } else {
        NSDebugLLog(@"gwcomp", @"[Player] no cover art available, ItemFlow will show placeholder");
    }

    // Keep the flow view's internal array in sync with the playlist size
    [flowView reloadData];
    [flowView updateTexturesForIndices:[NSIndexSet indexSetWithIndex:currentIndex]];

    [playButton setEnabled:YES];
    [stopButton setEnabled:YES];
    [previousButton setEnabled:([playlist count] > 1)];
    [nextButton setEnabled:([playlist count] > 1)];

    [self updateDurationDisplay];

    [progressIndicator setHidden:YES];
    [progressIndicator stopAnimation:self];
    [self updateStatus:[NSString stringWithFormat:@"Loaded: %@", [filePath lastPathComponent]]];
}

- (void)togglePlayPause
{
    if (playbackState == PlayerPlaybackStatePlaying) {
        [self pause];
    } else if (playbackState == PlayerPlaybackStatePaused) {
        [self play];
    } else if (playbackState == PlayerPlaybackStateStopped && currentFilePath) {
        [self loadFile:currentFilePath];
        [self play];
    }
}

- (void)play
{
    if (avPlayer) {
        NSLog(@"Player: play via AVPlayer (%@)", currentFilePath);
        [avPlayer play];
        playbackState = PlayerPlaybackStatePlaying;
        [playButton setImage:[self iconPause]];
        if (!playbackTimer) {
            playbackTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                              target:self
                                                            selector:@selector(playbackTimerFired:)
                                                            userInfo:nil
                                                             repeats:YES] retain];
        }
    } else if (audioPlayer) {
        NSLog(@"Player: play via AVAudioPlayer (%@)", currentFilePath);
        BOOL result = [audioPlayer play];
        NSLog(@"Player: AVAudioPlayer play returned %d", result);
        if (result) {
            NSLog(@"Player: AVAudioPlayer isPlaying=%d", [audioPlayer isPlaying]);
            playbackState = PlayerPlaybackStatePlaying;
            [playButton setImage:[self iconPause]];
            if (!playbackTimer) {
                playbackTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                                  target:self
                                                                selector:@selector(playbackTimerFired:)
                                                                userInfo:nil
                                                                 repeats:YES] retain];
            }
        } else {
            NSLog(@"Player: AVAudioPlayer play returned NO, audio may be silent");
        }
    }
}

- (void)pause
{
    if (avPlayer) {
        [avPlayer pause];
    } else if (audioPlayer) {
        [audioPlayer pause];
    }
    playbackState = PlayerPlaybackStatePaused;
    [playButton setImage:[self iconPlay]];
}

- (void)stopPlayback
{
    if (avPlayer) {
        [avPlayer pause];
        [avPlayer seekToTime:kCMTimeZero];
    }
    if (audioPlayer) {
        [audioPlayer stop];
    }
    playbackState = PlayerPlaybackStateStopped;
    [playButton setImage:[self iconPlay]];

    if (!isFullscreen) {
        [timeSlider setDoubleValue:0.0];
        [currentTimeLabel setStringValue:@"0:00"];
    }

    if (playbackTimer) {
        [playbackTimer invalidate];
        [playbackTimer release];
        playbackTimer = nil;
    }
}

- (void)updatePlaybackUI
{
    if (playbackState == PlayerPlaybackStatePlaying) {
        [playButton setImage:[self iconPause]];
    } else {
        [playButton setImage:[self iconPlay]];
    }
}

#pragma mark - Metadata

- (void)updateMetadata
{
    if (!currentFilePath) return;

    NSString *filename = [currentFilePath lastPathComponent];
    NSString *title = filename;
    NSString *artist = @"";
    NSString *album = @"";
    NSString *composer = @"";
    NSString *genre = @"";
    NSString *track = @"";

    if (urlAsset) {
        NSArray *metadata = [urlAsset commonMetadata];
        for (AVMetadataItem *item in metadata) {
            id key = [item key];
            if (![key isKindOfClass:[NSString class]]) continue;

            if ([key isEqual:AVMetadataCommonKeyTitle]) {
                if ([item stringValue]) title = [item stringValue];
            } else if ([key isEqual:AVMetadataCommonKeyArtist]) {
                if ([item stringValue]) artist = [item stringValue];
            } else if ([key isEqual:AVMetadataCommonKeyAlbumName]) {
                if ([item stringValue]) album = [item stringValue];
            } else if ([key isEqual:AVMetadataCommonKeyComposer]) {
                if ([item stringValue]) composer = [item stringValue];
            } else if ([key isEqual:AVMetadataCommonKeyGenre]) {
                if ([item stringValue]) genre = [item stringValue];
            } else if ([key isEqual:AVMetadataCommonKeyTrackNumber]) {
                if ([item stringValue]) track = [item stringValue];
            }
        }
    }

    if ([title isEqualToString:filename]) {
        title = [filename stringByDeletingPathExtension];
    }

    [titleLabel setStringValue:title];
    [artistLabel setStringValue:artist];
    [albumLabel setStringValue:album];

    // Build a compact details line from genre | composer | track
    NSMutableString *details = [NSMutableString string];
    if ([genre length] > 0) {
        [details appendString:genre];
    }
    if ([composer length] > 0) {
        if ([details length] > 0) [details appendString:@"  ·  "];
        [details appendString:composer];
    }
    if ([track length] > 0) {
        if ([details length] > 0) [details appendString:@"  ·  "];
        [details appendFormat:@"Track %@", track];
    }
    [detailsLabel setStringValue:details];

    [mainWindow setTitle:[NSString stringWithFormat:@"Player — %@", title]];
}

#pragma mark - ItemFlowView Data Source

- (NSUInteger)numberOfItemsInItemFlowView:(ItemFlowView *)view
{
    return [playlist count];
}

- (NSImage *)itemFlowView:(ItemFlowView *)view imageAtIndex:(NSUInteger)index
{
    if (index >= [playlist count]) return nil;
    NSString *path = [playlist objectAtIndex:index];
    return [coverImages objectForKey:path];
}

#pragma mark - ItemFlowView Delegate

- (void)itemFlowView:(ItemFlowView *)view didSelectItemAtIndex:(NSUInteger)index
{
    // Suppress re-selection of the already-playing track
    if ((int)index == currentIndex && playbackState != PlayerPlaybackStateStopped) {
        return;
    }
    if (index < [playlist count]) {
        [self playFromPlaylistAtIndex:(int)index];
    }
}

#pragma mark - Cover Art Extraction

- (NSImage *)extractCoverArtForFile:(NSString *)filePath
{
    if (!filePath) {
        NSDebugLLog(@"gwcomp", @"[Player] extractCoverArtForFile: nil path, returning nil");
        return nil;
    }

    NSDebugLLog(@"gwcomp", @"[Player] extractCoverArtForFile: %@", filePath);

    // ---- 1. Sidecar PNG — same basename, same directory ---- //

    NSString *baseName = [[filePath lastPathComponent] stringByDeletingPathExtension];
    NSString *directory = [filePath stringByDeletingLastPathComponent];
    NSString *pngPath = [directory stringByAppendingPathComponent:
        [baseName stringByAppendingPathExtension:@"png"]];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:pngPath]) {
        NSDebugLLog(@"gwcomp", @"[Player]   sidecar PNG found at %@, loading", pngPath);
        NSImage *sidecar = [[NSImage alloc] initWithContentsOfFile:pngPath];
        if (sidecar) {
            NSDebugLLog(@"gwcomp", @"[Player]   sidecar PNG loaded successfully (size=%@)",
                        NSStringFromSize([sidecar size]));
            [sidecar autorelease];
            return sidecar;  // prefer sidecar over embedded
        }
        NSDebugLLog(@"gwcomp", @"[Player]   sidecar PNG exists but failed to decode, falling through");
    } else {
        NSDebugLLog(@"gwcomp", @"[Player]   no sidecar PNG at %@", pngPath);
    }

    // ---- 2. Embedded artwork via AVFoundation ---- //

    NSURL *url = [NSURL fileURLWithPath:filePath];
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
    NSImage *cover = nil;

    NSArray *metadata = [asset commonMetadata];
    NSDebugLLog(@"gwcomp", @"[Player]   AVAsset commonMetadata count: %tu", [metadata count]);

    for (AVMetadataItem *item in metadata) {
        id key = [item key];
        NSString *keyDesc = [key isKindOfClass:[NSString class]] ? (NSString *)key : [key description];
        NSDebugLLog(@"gwcomp", @"[Player]   metadata item key=%@ valueClass=%@",
                    keyDesc, NSStringFromClass([[item value] class]));

        if ([key isKindOfClass:[NSString class]] &&
            [(NSString *)key isEqualToString:AVMetadataCommonKeyArtwork]) {
            id value = [item value];
            if ([value isKindOfClass:[NSData class]]) {
                NSData *data = (NSData *)value;
                NSDebugLLog(@"gwcomp", @"[Player]   artwork NSData length=%tu bytes", [data length]);

                cover = [[NSImage alloc] initWithData:data];
                if (cover) {
                    NSDebugLLog(@"gwcomp", @"[Player]   embedded artwork decoded OK (size=%@)",
                                NSStringFromSize([cover size]));
                    [cover autorelease];
                } else {
                    NSDebugLLog(@"gwcomp", @"[Player]   embedded artwork data did not produce an NSImage");
                }
            } else {
                NSDebugLLog(@"gwcomp", @"[Player]   artwork key found but value is %@, not NSData",
                            NSStringFromClass([value class]));
            }
            break;  // only one artwork item expected
        }
    }

    if (!cover) {
        NSDebugLLog(@"gwcomp", @"[Player]   no artwork found via AVFoundation");
    }

    [asset release];
    return cover;
}

#pragma mark - Batch Cover Loading

- (void)loadCoverArtForAllPlaylistItems
{
    NSInteger count = [playlist count];
    if (count == 0) return;

    NSDebugLLog(@"gwcomp", @"[Player] loadCoverArtForAllPlaylistItems: %ld items", (long)count);

    // Extract any covers we don't have yet
    for (NSInteger i = 0; i < count; i++) {
        NSString *path = [playlist objectAtIndex:i];
        if ([coverImages objectForKey:path] == nil) {
            NSImage *cover = [self extractCoverArtForFile:path];
            if (cover) {
                [coverImages setObject:cover forKey:path];
            }
        }
    }

    // Grow the view's item array without destroying existing textures
    [flowView setItemCount:count];

    // Load textures for every index that has a cached cover
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    for (NSInteger i = 0; i < count; i++) {
        if ([coverImages objectForKey:[playlist objectAtIndex:i]]) {
            [indices addIndex:i];
        }
    }
    if ([indices count] > 0) {
        [flowView updateTexturesForIndices:indices];
    }
}

- (NSString *)formatTime:(CMTime)time
{
    double totalSeconds = CMTimeGetSeconds(time);
    if (totalSeconds <= 0 || isnan(totalSeconds) || isinf(totalSeconds))
        return @"0:00";
    return [self formatTimeInterval:totalSeconds];
}

- (NSString *)formatTimeInterval:(NSTimeInterval)interval
{
    if (interval < 0 || isnan(interval) || isinf(interval))
        return @"0:00";
    int total = (int)round(interval);
    int hours = total / 3600;
    int mins = (total % 3600) / 60;
    int secs = total % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%d:%02d:%02d", hours, mins, secs];
    }
    return [NSString stringWithFormat:@"%d:%02d", mins, secs];
}

#pragma mark - Playlist

- (void)addToPlaylist:(NSString *)filePath
{
    if (!filePath) return;
    for (NSString *existing in playlist) {
        if ([existing isEqualToString:filePath]) {
            currentIndex = (int)[playlist indexOfObject:filePath];
            return;
        }
    }
    [playlist addObject:filePath];
    currentIndex = (int)[playlist count] - 1;
}

- (void)playFromPlaylistAtIndex:(int)index
{
    if (index < 0 || index >= (int)[playlist count]) return;
    currentIndex = index;
    NSString *fp = [playlist objectAtIndex:index];
    if (fp) {
        [self loadFile:fp];
        [self play];
        // Animate the flow view to show the currently playing track
        [flowView setSelectedIndex:index];
    }
}

#pragma mark - Timer

- (void)playbackTimerFired:(NSTimer *)timer
{
    if (playbackState == PlayerPlaybackStateStopped) return;

    if (avPlayer) {
        CMTime current = [avPlayer currentTime];
        CMTime duration = [[playerItem asset] duration];
        double durSec = CMTimeGetSeconds(duration);
        double curSec = CMTimeGetSeconds(current);

        if (durSec > 0 && curSec >= 0) {
            double pct = (curSec / durSec) * 100.0;
            if (!isFullscreen) {
                [timeSlider setDoubleValue:pct];
            }
            [currentTimeLabel setStringValue:[self formatTimeInterval:curSec]];
            [totalTimeLabel setStringValue:[self formatTimeInterval:durSec]];
        }

        if (durSec > 0 && curSec >= durSec) {
            [self stopPlayback];
        }
    } else if (audioPlayer) {
        // AVAudioPlayer wraps NSSound internally; read position from it.
        NSSound *sound = [audioPlayer valueForKey:@"sound"];
        if (sound) {
            NSTimeInterval curSec = [sound currentTime];
            NSTimeInterval durSec = [sound duration];
            if (durSec > 0 && curSec >= 0) {
                double pct = (curSec / durSec) * 100.0;
                if (!isFullscreen) {
                    [timeSlider setDoubleValue:pct];
                }
                [currentTimeLabel setStringValue:[self formatTimeInterval:curSec]];
                [totalTimeLabel setStringValue:[self formatTimeInterval:durSec]];
            }
        }

        if (![audioPlayer isPlaying] && playbackState == PlayerPlaybackStatePlaying) {
            [self stopPlayback];
            if ([playlist count] > 1) {
                if (repeatEnabled || shuffleEnabled) {
                    [self nextTrack:self];
                } else {
                    int nextIdx = currentIndex + 1;
                    if (nextIdx < (int)[playlist count]) {
                        [self playFromPlaylistAtIndex:nextIdx];
                    }
                }
            } else if (repeatEnabled && [playlist count] == 1) {
                [self playFromPlaylistAtIndex:0];
            }
        }
    }
}

- (void)updateDurationDisplay
{
    if (urlAsset) {
        CMTime duration = [urlAsset duration];
        if (CMTimeGetSeconds(duration) > 0) {
            [totalTimeLabel setStringValue:[self formatTime:duration]];
        }
    } else if (audioPlayer) {
        NSSound *sound = [audioPlayer valueForKey:@"sound"];
        NSTimeInterval dur = [sound respondsToSelector:@selector(duration)] ? [sound duration] : 0;
        if (dur > 0) {
            [totalTimeLabel setStringValue:[self formatTimeInterval:dur]];
        } else {
            [totalTimeLabel setStringValue:@"--:--"];
        }
    } else if (currentFilePath) {
        [totalTimeLabel setStringValue:@"--:--"];
    }
}

#pragma mark - Utility

- (void)updateStatus:(NSString *)status
{
    NSDebugLLog(@"gwcomp", @"Player: %@", status);
}

- (void)showOpenPanel
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setAllowedFileTypes:@[
        @"mp3", @"wav", @"aiff", @"aif", @"m4a", @"flac", @"ogg",
        @"mp4", @"m4v", @"mov", @"avi", @"mkv", @"webm"
    ]];

    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSArray *urls = [panel URLs];
        if ([urls count] == 0) return;

        // Collect all paths (files and directories)
        NSMutableArray *paths = [NSMutableArray arrayWithCapacity:[urls count]];
        for (NSURL *url in urls) {
            [paths addObject:[url path]];
        }

        // Reuse the drag-and-drop handler which recursively scans folders
        // and filters for supported media files
        if ([paths count] == 1) {
            BOOL isDir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:[paths firstObject] isDirectory:&isDir];
            if (!isDir) {
                // Single file — original fast path
                [self loadFile:[paths firstObject]];
                [self play];
                return;
            }
        }
        [self handleDroppedFiles:paths];
    }
}

- (BOOL)isVideoFile:(NSString *)path
{
    NSString *ext = [[path pathExtension] lowercaseString];
    return [@[@"mp4", @"m4v", @"mov", @"avi", @"mkv", @"webm", @"flv", @"wmv"]
        containsObject:ext];
}

- (BOOL)isAudioFile:(NSString *)path
{
    NSString *ext = [[path pathExtension] lowercaseString];
    return [@[@"mp3", @"wav", @"aiff", @"aif", @"m4a", @"flac", @"ogg", @"wma"]
        containsObject:ext];
}

#pragma mark - Drag & Drop (Playlist Management)

- (void)handleDroppedFiles:(NSArray *)filePaths
{
    if (!filePaths || [filePaths count] == 0) return;

    NSMutableArray *validFiles = [NSMutableArray array];

    for (NSString *path in filePaths) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
            if (isDir) {
                // Recursively scan the folder for supported media files
                NSArray *folderFiles = [self scanFolderForMediaFiles:path];
                [validFiles addObjectsFromArray:folderFiles];
            } else if ([self isAudioFile:path] || [self isVideoFile:path]) {
                [validFiles addObject:path];
            }
        }
    }

    if ([validFiles count] == 0) return;

    // Sort for consistent ordering
    [validFiles sortUsingSelector:@selector(compare:)];

    // Remember whether we were playing before adding
    BOOL wasPlaying = (playbackState != PlayerPlaybackStateStopped);

    // Add all valid files to the playlist (addToPlaylist: handles dedup)
    for (NSString *file in validFiles) {
        [self addToPlaylist:file];
    }

    // Load cover art for every playlist item immediately
    [self loadCoverArtForAllPlaylistItems];

    // If nothing was playing, start with the first (sorted) file
    if (!wasPlaying && [playlist count] > 0) {
        [self playFromPlaylistAtIndex:0];
    }

    [self updateStatus:[NSString stringWithFormat:@"Added %lu file(s) to playlist",
        (unsigned long)[validFiles count]]];
}

- (NSArray *)scanFolderForMediaFiles:(NSString *)folderPath
{
    NSMutableArray *result = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:folderPath];

    for (NSString *subpath in enumerator) {
        NSString *fullPath = [folderPath stringByAppendingPathComponent:subpath];
        BOOL isDir = NO;
        [fm fileExistsAtPath:fullPath isDirectory:&isDir];
        if (!isDir && ([self isAudioFile:fullPath] || [self isVideoFile:fullPath])) {
            [result addObject:fullPath];
        }
    }

    return result;
}

- (void)restoreWindowTitle
{
    if (currentFilePath) {
        NSString *title = [currentFilePath lastPathComponent];
        // Check if we have a nicer title from metadata
        NSString *metaTitle = [titleLabel stringValue];
        if (metaTitle && [metaTitle length] > 0 &&
            ![metaTitle isEqualToString:@"No file loaded"]) {
            title = metaTitle;
        } else {
            title = [title stringByDeletingPathExtension];
        }
        [mainWindow setTitle:[NSString stringWithFormat:@"Player — %@", title]];
    } else {
        [mainWindow setTitle:@"Player"];
    }
}

#pragma mark - Command Line

- (void)handleCommandLineArguments
{
    [mainWindow orderOut:nil];

    NSArray *args = [[NSProcessInfo processInfo] arguments];
    BOOL showHelp = NO;
    NSMutableArray *filesToOpen = [NSMutableArray array];

    for (int i = 1; i < (int)[args count]; i++) {
        NSString *arg = [args objectAtIndex:i];
        if ([arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) {
            showHelp = YES;
            break;
        } else if (![arg hasPrefix:@"-"]) {
            [filesToOpen addObject:arg];
        }
    }

    if (showHelp) {
        [self printUsageAndExit];
        return;
    }

    // UI was already created in applicationDidFinishLaunching
    if ([filesToOpen count] > 0) {
        [mainWindow makeKeyAndOrderFront:self];

        // Add all files to playlist
        for (NSString *filePath in filesToOpen) {
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:filePath]) {
                [self addToPlaylist:filePath];
            }
        }

        // Load cover art for every playlist item immediately
        [self loadCoverArtForAllPlaylistItems];

        // Start playing the first file
        if ([playlist count] > 0) {
            [self playFromPlaylistAtIndex:0];
        }
    } else {
        [mainWindow makeKeyAndOrderFront:self];
    }
}

- (void)printUsageAndExit
{
    printf("Player - GNUstep Media Player\n\n");
    printf("Usage: Player [options] [media-file]\n\n");
    printf("Options:\n");
    printf("  -h, --help    Show this help message\n\n");
    printf("If a media file is specified, it will be loaded and played.\n");
    printf("Supported formats: mp3, wav, aiff, m4a, flac, ogg,\n");
    printf("                   mp4, m4v, mov, avi, mkv, webm\n");
    exit(0);
}

- (void)exitApp
{
    [NSApp terminate:self];
}

@end

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef PlayerController_h
#define PlayerController_h

#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import "ItemFlowView.h"

typedef NS_ENUM(NSInteger, PlayerPlaybackState) {
    PlayerPlaybackStateStopped,
    PlayerPlaybackStatePlaying,
    PlayerPlaybackStatePaused
};

@interface PlayerController : NSObject <NSWindowDelegate, ItemFlowViewDataSource, ItemFlowViewDelegate>
{
    // Main window
    NSWindow *mainWindow;
    BOOL isFullscreen;

    // Video display
    NSView *videoView;
    ItemFlowView *flowView;
    BOOL isVideo;

    // Playback controls
    NSButton *playButton;
    NSButton *stopButton;
    NSButton *previousButton;
    NSButton *nextButton;
    NSButton *openButton;
    NSSlider *timeSlider;
    NSTextField *currentTimeLabel;
    NSTextField *totalTimeLabel;
    NSButton *fullscreenButton;

    // Overlay control bar (fullscreen)
    NSView *overlayBar;
    NSTimer *overlayHideTimer;

    // Metadata display
    NSTextField *titleLabel;
    NSTextField *artistLabel;
    NSTextField *albumLabel;
    NSTextField *detailsLabel;
    NSProgressIndicator *progressIndicator;

    // Layout geometry cache (recomputed on resize)
    CGFloat coverAreaHeight;
    CGFloat controlRowHeight;
    CGFloat metadataAreaHeight;

    // AVFoundation objects
    AVPlayer *avPlayer;
    AVPlayerItem *playerItem;
    AVURLAsset *urlAsset;
    AVAudioPlayer *audioPlayer;
    NSString *currentFilePath;
    PlayerPlaybackState playbackState;

    // Timer for updating UI during playback
    NSTimer *playbackTimer;

    // Playlist support
    NSMutableArray *playlist;
    int currentIndex;
    BOOL repeatEnabled;
    BOOL shuffleEnabled;

    // Menu items (to update checkmarks)
    NSMenuItem *repeatMenuItem;
    NSMenuItem *shuffleMenuItem;

    // Cover art cache
    NSMutableDictionary *coverImages;
}

// Properties
@property (retain) NSWindow *mainWindow;
@property (retain) NSView *videoView;
@property (retain) ItemFlowView *flowView;
@property (retain) NSButton *playButton;
@property (retain) NSButton *stopButton;
@property (retain) NSButton *previousButton;
@property (retain) NSButton *nextButton;
@property (retain) NSButton *openButton;
@property (retain) NSButton *fullscreenButton;
@property (retain) NSSlider *timeSlider;
@property (retain) NSTextField *currentTimeLabel;
@property (retain) NSTextField *totalTimeLabel;
@property (retain) NSTextField *titleLabel;
@property (retain) NSTextField *artistLabel;
@property (retain) NSTextField *albumLabel;
@property (retain) NSTextField *detailsLabel;
@property (retain) NSProgressIndicator *progressIndicator;

// UI Creation
- (void)createUI;
- (void)createMenu;

// Layout
- (void)layoutSubviews;
- (void)layoutNormalMode;
- (void)layoutFullscreenMode;

// Window delegate
- (void)windowDidResize:(NSNotification *)notification;

// Application delegate methods
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (BOOL)application:(NSApplication *)application openFile:(NSString *)filename;

// Playback actions
- (IBAction)openFile:(id)sender;
- (IBAction)playPause:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)previousTrack:(id)sender;
- (IBAction)nextTrack:(id)sender;
- (IBAction)seekToTime:(id)sender;

// View actions
- (IBAction)toggleFullscreen:(id)sender;
- (IBAction)toggleRepeat:(id)sender;
- (IBAction)toggleShuffle:(id)sender;

// Playback control
- (void)loadFile:(NSString *)filePath;
- (void)play;
- (void)pause;
- (void)stopPlayback;
- (void)updatePlaybackUI;
- (void)togglePlayPause;

// Metadata
- (void)updateMetadata;
- (NSString *)formatTime:(CMTime)time;
- (NSString *)formatTimeInterval:(NSTimeInterval)interval;

// Cover Art
- (NSImage *)extractCoverArtForFile:(NSString *)filePath;

// Playlist
- (void)addToPlaylist:(NSString *)filePath;
- (void)playFromPlaylistAtIndex:(int)index;

// Timer
- (void)playbackTimerFired:(NSTimer *)timer;

// Overlay controls (fullscreen)
- (void)showOverlay;
- (void)hideOverlay;
- (void)overlayAutoHideTimerFired:(NSTimer *)timer;
- (void)mouseMoved:(NSEvent *)event;

// Utility
- (void)updateStatus:(NSString *)status;
- (void)showOpenPanel;
- (BOOL)isVideoFile:(NSString *)path;
- (BOOL)isAudioFile:(NSString *)path;

// Command line handling
- (void)handleCommandLineArguments;
- (void)printUsageAndExit;
- (void)exitApp;

@end

#endif /* PlayerController_h */

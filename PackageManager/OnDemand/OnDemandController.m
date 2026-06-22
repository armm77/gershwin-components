/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OnDemandController implementation.
 *
 * Flow:
 *   setupFromPlist -> reads install.plist from bundle
 *   showWindow -> creates and displays progress UI
 *   performInstallAndLaunch ->
 *     1. Check if postinstall_command exists
 *     2. If yes -> launch it directly
 *     3. If no  -> install packages via GWPackageManager, then launch
 */

#import "OnDemandController.h"
#import "../GWSystemCommandExecutor.h"

#pragma mark - Constants (derived from AppearanceMetrics.h)

// HIG metrics (see AppearanceMetrics.h)
static const CGFloat kWinWidth = 400.0;
static const CGFloat kSideMargin = 24.0;
static const CGFloat kBottomMargin = 20.0;
static const CGFloat kTopMargin = 15.0;
static const CGFloat kBtnHeight = 20.0;
static const CGFloat kBtnWide = 100.0;
static const CGFloat kBtnHSpace = 10.0;          // METRICS_BUTTON_HORIZ_INTERSPACE
static const CGFloat kBarHeight = 20.0;
static const CGFloat kLineHeight = 18.0;
static const CGFloat kIconSide = 64.0;            // METRICS_ICON_SIDE
static const CGFloat kIconLeft = 24.0;            // METRICS_ICON_LEFT
static const CGFloat kTextLeft = 104.0;           // METRICS_TEXT_LEFT = 24 + 64 + 16
static const CGFloat kSpace8 = 8.0;               // METRICS_SPACE_8
static const CGFloat kSpace16 = 16.0;              // METRICS_SPACE_16
static const CGFloat kDetailsTextH = 140.0;        // expanded details height

#pragma mark - OnDemandController

@implementation OnDemandController
{
  BOOL _isTerminating;
}

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _pm = [[GWPackageManager alloc] initWithBackend:nil];
      _isTerminating = NO;
    }
  return self;
}

/// Resolve the actual .app bundle path from argv[0] so symlinked
/// placeholders load their own Resources/install.plist rather than
/// the symlink target's bundle (OnDemand.app).
- (NSString *)_actualBundlePath
{
  NSString *arg0 = [[[NSProcessInfo processInfo] arguments] firstObject];
  if (arg0)
    {
      NSString *absPath = [arg0 stringByStandardizingPath];
      NSString *dir = absPath;
      while (dir && ![dir isEqualToString:@"/"])
        {
          if ([[dir pathExtension] isEqualToString:@"app"])
            return dir;
          dir = [dir stringByDeletingLastPathComponent];
        }
    }
  return [[NSBundle mainBundle] bundlePath];
}

#pragma mark - Plist Setup

- (BOOL)setupFromPlist
{
  NSString *appPath = [self _actualBundlePath];
  _plistPath = [appPath stringByAppendingPathComponent:@"Resources/install.plist"];
  NSLog(@"OnDemand -> setupFromPlist: appPath=%@, plist=%@", appPath, _plistPath);

  if (!_plistPath)
    {
      NSLog(@"OnDemand [FAIL] setupFromPlist: install.plist not found at %@", _plistPath);
      return NO;
    }

  _spec = [[GWPackageInstallSpec alloc] initWithPlistAtPath:_plistPath
                                                   specType:GWPackageInstallSpecTypeInstall
                                                      error:nil];
  if (!_spec)
    {
      NSLog(@"OnDemand [FAIL] setupFromPlist: failed to parse %@", _plistPath);
      return NO;
    }

  // App name from the .app bundle directory (e.g., "Krita.app" -> "Krita")
  _appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
  if ([_appName length] == 0)
    _appName = @"Application";
  NSLog(@"OnDemand [OK] setupFromPlist: app=%@ packages=%@ command=%@",
        _appName, [_spec packages], [_spec postCommand]);

  return YES;
}

#pragma mark - Window Setup

- (void)showWindow
{
  CGFloat cx = kSideMargin;
  CGFloat contentW = kWinWidth - 2 * kSideMargin;
  CGFloat textW = kWinWidth - kSideMargin - kTextLeft;       // 272

  // Description text — defined once, used for both measurement and display
  NSString *desc = [NSString stringWithFormat:
    @"%@ is not yet available on this system and needs to be downloaded from the Internet.\nWould you like to download it now?", _appName];

  // Calculate actual text height: measure via attributed string
  NSFont *descFont = [NSFont systemFontOfSize:11.0];
  NSAttributedString *as = [[NSAttributedString alloc] initWithString:desc
                                                           attributes:@{ NSFontAttributeName: descFont }];
  NSRect textBounds = [as boundingRectWithSize:NSMakeSize(textW, CGFLOAT_MAX)
                                       options:NSStringDrawingUsesLineFragmentOrigin];
  // Add padding for NSTextField text container insets
  CGFloat totalDescH = ceil(textBounds.size.height) + 4.0;

  // Window height (bottom-up):
  // bottom(20) + btn(20) + gap(16) + desc(mm) + gap(8) + icon(64) + top(15)
  CGFloat winH = kBottomMargin + kBtnHeight + kSpace16
               + totalDescH + kSpace8 + kIconSide + kTopMargin;

  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWinWidth, winH)
                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

  CGFloat y = kBottomMargin;

  // ── Bottom row: Cancel + Download (right-aligned, Cancel left of default) ──
  CGFloat btnRight = kWinWidth - kSideMargin;
  CGFloat downloadX = btnRight - kBtnWide;
  CGFloat cancelX  = downloadX - kBtnHSpace - kBtnWide;

  _cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(cancelX, y, kBtnWide, kBtnHeight)];
  [_cancelButton setTitle:@"Cancel"];
  [_cancelButton setTarget:self];
  [_cancelButton setAction:@selector(cancelClicked:)];
  [_cancelButton setKeyEquivalent:@"\e"];
  [[_window contentView] addSubview:_cancelButton];

  _installButton = [[NSButton alloc] initWithFrame:NSMakeRect(downloadX, y, kBtnWide, kBtnHeight)];
  [_installButton setTitle:@"Download"];
  [_installButton setTarget:self];
  [_installButton setAction:@selector(installClicked:)];
  [_installButton setKeyEquivalent:@"\r"];
  [[_window contentView] addSubview:_installButton];

  y += kBtnHeight + kSpace16;

  // ── Description ──
  _descriptionField = [[NSTextField alloc] initWithFrame:NSMakeRect(kTextLeft, y, contentW - kTextLeft + cx, totalDescH)];
  [_descriptionField setStringValue:desc];
  [_descriptionField setBezeled:NO];
  [_descriptionField setDrawsBackground:NO];
  [_descriptionField setEditable:NO];
  [_descriptionField setSelectable:NO];
  [_descriptionField setAlignment:NSTextAlignmentLeft];
  [_descriptionField setFont:descFont];
  [[_descriptionField cell] setLineBreakMode:NSLineBreakByWordWrapping];
  [[_window contentView] addSubview:_descriptionField];

  y += totalDescH + kSpace8;

  // ── App icon + name ──
  _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(kIconLeft, y, kIconSide, kIconSide)];
  [_iconView setImageFrameStyle:NSImageFrameNone];
  NSString *appPath = [self _actualBundlePath];
  NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
  if (icon) [_iconView setImage:icon];
  [[_window contentView] addSubview:_iconView];

  CGFloat nameX = kTextLeft;
  CGFloat nameW = btnRight - kTextLeft;
  NSRect nr = NSMakeRect(nameX, y + (kIconSide - kLineHeight) / 2, nameW, kLineHeight);
  NSTextField *nf = [[NSTextField alloc] initWithFrame:nr];
  [nf setStringValue:_appName ?: @""];
  [nf setBezeled:NO];
  [nf setDrawsBackground:NO];
  [nf setEditable:NO];
  [nf setSelectable:NO];
  [nf setFont:[NSFont systemFontOfSize:13.0]];
  [[_window contentView] addSubview:nf];

  // ── Progress UI (created lazily) ──
  _progressBar = nil;
  _statusField = nil;

  [_window setTitle:_appName];
  [_window center];

  // Defer display to next run loop iteration to avoid window system crashes
  dispatch_async(dispatch_get_main_queue(), ^{
    [_window orderFront:nil];
  });
}

#pragma mark - Progress Handler

- (void)installDidProgress:(float)progress message:(NSString *)message
{
  NSLog(@"OnDemand -> installDidProgress: %.0f%% — %@", progress * 100, message);
  dispatch_async(dispatch_get_main_queue(), ^{
    [_statusField setStringValue:message ?: @""];

    // Switch to indeterminate during long apt-get phase (progress stays at 50%)
    if (progress > 0.0f && progress < 1.0f && ![_progressBar isIndeterminate])
      {
        [_progressBar setIndeterminate:YES];
        [_progressBar startAnimation:nil];
      }
    else if (progress >= 1.0f && [_progressBar isIndeterminate])
      {
        [_progressBar stopAnimation:nil];
        [_progressBar setIndeterminate:NO];
        [_progressBar setDoubleValue:1.0];
      }
    else if (![_progressBar isIndeterminate])
      {
        [_progressBar setDoubleValue:(double)progress];
      }

    [_progressBar displayIfNeeded];
  });
}

#pragma mark - Actions

- (void)cancelClicked:(id)sender
{
  NSLog(@"OnDemand: User cancelled");
  if (_isTerminating) return;
  _isTerminating = YES;
  [_window close];
}

- (void)installClicked:(id)sender
{
  NSLog(@"OnDemand -> installClicked: user confirmed download");

  // Switch from confirmation to progress UI
  [_descriptionField setHidden:YES];
  [_installButton setHidden:YES];

  // Create progress UI lazily
  CGFloat cx = kSideMargin;
  CGFloat contentW = kWinWidth - 2 * kSideMargin;
  CGFloat progY  = kBottomMargin + kBtnHeight + kSpace16;  // 56
  CGFloat statY  = progY + kBarHeight + kSpace8;           // 84
  CGFloat btnRight = kWinWidth - kSideMargin;

  _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(kTextLeft, progY, contentW - kTextLeft + cx, kBarHeight)];
  [_progressBar setStyle:NSProgressIndicatorBarStyle];
  [_progressBar setIndeterminate:NO];
  [_progressBar setMinValue:0.0];
  [_progressBar setMaxValue:1.0];
  [_progressBar setDoubleValue:0.0];
  [[_window contentView] addSubview:_progressBar];

  _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(kTextLeft, statY, contentW - kTextLeft + cx, kLineHeight)];
  [_statusField setStringValue:@"Preparing…"];
  [_statusField setBezeled:NO];
  [_statusField setDrawsBackground:NO];
  [_statusField setEditable:NO];
  [_statusField setSelectable:NO];
  [_statusField setAlignment:NSTextAlignmentLeft];
  [[_window contentView] addSubview:_statusField];

  // ── Details disclosure toggle (left side, same row as Cancel) ──
  _detailsVisible = NO;
  _detailsScrollView = nil;
  _detailsTextView = nil;

  _detailsToggle = [[NSButton alloc] initWithFrame:NSMakeRect(kSideMargin, kBottomMargin, 130.0, kBtnHeight)];
  [_detailsToggle setTitle:@"  ▶  Details"];
  [_detailsToggle setTarget:self];
  [_detailsToggle setAction:@selector(detailsToggled:)];
  [_detailsToggle setBordered:NO];
  [[_detailsToggle cell] setFont:[NSFont systemFontOfSize:11.0]];
  [[_detailsToggle cell] setHighlightsBy:NSContentsCellMask];
  [[_window contentView] addSubview:_detailsToggle];

  // Cancel button in lower-right (matching Download button position from confirmation state)
  [_cancelButton setFrameOrigin:NSMakePoint(
    btnRight - kBtnWide, kBottomMargin)];

  [_window setTitle:[NSString stringWithFormat:@"Downloading %@", _appName]];

  // Start download on background thread
  [self performInstallAndLaunch];
}

#pragma mark - Command Checking

- (BOOL)_commandExists:(NSString *)command
{
  if (!command || [command length] == 0)
    {
      NSLog(@"OnDemand -> _commandExists: (empty) -> NO");
      return NO;
    }

  // If it's an absolute path, check directly
  if ([command hasPrefix:@"/"])
    {
      BOOL exists = [[NSFileManager defaultManager] isExecutableFileAtPath:command];
      NSLog(@"OnDemand -> _commandExists: absolute path %@ -> %s", command, exists ? "YES" : "NO");
      return exists;
    }

  // Search PATH via `which`
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/usr/bin/which"];
  [task setArguments:@[command]];

  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:[NSPipe pipe]];

  @try
    {
      [task launch];
      [task waitUntilExit];
      BOOL exists = ([task terminationStatus] == 0);
      NSLog(@"OnDemand -> _commandExists: which %@ -> %s", command, exists ? "YES" : "NO");
      return exists;
    }
  @catch (NSException *e)
    {
      NSLog(@"OnDemand -> _commandExists: which %@ -> exception %@", command, e);
      return NO;
    }
}

/// Resolve a command to an absolute path. Returns nil on failure.
- (NSString *)_resolveCommandPath:(NSString *)command
{
  if ([command hasPrefix:@"/"])
    return command;

  id<GWSystemCommandExecutor> exec = [GWSystemCommandExecutor sharedExecutor];
  NSString *output = nil;
  int rc = [exec execute:@"/usr/bin/which" arguments:@[command] output:&output];
  if (rc == 0 && output)
    {
      NSString *path = [output stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([path length] > 0)
        return path;
    }
  return nil;
}

/// Exit codes used by OnDemand:
///   0 = success
///   1 = setup/plist error
///   2 = command not found / can't resolve path
///   3 = installation failed
///   4 = NSTask execution exception
///   otherwise = exit code from the launched command (passed through)

/// Execute a command via NSTask, inheriting stdio so stdout/stderr
/// and the exit code pass through to the caller.
/// Returns: command's exit code (>= 0), -2 if not found, -4 on exception.
- (int)_executeCommand:(NSString *)command arguments:(NSArray<NSString *> *)args
{
  if (!command || [command length] == 0)
    {
      NSLog(@"OnDemand -> _executeCommand: (empty) -> exit -1");
      return -1;
    }

  NSString *path = [self _resolveCommandPath:command];
  if (!path)
    {
      NSLog(@"OnDemand [FAIL] _executeCommand: '%@' not found in PATH", command);
      return -2;
    }

  NSLog(@"OnDemand -> _executeCommand: %@ %@", path,
        [args count] > 0 ? [args componentsJoinedByString:@" "] : @"");

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  if ([args count] > 0)
    [task setArguments:args];
  // Pass through the parent's environment so the launched app sees
  // the same PATH, DISPLAY, etc. as OnDemand
  [task setEnvironment:[[NSProcessInfo processInfo] environment]];
  // Do NOT set standardOutput/standardError — leaving them unset
  // makes the child inherit the parent's stdio so output and exit
  // codes pass through to the caller.

  @try
    {
      [task launch];
      [task waitUntilExit];
      int status = [task terminationStatus];
      NSLog(@"OnDemand <- _executeCommand: %@ -> exit %d", path, status);
      return status;
    }
  @catch (NSException *e)
    {
      NSLog(@"OnDemand [FAIL] _executeCommand: exception running %@: %@", path, e);
      return -4;
    }
}

/// Map _executeCommand return value to an exit code and call exit().
- (void)_exitWithCommandStatus:(int)status command:(NSString *)command
{
  int code;
  if (status >= 0)
    code = status;                                   // pass through command's exit code
  else if (status == -2)
    code = 2;                                        // command not found
  else if (status == -4)
    code = 4;                                        // NSTask exception
  else
    code = 1;                                        // unknown error

  NSLog(@"OnDemand -> _exitWithCommandStatus: %d -> exit(%d)", status, code);
  exit(code);
}

#pragma mark - Direct Launch (no GUI)

- (BOOL)commandIsAvailable
{
  NSString *command = [_spec postCommand];
  return command ? [self _commandExists:command] : NO;
}

- (BOOL)launchAndExit
{
  NSString *command = [_spec postCommand];
  NSArray *args = [_spec postCommandArguments];
  NSLog(@"OnDemand -> launchAndExit: %@ %@", command,
        [args count] > 0 ? [args componentsJoinedByString:@" "] : @"");
  int status = [self _executeCommand:command arguments:args];
  [self _exitWithCommandStatus:status command:command];
  return YES; // unreachable
}

#pragma mark - Main Workflow (install + launch)

/// Show an error and schedule clean termination (helper for the install path)
- (void)_showInstallError:(NSString *)message
{
  NSLog(@"OnDemand [FAIL] Download FAILED: %@", message);
  [self _showError:message];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (!_isTerminating)
      {
        _isTerminating = YES;
        [NSApp terminate:nil];
      }
  });
}

/// Post-install launch step — called on the main thread after a successful install.
- (void)_launchAfterInstall
{
  [_progressBar setDoubleValue:1.0];
  [_window setTitle:[NSString stringWithFormat:@"Downloading %@", _appName]];
  NSString *command = [_spec postCommand];
  NSArray *commandArgs = [_spec postCommandArguments];

  if (command)
    {
      NSLog(@"OnDemand -> [Step 2/2] Executing command: %@", command);
      [_statusField setStringValue:@"Launching..."];

      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int status = [self _executeCommand:command arguments:commandArgs];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (status != 0)
            {
              NSLog(@"OnDemand [FAIL] [Step 2/2] Execution FAILED: %@ (status %d)", command, status);
              [self _showError:[NSString stringWithFormat:
                                @"%@ was downloaded but could not be launched.", _appName]];
              [self _exitWithCommandStatus:status command:command];
              return;
            }
          NSLog(@"OnDemand [OK] [Step 2/2] Execution succeeded (exit %d), exiting", status);
          [self _exitWithCommandStatus:status command:command];
        });
      });
    }
  else
    {
      NSLog(@"OnDemand -> performInstallAndLaunch: no postinstall command, done");
      [_statusField setStringValue:@"Download complete"];
      exit(0);
    }
}

- (void)performInstallAndLaunch
{
  NSString *command = [_spec postCommand];
  NSArray *packages = [_spec packages];
  NSArray *localFiles = [_spec localFilePaths];

  NSLog(@"OnDemand -> performInstallAndLaunch: BEGIN (command=%@, packages=%@, local=%@)",
        command, packages, localFiles);
  [_statusField setStringValue:@"Downloading…"];

  // Run the blocking install on a background thread so the UI stays responsive
  // and the progress bar updates in real time
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error = nil;
    BOOL success = [_pm installPackages:packages
                         localFilePaths:localFiles
                              progress:self
                                 error:&error];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (!success)
        {
          [self _populateDetailsFromBackend];
          NSString *captured = [_pm capturedErrorOutput];

          // ── Auto-recover from interrupted dpkg state ──
          if (!_dpkgRetried && captured &&
              [captured rangeOfString:@"dpkg --configure -a"].location != NSNotFound)
            {
              _dpkgRetried = YES;
              NSLog(@"OnDemand: dpkg was interrupted, running --configure -a and retrying...");
              [_statusField setStringValue:@"Recovering from interrupted package configuration…"];

              dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // Fix the interrupted dpkg state
                [self _executeCommand:@"/usr/bin/sudo"
                           arguments:@[@"dpkg", @"--configure", @"-a"]];

                // Retry the install once
                NSError *retryError = nil;
                BOOL retrySuccess = [_pm installPackages:packages
                                          localFilePaths:localFiles
                                               progress:self
                                                  error:&retryError];

                dispatch_async(dispatch_get_main_queue(), ^{
                  if (retrySuccess)
                    {
                      NSLog(@"OnDemand: dpkg recovery succeeded, continuing...");
                      [self _populateDetailsFromBackend];
                      [self _launchAfterInstall];
                    }
                  else
                    {
                      [self _populateDetailsFromBackend];
                      NSString *retryCaptured = [_pm capturedErrorOutput];
                      if ([retryCaptured hasPrefix:@"E: "])
                        retryCaptured = [retryCaptured substringFromIndex:3];
                      if ([retryCaptured length] == 0)
                        retryCaptured = [GWPackageManager friendlyErrorMessageForError:retryError
                                                                                appName:_appName];
                      [self _showInstallError:retryCaptured];
                    }
                });
              });
              return;
            }

          // ── Normal error ──
          if ([captured hasPrefix:@"E: "])
            captured = [captured substringFromIndex:3];
          NSString *msg = captured;
          if ([msg length] == 0)
            msg = [GWPackageManager friendlyErrorMessageForError:error
                                                          appName:_appName];
          [self _showInstallError:msg];
          return;
        }

      NSLog(@"OnDemand [OK] [Step 1/2] Download succeeded");
      [self _populateDetailsFromBackend];
      [self _launchAfterInstall];
    });
  });
}

#pragma mark - Captured Output (Details)

/// Populate the details text view from the backend's capturedErrorOutput
/// if it hasn't already been populated via live installDidOutputLine: calls.
- (void)_populateDetailsFromBackend
{
  if (!_detailsTextView || !_pm) return;

  // Only append if the text view is still empty; live callbacks may have
  // already populated it during command execution.
  if ([[_detailsTextView string] length] > 0) return;

  NSString *output = [_pm capturedErrorOutput];
  if ([output length] == 0) return;

  NSAttributedString *as = [[NSAttributedString alloc]
                             initWithString:output
                                 attributes:@{ NSFontAttributeName:
                                   [NSFont userFixedPitchFontOfSize:10.0] }];
  [[_detailsTextView textStorage] appendAttributedString:as];

  NSRange endRange = NSMakeRange([output length], 0);
  [_detailsTextView scrollRangeToVisible:endRange];
}

#pragma mark - Error Display

- (void)_showError:(NSString *)message
{
  NSLog(@"OnDemand: Error — %@", message);

  // Close the progress window before showing the error
  [_window orderOut:nil];

  // Show error in a standalone alert (avoids reusing same window views)
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:_appName ?: @"Application"];
  [alert setInformativeText:message];
  [alert addButtonWithTitle:@"Cancel"];
  [alert setAlertStyle:0]; // critical

  void (^showBlock)(void) = ^{
    [alert runModal];
    if (!_isTerminating)
      {
        _isTerminating = YES;
        [NSApp terminate:nil];
      }
  };

  if ([NSThread isMainThread])
    showBlock();
  else
    dispatch_sync(dispatch_get_main_queue(), showBlock);
}

- (void)quitClicked:(id)sender
{
  if (_isTerminating) return;
  _isTerminating = YES;
  [NSApp terminate:nil];
}

#pragma mark - Details Disclosure

- (void)detailsToggled:(id)sender
{
  _detailsVisible = !_detailsVisible;
  NSString *arrow = _detailsVisible ? @"  ▼" : @"  ▶";
  [_detailsToggle setTitle:[NSString stringWithFormat:@"%@  Details", arrow]];

  if (_detailsVisible && !_detailsTextView)
    {
      CGFloat contentW = kWinWidth - 2 * kSideMargin;

      _detailsTextView = [[NSTextView alloc]
                           initWithFrame:NSMakeRect(0, 0, contentW, kDetailsTextH)];
      [_detailsTextView setEditable:NO];
      [_detailsTextView setSelectable:YES];
      [_detailsTextView setFont:[NSFont userFixedPitchFontOfSize:10.0]];
      [_detailsTextView setTextColor:[NSColor colorWithCalibratedWhite:0.22 alpha:1.0]];
      [_detailsTextView setBackgroundColor:[NSColor colorWithCalibratedWhite:0.95 alpha:1.0]];
      [_detailsTextView setAutoresizingMask:NSViewWidthSizable];

      _detailsScrollView = [[NSScrollView alloc]
                             initWithFrame:NSMakeRect(kSideMargin, kSpace8,
                                                      contentW, kDetailsTextH)];
      [_detailsScrollView setDocumentView:_detailsTextView];
      [_detailsScrollView setHasVerticalScroller:YES];
      [_detailsScrollView setAutoresizingMask:NSViewWidthSizable];
      [_detailsScrollView setBorderType:NSBezelBorder];
      [_detailsScrollView setHidden:YES];
      [[_window contentView] addSubview:_detailsScrollView
                             positioned:NSWindowBelow relativeTo:nil];
      [self _populateDetailsFromBackend];
    }

  // Defer the resize to the next run loop pass using the NSRunLoop timer
  // mechanism (performSelector:afterDelay:), which integrates cleanly with
  // the AppKit event loop in GNUstep.
  [self performSelector:@selector(_resizeForDetails) withObject:nil afterDelay:0];
}

- (void)_resizeForDetails
{
  CGFloat contentW = kWinWidth - 2 * kSideMargin;
  CGFloat growBy = kDetailsTextH + kSpace8 + kBottomMargin;

  if (_detailsVisible)
    {
      // Grow the window downward — top stays fixed
      NSRect frame = [_window frame];
      frame.origin.y -= growBy;
      frame.size.height += growBy;
      [_window setFrame:frame display:YES];

      // Shift existing controls up so their screen position stays put
      for (NSView *v in [[_window contentView] subviews])
        {
          if (v == _detailsScrollView) continue;
          NSRect f = [v frame];
          f.origin.y += growBy;
          [v setFrame:f];
        }

      // Show the text view at the very bottom
      [_detailsScrollView setFrame:NSMakeRect(kSideMargin, kSpace8,
                                               contentW, kDetailsTextH)];
      [_detailsScrollView setHidden:NO];
      [[_window contentView] setNeedsDisplay:YES];

      NSRange end = NSMakeRange([[_detailsTextView string] length], 0);
      [_detailsTextView scrollRangeToVisible:end];
    }
  else
    {
      // Shrink the window back
      NSRect frame = [_window frame];
      frame.origin.y += growBy;
      frame.size.height -= growBy;
      [_window setFrame:frame display:YES];

      // Shift controls back down
      for (NSView *v in [[_window contentView] subviews])
        {
          if (v == _detailsScrollView) continue;
          NSRect f = [v frame];
          f.origin.y -= growBy;
          [v setFrame:f];
        }

      [_detailsScrollView setHidden:YES];
      [[_window contentView] setNeedsDisplay:YES];
    }
}

#pragma mark - Live Output from Backend

- (void)installDidOutputLine:(NSString *)line
{
  if (!line) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!_detailsTextView) return;

    NSAttributedString *as = [[NSAttributedString alloc]
                               initWithString:[line stringByAppendingString:@"\n"]
                                   attributes:@{ NSFontAttributeName:
                                     [NSFont userFixedPitchFontOfSize:10.0] }];
    [[_detailsTextView textStorage] appendAttributedString:as];

    // Auto-scroll if the details section is visible
    if (_detailsVisible)
      {
        NSRange endRange = NSMakeRange([[_detailsTextView string] length], 0);
        [_detailsTextView scrollRangeToVisible:endRange];
      }
  });
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSLog(@"OnDemand -> applicationDidFinishLaunching: showing download dialog");
  [self showWindow];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return YES;
}

@end

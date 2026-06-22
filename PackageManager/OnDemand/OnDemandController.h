/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OnDemandController — Controller for the OnDemand installer app.
 * Manages the progress window and orchestrates install/launch flow.
 */

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import "../GWPackageManager.h"
#import "../GWPackageInstallSpec.h"

@interface OnDemandController : NSObject <NSApplicationDelegate, GWInstallProgressHandler>
{
  NSWindow *_window;
  NSProgressIndicator *_progressBar;
  NSTextField *_statusField;
  NSButton *_cancelButton;
  NSImageView *_iconView;
  NSButton *_installButton;
  NSTextField *_descriptionField;

  GWPackageManager *_pm;
  GWPackageInstallSpec *_spec;
  NSString *_plistPath;
  NSString *_appName;
}

// Read the install plist from the app bundle
- (BOOL)setupFromPlist;

// Check if the target command is already available without showing a window
- (BOOL)commandIsAvailable;

// Launch the command and exit the app (no GUI shown)
- (BOOL)launchAndExit;

// Show the progress window
- (void)showWindow;

// Install packages then launch (call after showWindow)
- (void)performInstallAndLaunch;

@end

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * OnDemand — Placeholder on-demand installer application.
 *
 * Reads its embedded install.plist, checks if the target command
 * exists, installs packages if needed, then launches the command.
 */

#import <AppKit/NSApplication.h>
#import <Foundation/NSAutoreleasePool.h>
#import "OnDemandController.h"

// Keep controller alive for the run loop (NSApplication does not retain its delegate)
static OnDemandController *gController = nil;

int main(int argc, const char *argv[])
{
  [NSApplication sharedApplication];
  gController = [[OnDemandController alloc] init];
  [[NSApplication sharedApplication] setDelegate:gController];

  if (![gController setupFromPlist])
    {
      NSLog(@"OnDemand [FAIL] main: failed to read install plist, exiting");
      return 1;
    }

  // If command is already available, launch silently and exit (no GUI)
  if ([gController commandIsAvailable])
    {
      NSLog(@"OnDemand -> main: command already installed, launching silently");
      [gController launchAndExit]; // never returns (calls exit() internally)
      return 1; // only reached if launchAndExit somehow returns
    }

  // Otherwise start run loop; window will be shown in applicationDidFinishLaunching:
  NSLog(@"OnDemand -> main: starting run loop");
  [[NSApplication sharedApplication] run];
  return 0;
}

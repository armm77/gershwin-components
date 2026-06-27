/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/NSApplication.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSAutoreleasePool.h>
#import "PlayerController.h"

int main(int argc, const char *argv[])
{
   BOOL hasCommandLineArgs = (argc > 1);

   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

   // Create the application
   [NSApplication sharedApplication];

   // Create and set the controller as the delegate
   PlayerController *controller = [[PlayerController alloc] init];

   [[NSApplication sharedApplication] setDelegate:controller];
   [controller createUI];

   // If command-line args provided, let the controller handle them
   if (hasCommandLineArgs) {
       [controller handleCommandLineArguments];
   }

   [pool release];

   // Run the application
   [[NSApplication sharedApplication] run];
   return 0;
}

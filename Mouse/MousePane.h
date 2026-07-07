/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <PreferencePanes/PreferencePanes.h>

@class MouseController;

@interface MousePane : NSPreferencePane
{
    MouseController *controller;
}

@end

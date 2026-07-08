/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface EnergyController : NSObject
{
    NSView *mainView;

    // Power Source
    NSTextField *sourceLabel;
    NSTextField *batteryPercentLabel;
    NSLevelIndicator *batteryIndicator;

    // CPU
    NSPopUpButton *governorPopUp;

    // Display
    NSSlider *brightnessSlider;
    NSTextField *brightnessLabel;
    NSPopUpButton *blankPopUp;

    // Status
    NSTextField *statusLabel;

    BOOL isRefreshing;
}

- (NSView *)createMainView;
- (void)refreshFromSystem;
- (IBAction)settingChanged:(id)sender;
- (void)pollBattery;

@end

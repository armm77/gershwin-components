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
    // CPU
    NSPopUpButton *governorPopUp;

    // Display
    NSSlider *brightnessSlider;
    NSTextField *brightnessLabel;
    NSPopUpButton *blankPopUp;

    // Power Management
    NSButton *preventSleepCheckbox;
    NSButton *hddSleepCheckbox;
    NSButton *wakeNetworkCheckbox;
    NSButton *powerFailCheckbox;

    // Status
    NSTextField *statusLabel;

    BOOL isRefreshing;
    NSTask *inhibitTask;
    BOOL preventSleepState;
    BOOL hddSleepState;
    BOOL wakeNetworkState;
    BOOL powerFailState;
}

- (NSView *)createMainView;
- (void)refreshFromSystem;
- (IBAction)settingChanged:(id)sender;
- (void)pollBattery;

@end

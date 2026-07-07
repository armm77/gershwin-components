/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MouseController.h"
#import <dispatch/dispatch.h>

static NSString *const kMouseDomain = @"MousePreferences";

@interface MouseController ()
- (NSString *)findXinput;
- (NSDictionary *)xinputNameToIdMap;
- (void)enumerateDevices;
- (NSString *)identifierForDevice:(NSString *)name;
- (NSDictionary *)getPropertiesForDevice:(NSString *)device;
- (NSString *)propertyValue:(NSDictionary *)props name:(NSString *)name;
- (void)setProperty:(NSString *)prop forDevice:(NSString *)device value:(NSString *)value;
- (void)setBoolProperty:(NSString *)prop forDevice:(NSString *)device value:(BOOL)value;
- (void)applyAllSettings;
- (void)updateStatus:(NSString *)message;
@end

@implementation MouseController

- (id)init
{
    self = [super init];
    if (self) {
        isRefreshing = YES;
        xinputPath = nil;
        touchpadName = nil;
        touchpadId = nil;
        mouseName = nil;
        mouseId = nil;
        trackpointName = nil;
        trackpointId = nil;
    }
    return self;
}

- (void)dealloc
{
    [mainView release];
    [mouseSpeedSlider release];
    [mouseSpeedLabel release];
    [trackpadSpeedSlider release];
    [trackpadSpeedLabel release];
    [trackpointSpeedSlider release];
    [trackpointSpeedLabel release];
    [naturalScrollingCheckbox release];
    [tapToClickCheckbox release];
    [twoFingerRightClickCheckbox release];
    [threeFingerMiddleClickCheckbox release];
    [disableWhileTypingCheckbox release];
    [leftHandedCheckbox release];
    [statusLabel release];
    [xinputPath release];
    [touchpadName release];
    [touchpadId release];
    [mouseName release];
    [mouseId release];
    [trackpointName release];
    [trackpointId release];
    [super dealloc];
}

- (NSString *)findXinput
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *candidates = [NSArray arrayWithObjects:
        @"/usr/bin/xinput",
        @"/usr/local/bin/xinput",
        @"/opt/local/bin/xinput",
        @"/opt/bin/xinput",
        @"/usr/pkg/bin/xinput",
        @"/usr/X11R6/bin/xinput",
        nil];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) {
            return path;
        }
    }
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/which"];
    [task setArguments:[NSArray arrayWithObject:@"xinput"]];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    [task release];
    NSString *trim = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trim length] > 0 && [fm isExecutableFileAtPath:trim]) {
        return trim;
    }
    return nil;
}

- (NSDictionary *)xinputNameToIdMap
{
    if (!xinputPath) {
        return [NSDictionary dictionary];
    }
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:xinputPath];
    [task setArguments:[NSArray arrayWithObjects:@"list", nil]];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    [task release];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    // Parse "xinput list" output: matches lines like:
    //   ↳ SynPS/2 Synaptics TouchPad            id=11   [slave  pointer  (2)]
    // Also handles: "device name  id=N" and "device name\tid=N"
    NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString *name = nil;
        // Skip leading arrows/whitespace
        [scanner scanUpToCharactersFromSet:[NSCharacterSet alphanumericCharacterSet]
                                intoString:nil];
        // Scan device name up to "id="
        if (![scanner scanUpToString:@"id=" intoString:&name]) {
            continue;
        }
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name length] == 0) {
            continue;
        }
        // Scan the ID number
        [scanner scanString:@"id=" intoString:nil];
        NSString *idStr = nil;
        if (![scanner scanUpToString:@"[" intoString:&idStr]) {
            [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet]
                                    intoString:&idStr];
        }
        idStr = [idStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([idStr length] > 0) {
            [map setObject:idStr forKey:name];
        }
    }
    return map;
}

- (NSString *)identifierForDevice:(NSString *)name
{
    if (!name) return nil;
    NSDictionary *map = [self xinputNameToIdMap];
    NSString *devId = [map objectForKey:name];
    if (devId) return devId;
    // Fallback: try using the name directly (may fail with spaces on some xinput versions)
    return name;
}

- (BOOL)matchesAny:(NSString *)name patterns:(NSArray *)patterns
{
    for (NSString *p in patterns) {
        if ([name rangeOfString:p].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (void)enumerateDevices
{
    [touchpadName release];
    [touchpadId release];
    [mouseName release];
    [mouseId release];
    [trackpointName release];
    [trackpointId release];
    touchpadName = nil;
    touchpadId = nil;
    mouseName = nil;
    mouseId = nil;
    trackpointName = nil;
    trackpointId = nil;

    NSDictionary *nameMap = [self xinputNameToIdMap];
    NSArray *tpPatterns = [NSArray arrayWithObjects:
        @"TouchPad", @"Touchpad", @"touchpad",
        @"Synaptics", @"ALPS", @"Elan", @"Elantech",
        @"bcm5974", @"appletouch",
        nil];
    NSArray *trackpointPatterns = [NSArray arrayWithObjects:
        @"TrackPoint", @"Trackpoint", @"Track point",
        nil];
    NSArray *skipPatterns = [NSArray arrayWithObjects:
        @"XTEST", @"Virtual", @"virtual",
        @"keyboard", @"Keyboard",
        @"Button",
        @"HID ", @"HID/",
        @"Power Button", @"Sleep Button", @"Lid Switch",
        @"Video Bus",
        nil];
    NSArray *bsdPointerPatterns = [NSArray arrayWithObjects:
        @"ums", @"wsmouse", @"sysmouse", @"pms",
        nil];

    for (NSString *name in nameMap) {
        NSString *devId = [nameMap objectForKey:name];

        // Skip virtual/internal non-pointer devices
        if ([self matchesAny:name patterns:skipPatterns]) {
            continue;
        }

        // Touchpad detection (Linux + BSD)
        if (touchpadName == nil && [self matchesAny:name patterns:tpPatterns]) {
            touchpadName = [name copy];
            touchpadId = [devId copy];
            continue;
        }

        // TrackPoint detection
        if (trackpointName == nil && [self matchesAny:name patterns:trackpointPatterns]) {
            trackpointName = [name copy];
            trackpointId = [devId copy];
            continue;
        }

        // BSD pointer detection (if not already classified as touchpad/trackpoint)
        if (mouseName == nil && [self matchesAny:name patterns:bsdPointerPatterns]) {
            mouseName = [name copy];
            mouseId = [devId copy];
            continue;
        }

        // Generic pointer: first unmatching device becomes the mouse
        if (mouseName == nil) {
            mouseName = [name copy];
            mouseId = [devId copy];
        }
    }
}

- (NSDictionary *)getPropertiesForDevice:(NSString *)device
{
    if (!xinputPath || !device) {
        return [NSDictionary dictionary];
    }
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:xinputPath];
    [task setArguments:[NSArray arrayWithObjects:@"list-props", device, nil]];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    [task release];
    // xinput list-props output format:
    //   libprop Name (ID): value...
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSScanner *scanner = [NSScanner scannerWithString:line];
        NSString *propName = nil;
        if (![scanner scanUpToString:@"(" intoString:&propName]) {
            continue;
        }
        propName = [propName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([propName length] == 0) {
            continue;
        }
        // skip the parenthesized ID
        [scanner scanUpToString:@"):" intoString:nil];
        if (![scanner scanString:@"):" intoString:nil]) {
            continue;
        }
        NSString *value = nil;
        [scanner scanUpToString:@"\n" intoString:&value];
        if (value) {
            value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if ([value length] > 0) {
            [result setObject:value forKey:propName];
        }
    }
    return result;
}

- (NSString *)propertyValue:(NSDictionary *)props name:(NSString *)name
{
    for (NSString *key in props) {
        if ([key rangeOfString:name].location != NSNotFound) {
            return [props objectForKey:key];
        }
    }
    return nil;
}

- (void)setProperty:(NSString *)prop forDevice:(NSString *)device value:(NSString *)value
{
    if (!xinputPath || !device || !prop) {
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:xinputPath];
    [task setArguments:[NSArray arrayWithObjects:
        @"set-prop", device, prop, value, nil]];
    [task launch];
    [task waitUntilExit];
    [task release];
}

- (void)setBoolProperty:(NSString *)prop forDevice:(NSString *)device value:(BOOL)value
{
    [self setProperty:prop forDevice:device value:(value ? @"1" : @"0")];
}

- (NSView *)createMainView
{
    if (mainView) {
        return mainView;
    }
    xinputPath = [[self findXinput] retain];
    [self enumerateDevices];
    mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 370)];
    CGFloat y = 352;
    CGFloat labelX = 20;
    CGFloat controlX = 160;
    CGFloat controlW = 260;
    CGFloat rowH = 22;

    // ---- Mouse Section ----
    NSTextField *mouseSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [mouseSection setBezeled:NO];
    [mouseSection setEditable:NO];
    [mouseSection setSelectable:NO];
    [mouseSection setDrawsBackground:NO];
    [mouseSection setStringValue:@"Mouse"];
    [mouseSection setFont:[NSFont boldSystemFontOfSize:13]];
    [mouseSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:mouseSection];
    [mouseSection release];
    y -= 20;

    // Left handed
    leftHandedCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [leftHandedCheckbox setButtonType:NSSwitchButton];
    [leftHandedCheckbox setTitle:@"Swap left and right buttons"];
    [leftHandedCheckbox setTarget:self];
    [leftHandedCheckbox setAction:@selector(settingChanged:)];
    [leftHandedCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:leftHandedCheckbox];
    y -= 22;

    // Mouse speed slider
    NSTextField *mouseSpeedText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [mouseSpeedText setBezeled:NO];
    [mouseSpeedText setEditable:NO];
    [mouseSpeedText setSelectable:NO];
    [mouseSpeedText setDrawsBackground:NO];
    [mouseSpeedText setStringValue:@"Tracking speed:"];
    [mouseSpeedText setAlignment:NSRightTextAlignment];
    [mouseSpeedText setFont:[NSFont systemFontOfSize:12]];
    [mouseSpeedText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:mouseSpeedText];
    [mouseSpeedText release];
    mouseSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX, y + 2, controlW, rowH)];
    [mouseSpeedSlider setMinValue:-1.0];
    [mouseSpeedSlider setMaxValue:1.0];
    [mouseSpeedSlider setFloatValue:0.0];
    [mouseSpeedSlider setNumberOfTickMarks:11];
    [mouseSpeedSlider setAllowsTickMarkValuesOnly:NO];
    [mouseSpeedSlider setContinuous:YES];
    [mouseSpeedSlider setTarget:self];
    [mouseSpeedSlider setAction:@selector(settingChanged:)];
    [mouseSpeedSlider setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:mouseSpeedSlider];
    mouseSpeedLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX + controlW + 10, y, 60, rowH)];
    [mouseSpeedLabel setBezeled:NO];
    [mouseSpeedLabel setEditable:NO];
    [mouseSpeedLabel setSelectable:NO];
    [mouseSpeedLabel setDrawsBackground:NO];
    [mouseSpeedLabel setStringValue:@"0.00"];
    [mouseSpeedLabel setFont:[NSFont systemFontOfSize:11]];
    [mouseSpeedLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:mouseSpeedLabel];
    y -= 28;

    // ---- Separator ----
    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(labelX, y - 2, 520, 1)];
    [sep1 setBoxType:NSBoxSeparator];
    [sep1 setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
    [mainView addSubview:sep1];
    [sep1 release];
    y -= 16;

    // ---- Trackpad Section ----
    NSTextField *trackpadSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [trackpadSection setBezeled:NO];
    [trackpadSection setEditable:NO];
    [trackpadSection setSelectable:NO];
    [trackpadSection setDrawsBackground:NO];
    [trackpadSection setStringValue:@"Trackpad"];
    [trackpadSection setFont:[NSFont boldSystemFontOfSize:13]];
    [trackpadSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpadSection];
    [trackpadSection release];
    y -= 20;

    // Tap to click
    tapToClickCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [tapToClickCheckbox setButtonType:NSSwitchButton];
    [tapToClickCheckbox setTitle:@"Tap to click"];
    [tapToClickCheckbox setTarget:self];
    [tapToClickCheckbox setAction:@selector(settingChanged:)];
    [tapToClickCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:tapToClickCheckbox];
    y -= 22;

    // Two-finger right click
    twoFingerRightClickCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [twoFingerRightClickCheckbox setButtonType:NSSwitchButton];
    [twoFingerRightClickCheckbox setTitle:@"Two-finger tap = right click"];
    [twoFingerRightClickCheckbox setTarget:self];
    [twoFingerRightClickCheckbox setAction:@selector(settingChanged:)];
    [twoFingerRightClickCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:twoFingerRightClickCheckbox];
    y -= 22;

    // Three-finger middle click
    threeFingerMiddleClickCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [threeFingerMiddleClickCheckbox setButtonType:NSSwitchButton];
    [threeFingerMiddleClickCheckbox setTitle:@"Three-finger tap = middle click"];
    [threeFingerMiddleClickCheckbox setTarget:self];
    [threeFingerMiddleClickCheckbox setAction:@selector(settingChanged:)];
    [threeFingerMiddleClickCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:threeFingerMiddleClickCheckbox];
    y -= 22;

    // Disable while typing
    disableWhileTypingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [disableWhileTypingCheckbox setButtonType:NSSwitchButton];
    [disableWhileTypingCheckbox setTitle:@"Disable trackpad while typing"];
    [disableWhileTypingCheckbox setTarget:self];
    [disableWhileTypingCheckbox setAction:@selector(settingChanged:)];
    [disableWhileTypingCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:disableWhileTypingCheckbox];
    y -= 22;

    // Reverse scrolling direction
    naturalScrollingCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [naturalScrollingCheckbox setButtonType:NSSwitchButton];
    [naturalScrollingCheckbox setTitle:@"Reverse scrolling direction"];
    [naturalScrollingCheckbox setTarget:self];
    [naturalScrollingCheckbox setAction:@selector(settingChanged:)];
    [naturalScrollingCheckbox setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:naturalScrollingCheckbox];
    y -= 22;

    // Trackpad speed slider
    NSTextField *trackpadSpeedText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [trackpadSpeedText setBezeled:NO];
    [trackpadSpeedText setEditable:NO];
    [trackpadSpeedText setSelectable:NO];
    [trackpadSpeedText setDrawsBackground:NO];
    [trackpadSpeedText setStringValue:@"Tracking speed:"];
    [trackpadSpeedText setAlignment:NSRightTextAlignment];
    [trackpadSpeedText setFont:[NSFont systemFontOfSize:12]];
    [trackpadSpeedText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpadSpeedText];
    [trackpadSpeedText release];
    trackpadSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX, y + 2, controlW, rowH)];
    [trackpadSpeedSlider setMinValue:-1.0];
    [trackpadSpeedSlider setMaxValue:1.0];
    [trackpadSpeedSlider setFloatValue:0.0];
    [trackpadSpeedSlider setNumberOfTickMarks:11];
    [trackpadSpeedSlider setAllowsTickMarkValuesOnly:NO];
    [trackpadSpeedSlider setContinuous:YES];
    [trackpadSpeedSlider setTarget:self];
    [trackpadSpeedSlider setAction:@selector(settingChanged:)];
    [trackpadSpeedSlider setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpadSpeedSlider];
    trackpadSpeedLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX + controlW + 10, y, 60, rowH)];
    [trackpadSpeedLabel setBezeled:NO];
    [trackpadSpeedLabel setEditable:NO];
    [trackpadSpeedLabel setSelectable:NO];
    [trackpadSpeedLabel setDrawsBackground:NO];
    [trackpadSpeedLabel setStringValue:@"0.00"];
    [trackpadSpeedLabel setFont:[NSFont systemFontOfSize:11]];
    [trackpadSpeedLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpadSpeedLabel];
    y -= 28;

    // ---- Separator ----
    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(labelX, y - 2, 520, 1)];
    [sep2 setBoxType:NSBoxSeparator];
    [sep2 setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
    [mainView addSubview:sep2];
    [sep2 release];
    y -= 16;

    // ---- TrackPoint Section ----
    NSTextField *trackpointSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [trackpointSection setBezeled:NO];
    [trackpointSection setEditable:NO];
    [trackpointSection setSelectable:NO];
    [trackpointSection setDrawsBackground:NO];
    [trackpointSection setStringValue:@"TrackPoint"];
    [trackpointSection setFont:[NSFont boldSystemFontOfSize:13]];
    [trackpointSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpointSection];
    [trackpointSection release];
    y -= 20;

    // TrackPoint speed slider
    NSTextField *trackpointSpeedText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [trackpointSpeedText setBezeled:NO];
    [trackpointSpeedText setEditable:NO];
    [trackpointSpeedText setSelectable:NO];
    [trackpointSpeedText setDrawsBackground:NO];
    [trackpointSpeedText setStringValue:@"Tracking speed:"];
    [trackpointSpeedText setAlignment:NSRightTextAlignment];
    [trackpointSpeedText setFont:[NSFont systemFontOfSize:12]];
    [trackpointSpeedText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpointSpeedText];
    [trackpointSpeedText release];
    trackpointSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX, y + 2, controlW, rowH)];
    [trackpointSpeedSlider setMinValue:-1.0];
    [trackpointSpeedSlider setMaxValue:1.0];
    [trackpointSpeedSlider setFloatValue:0.0];
    [trackpointSpeedSlider setNumberOfTickMarks:11];
    [trackpointSpeedSlider setAllowsTickMarkValuesOnly:NO];
    [trackpointSpeedSlider setContinuous:YES];
    [trackpointSpeedSlider setTarget:self];
    [trackpointSpeedSlider setAction:@selector(settingChanged:)];
    [trackpointSpeedSlider setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpointSpeedSlider];
    trackpointSpeedLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX + controlW + 10, y, 60, rowH)];
    [trackpointSpeedLabel setBezeled:NO];
    [trackpointSpeedLabel setEditable:NO];
    [trackpointSpeedLabel setSelectable:NO];
    [trackpointSpeedLabel setDrawsBackground:NO];
    [trackpointSpeedLabel setStringValue:@"0.00"];
    [trackpointSpeedLabel setFont:[NSFont systemFontOfSize:11]];
    [trackpointSpeedLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:trackpointSpeedLabel];
    // Update section title availability indicators
    [self updateSectionTitles];
    // Status label at the bottom
    statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, 6, 520, 26)];
    [statusLabel setBezeled:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setFont:[NSFont systemFontOfSize:10]];
    [statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [mainView addSubview:statusLabel];
    [self refreshFromSystem];
    return mainView;
}

- (void)updateSectionTitles
{
    BOOL hasTrackpoint = ([trackpointName length] > 0 || [trackpointId length] > 0);
    [trackpointSpeedSlider setEnabled:hasTrackpoint];
}

- (IBAction)settingChanged:(id)sender
{
    (void)sender;
    if (isRefreshing) {
        return;
    }
    [self applyAllSettings];
}

- (void)applyAllSettings
{
    if (isRefreshing) {
        return;
    }
    NSString *tpDev = touchpadId ? touchpadId : touchpadName;
    NSString *mDev = mouseId ? mouseId : mouseName;
    NSString *tppDev = trackpointId ? trackpointId : trackpointName;

    // -- Natural Scrolling --
    BOOL natural = ([naturalScrollingCheckbox state] == NSOnState);
    if (tpDev) {
        [self setBoolProperty:@"libinput Natural Scrolling Enabled"
                    forDevice:tpDev value:natural];
    }
    if (mDev) {
        [self setBoolProperty:@"libinput Natural Scrolling Enabled"
                    forDevice:mDev value:natural];
    }
    if (tppDev) {
        [self setBoolProperty:@"libinput Natural Scrolling Enabled"
                    forDevice:tppDev value:natural];
    }
    // -- Left Handed --
    BOOL lefty = ([leftHandedCheckbox state] == NSOnState);
    if (tpDev) {
        [self setBoolProperty:@"libinput Left Handed Enabled"
                    forDevice:tpDev value:lefty];
    }
    if (mDev) {
        [self setBoolProperty:@"libinput Left Handed Enabled"
                    forDevice:mDev value:lefty];
    }
    if (tppDev) {
        [self setBoolProperty:@"libinput Left Handed Enabled"
                    forDevice:tppDev value:lefty];
    }
    // -- Mouse Speed --
    float mSpeed = [mouseSpeedSlider floatValue];
    [mouseSpeedLabel setFloatValue:mSpeed];
    if (tpDev) {
        [self setProperty:@"libinput Accel Speed" forDevice:tpDev
                    value:[NSString stringWithFormat:@"%.3f", mSpeed]];
    }
    if (mDev) {
        [self setProperty:@"libinput Accel Speed" forDevice:mDev
                    value:[NSString stringWithFormat:@"%.3f", mSpeed]];
    }
    // -- Trackpad Speed --
    float tSpeed = [trackpadSpeedSlider floatValue];
    [trackpadSpeedLabel setFloatValue:tSpeed];
    if (tpDev) {
        [self setProperty:@"libinput Accel Speed" forDevice:tpDev
                    value:[NSString stringWithFormat:@"%.3f", tSpeed]];
    }
    // -- TrackPoint Speed --
    float tpSpeed = [trackpointSpeedSlider floatValue];
    [trackpointSpeedLabel setFloatValue:tpSpeed];
    if (tppDev) {
        [self setProperty:@"libinput Accel Speed" forDevice:tppDev
                    value:[NSString stringWithFormat:@"%.3f", tpSpeed]];
    }
    // -- Tap to Click --
    BOOL tap = ([tapToClickCheckbox state] == NSOnState);
    if (tpDev) {
        [self setBoolProperty:@"libinput Tapping Enabled"
                    forDevice:tpDev value:tap];
    }
    // -- Tap Button Mapping --
    if (tpDev) {
        BOOL twoFingerRC = ([twoFingerRightClickCheckbox state] == NSOnState);
        BOOL threeFingerMC = ([threeFingerMiddleClickCheckbox state] == NSOnState);
        NSString *mapVal = @"1, 0";
        if (threeFingerMC && !twoFingerRC) {
            mapVal = @"0, 0";
        } else if (twoFingerRC && !threeFingerMC) {
            mapVal = @"1, 0";
        } else if (twoFingerRC && threeFingerMC) {
            mapVal = @"1, 0";
        }
        [self setProperty:@"libinput Tapping Button Mapping"
                forDevice:tpDev value:mapVal];
        if (threeFingerMC) {
            [self setProperty:@"libinput Clickfinger Button Mapping"
                    forDevice:tpDev value:@"1, 0"];
        } else {
            [self setProperty:@"libinput Clickfinger Button Mapping"
                    forDevice:tpDev value:@"1, 0"];
        }
    }
    // -- Disable While Typing --
    BOOL dwts = ([disableWhileTypingCheckbox state] == NSOnState);
    if (tpDev) {
        [self setBoolProperty:@"libinput Disable While Typing Enabled"
                    forDevice:tpDev value:dwts];
    }
    // -- Persist --
    [self persistSettings];
}

- (void)refreshFromSystem
{
    isRefreshing = YES;
    if (!xinputPath) {
        [self updateStatus:@"xinput not found. Install xinput package."];
        isRefreshing = NO;
        return;
    }
    [self enumerateDevices];
    [self updateSectionTitles];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *tpProps = nil;
        NSDictionary *mProps = nil;
        NSDictionary *tppProps = nil;
        if (touchpadId) {
            tpProps = [self getPropertiesForDevice:touchpadId];
        } else if (touchpadName) {
            tpProps = [self getPropertiesForDevice:touchpadName];
        }
        if (mouseId) {
            mProps = [self getPropertiesForDevice:mouseId];
        } else if (mouseName) {
            mProps = [self getPropertiesForDevice:mouseName];
        }
        if (trackpointId) {
            tppProps = [self getPropertiesForDevice:trackpointId];
        } else if (trackpointName) {
            tppProps = [self getPropertiesForDevice:trackpointName];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *tpSpeedStr = [self propertyValue:tpProps name:@"Accel Speed"];
            NSString *mSpeedStr = [self propertyValue:mProps name:@"Accel Speed"];
            NSString *tppSpeedStr = [self propertyValue:tppProps name:@"Accel Speed"];
            NSString *tpTapStr = [self propertyValue:tpProps name:@"Tapping Enabled"];
            NSString *tpNaturalStr = [self propertyValue:tpProps name:@"Natural Scrolling Enabled"];
            NSString *mNaturalStr = [self propertyValue:mProps name:@"Natural Scrolling Enabled"];
            NSString *tpLeftStr = [self propertyValue:tpProps name:@"Left Handed Enabled"];
            NSString *mLeftStr = [self propertyValue:mProps name:@"Left Handed Enabled"];
            NSString *tpDwtStr = [self propertyValue:tpProps name:@"Disable While Typing Enabled"];
            NSString *tpBtnMapStr = [self propertyValue:tpProps name:@"Tapping Button Mapping"];
            // Set mouse speed (affects both touchpad and mouse via same slider)
            if (mSpeedStr) {
                [mouseSpeedSlider setFloatValue:[mSpeedStr floatValue]];
                [mouseSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [mSpeedStr floatValue]]];
            } else if (tpSpeedStr) {
                [mouseSpeedSlider setFloatValue:[tpSpeedStr floatValue]];
                [mouseSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [tpSpeedStr floatValue]]];
            }
            // Set trackpad speed
            if (tpSpeedStr) {
                [trackpadSpeedSlider setFloatValue:[tpSpeedStr floatValue]];
                [trackpadSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [tpSpeedStr floatValue]]];
            }
            // Set TrackPoint speed
            if (tppSpeedStr) {
                [trackpointSpeedSlider setFloatValue:[tppSpeedStr floatValue]];
                [trackpointSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [tppSpeedStr floatValue]]];
            }
            // Natural scrolling
            if (tpNaturalStr) {
                [naturalScrollingCheckbox setState:([tpNaturalStr intValue] ? NSOnState : NSOffState)];
            } else if (mNaturalStr) {
                [naturalScrollingCheckbox setState:([mNaturalStr intValue] ? NSOnState : NSOffState)];
            }
            // Left handed
            if (tpLeftStr) {
                [leftHandedCheckbox setState:([tpLeftStr intValue] ? NSOnState : NSOffState)];
            } else if (mLeftStr) {
                [leftHandedCheckbox setState:([mLeftStr intValue] ? NSOnState : NSOffState)];
            }
            // Tap to click
            if (tpTapStr) {
                [tapToClickCheckbox setState:([tpTapStr intValue] ? NSOnState : NSOffState)];
            }
            // Tap button mapping
            if (tpBtnMapStr) {
                NSArray *parts = [tpBtnMapStr componentsSeparatedByString:@","];
                if ([parts count] >= 2) {
                    int v1 = [[parts objectAtIndex:0] intValue];
                    int v2 = [[parts objectAtIndex:1] intValue];
                    // Default mapping: 1,0 = left/right; 0,1 = right/left; 0,0 = 3-finger
                    [twoFingerRightClickCheckbox setState:(v1 != 0 ? NSOnState : NSOffState)];
                    [threeFingerMiddleClickCheckbox setState:(v1 == 0 && v2 == 0 ? NSOnState : NSOffState)];
                }
            }
            // Disable while typing
            if (tpDwtStr) {
                [disableWhileTypingCheckbox setState:([tpDwtStr intValue] ? NSOnState : NSOffState)];
            }
            // Override with persisted user defaults (xinput may not persist across reboots)
            {
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                NSDictionary *persisted = [defaults persistentDomainForName:kMouseDomain];
                if (persisted) {
                    NSNumber *val;

                    val = [persisted objectForKey:@"naturalScrolling"];
                    if (val) {
                        [naturalScrollingCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"leftHanded"];
                    if (val) {
                        [leftHandedCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"tapToClick"];
                    if (val) {
                        [tapToClickCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"twoFingerRightClick"];
                    if (val) {
                        [twoFingerRightClickCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"threeFingerMiddleClick"];
                    if (val) {
                        [threeFingerMiddleClickCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"disableWhileTyping"];
                    if (val) {
                        [disableWhileTypingCheckbox setState:[val boolValue] ? NSOnState : NSOffState];
                    }
                    val = [persisted objectForKey:@"mouseSpeed"];
                    if (val) {
                        [mouseSpeedSlider setFloatValue:[val floatValue]];
                        [mouseSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [val floatValue]]];
                    }
                    val = [persisted objectForKey:@"trackpadSpeed"];
                    if (val) {
                        [trackpadSpeedSlider setFloatValue:[val floatValue]];
                        [trackpadSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [val floatValue]]];
                    }
                    val = [persisted objectForKey:@"trackpointSpeed"];
                    if (val) {
                        [trackpointSpeedSlider setFloatValue:[val floatValue]];
                        [trackpointSpeedLabel setStringValue:[NSString stringWithFormat:@"%.2f", [val floatValue]]];
                    }
                }
            }
            // Push the (possibly overridden) settings to the system
            isRefreshing = NO;
            [self applyAllSettings];
            // Status message
            NSMutableString *status = [NSMutableString stringWithFormat:@"Applied"];
            if (touchpadName) {
                [status appendFormat:@" | Trackpad: %@", touchpadName];
            }
            if (mouseName) {
                [status appendFormat:@" | Mouse: %@", mouseName];
            }
            if (trackpointName) {
                [status appendFormat:@" | TrackPoint: %@", trackpointName];
            }
            [self updateStatus:status];
        });
    });
}

- (void)persistSettings
{
    NSMutableDictionary *domain = [NSMutableDictionary dictionary];
    [domain setObject:[NSNumber numberWithFloat:[mouseSpeedSlider floatValue]] forKey:@"mouseSpeed"];
    [domain setObject:[NSNumber numberWithFloat:[trackpadSpeedSlider floatValue]] forKey:@"trackpadSpeed"];
    [domain setObject:[NSNumber numberWithFloat:[trackpointSpeedSlider floatValue]] forKey:@"trackpointSpeed"];
    [domain setObject:[NSNumber numberWithBool:([naturalScrollingCheckbox state] == NSOnState)] forKey:@"naturalScrolling"];
    [domain setObject:[NSNumber numberWithBool:([leftHandedCheckbox state] == NSOnState)] forKey:@"leftHanded"];
    [domain setObject:[NSNumber numberWithBool:([tapToClickCheckbox state] == NSOnState)] forKey:@"tapToClick"];
    [domain setObject:[NSNumber numberWithBool:([twoFingerRightClickCheckbox state] == NSOnState)] forKey:@"twoFingerRightClick"];
    [domain setObject:[NSNumber numberWithBool:([threeFingerMiddleClickCheckbox state] == NSOnState)] forKey:@"threeFingerMiddleClick"];
    [domain setObject:[NSNumber numberWithBool:([disableWhileTypingCheckbox state] == NSOnState)] forKey:@"disableWhileTyping"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setPersistentDomain:domain forName:kMouseDomain];
    [defaults synchronize];
}

- (void)updateStatus:(NSString *)message
{
    [statusLabel setStringValue:(message ? message : @"")];
}

@end

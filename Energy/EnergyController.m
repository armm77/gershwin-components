/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "EnergyController.h"
#import <dispatch/dispatch.h>

static NSString *const kEnergyDomain = @"EnergyPreferences";

@interface EnergyController ()
- (NSString *)readFile:(NSString *)path;
- (BOOL)writeSysfs:(NSString *)path value:(NSString *)value;
- (NSString *)runCommand:(NSString *)cmd args:(NSArray *)args;
- (NSDictionary *)readBatteryInfo;
- (NSString *)readGovernor;
- (NSArray *)availableGovernors;
- (BOOL)writeGovernor:(NSString *)gov;
- (int)readBrightnessPercent;
- (BOOL)writeBrightnessPercent:(int)pct;
- (void)applyAllSettings;
- (void)updateStatus:(NSString *)message;
@end

@implementation EnergyController

- (id)init
{
    self = [super init];
    if (self) {
        isRefreshing = YES;
    }
    return self;
}

- (void)dealloc
{
    [mainView release];
    [sourceLabel release];
    [batteryPercentLabel release];
    [batteryIndicator release];
    [governorPopUp release];
    [brightnessSlider release];
    [brightnessLabel release];
    [blankPopUp release];
    [statusLabel release];
    [super dealloc];
}

#pragma mark - System Helpers

- (NSString *)readFile:(NSString *)path
{
    NSString *content = [[[NSString alloc] initWithContentsOfFile:path
                                                        encoding:NSUTF8StringEncoding
                                                           error:NULL] autorelease];
    return [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)writeSysfs:(NSString *)path value:(NSString *)value
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:[NSArray arrayWithObjects:
        @"-c",
        [NSString stringWithFormat:@"printf '%s' '%@' | /usr/bin/sudo tee '%@' > /dev/null",
            [value UTF8String], value, path],
        nil]];
    [task launch];
    [task waitUntilExit];
    int status = [task terminationStatus];
    [task release];
    return (status == 0);
}

- (NSString *)runCommand:(NSString *)cmd args:(NSArray *)args
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:cmd];
    [task setArguments:args];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    [task release];
    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - UI

- (NSView *)createMainView
{
    if (mainView) {
        return mainView;
    }
    mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 370)];
    CGFloat y = 352;
    CGFloat labelX = 20;
    CGFloat controlX = 160;
    CGFloat controlW = 260;
    CGFloat rowH = 22;

    // ---- Power Source Section ----
    NSTextField *powerSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [powerSection setBezeled:NO];
    [powerSection setEditable:NO];
    [powerSection setSelectable:NO];
    [powerSection setDrawsBackground:NO];
    [powerSection setStringValue:@"Power Source"];
    [powerSection setFont:[NSFont boldSystemFontOfSize:13]];
    [powerSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:powerSection];
    [powerSection release];
    y -= 20;

    // Source label
    sourceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 300, rowH)];
    [sourceLabel setBezeled:NO];
    [sourceLabel setEditable:NO];
    [sourceLabel setSelectable:NO];
    [sourceLabel setDrawsBackground:NO];
    [sourceLabel setStringValue:@"Source: reading..."];
    [sourceLabel setFont:[NSFont systemFontOfSize:12]];
    [sourceLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:sourceLabel];
    y -= 22;

    // Battery percent label + level indicator
    batteryPercentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 100, rowH)];
    [batteryPercentLabel setBezeled:NO];
    [batteryPercentLabel setEditable:NO];
    [batteryPercentLabel setSelectable:NO];
    [batteryPercentLabel setDrawsBackground:NO];
    [batteryPercentLabel setStringValue:@"Battery: --%"];
    [batteryPercentLabel setFont:[NSFont systemFontOfSize:12]];
    [batteryPercentLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:batteryPercentLabel];

    batteryIndicator = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(controlX, y + 3, controlW, 16)];
#ifdef GNUSTEP
    // GNUstep uses warningLevel/tickMark for level indicator style
    [batteryIndicator setWarningValue:75];
    [batteryIndicator setCriticalValue:25];
#else
    [batteryIndicator setLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle];
#endif
    [batteryIndicator setMinValue:0];
    [batteryIndicator setMaxValue:100];
    [batteryIndicator setDoubleValue:0];
    [batteryIndicator setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:batteryIndicator];
    y -= 24;

    // ---- Separator ----
    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(labelX, y - 2, 520, 1)];
    [sep1 setBoxType:NSBoxSeparator];
    [sep1 setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
    [mainView addSubview:sep1];
    [sep1 release];
    y -= 16;

    // ---- CPU Performance Section ----
    NSTextField *cpuSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [cpuSection setBezeled:NO];
    [cpuSection setEditable:NO];
    [cpuSection setSelectable:NO];
    [cpuSection setDrawsBackground:NO];
    [cpuSection setStringValue:@"CPU Performance"];
    [cpuSection setFont:[NSFont boldSystemFontOfSize:13]];
    [cpuSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:cpuSection];
    [cpuSection release];
    y -= 20;

    // Governor label
    NSTextField *govText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [govText setBezeled:NO];
    [govText setEditable:NO];
    [govText setSelectable:NO];
    [govText setDrawsBackground:NO];
    [govText setStringValue:@"Governor:"];
    [govText setAlignment:NSRightTextAlignment];
    [govText setFont:[NSFont systemFontOfSize:12]];
    [govText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:govText];
    [govText release];

    governorPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, y, controlW, rowH)];
    [governorPopUp setTarget:self];
    [governorPopUp setAction:@selector(settingChanged:)];
    [governorPopUp setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:governorPopUp];
    y -= 28;

    // ---- Separator ----
    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(labelX, y - 2, 520, 1)];
    [sep2 setBoxType:NSBoxSeparator];
    [sep2 setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
    [mainView addSubview:sep2];
    [sep2 release];
    y -= 16;

    // ---- Display Section ----
    NSTextField *dispSection = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, 200, 18)];
    [dispSection setBezeled:NO];
    [dispSection setEditable:NO];
    [dispSection setSelectable:NO];
    [dispSection setDrawsBackground:NO];
    [dispSection setStringValue:@"Display"];
    [dispSection setFont:[NSFont boldSystemFontOfSize:13]];
    [dispSection setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:dispSection];
    [dispSection release];
    y -= 20;

    // Brightness slider
    NSTextField *brightText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [brightText setBezeled:NO];
    [brightText setEditable:NO];
    [brightText setSelectable:NO];
    [brightText setDrawsBackground:NO];
    [brightText setStringValue:@"Brightness:"];
    [brightText setAlignment:NSRightTextAlignment];
    [brightText setFont:[NSFont systemFontOfSize:12]];
    [brightText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:brightText];
    [brightText release];

    brightnessSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(controlX, y + 2, controlW - 50, rowH)];
    [brightnessSlider setMinValue:1];
    [brightnessSlider setMaxValue:100];
    [brightnessSlider setFloatValue:100];
    [brightnessSlider setNumberOfTickMarks:11];
    [brightnessSlider setAllowsTickMarkValuesOnly:NO];
    [brightnessSlider setContinuous:YES];
    [brightnessSlider setTarget:self];
    [brightnessSlider setAction:@selector(settingChanged:)];
    [brightnessSlider setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:brightnessSlider];

    brightnessLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(controlX + controlW - 40, y, 45, rowH)];
    [brightnessLabel setBezeled:NO];
    [brightnessLabel setEditable:NO];
    [brightnessLabel setSelectable:NO];
    [brightnessLabel setDrawsBackground:NO];
    [brightnessLabel setStringValue:@"100%"];
    [brightnessLabel setFont:[NSFont systemFontOfSize:11]];
    [brightnessLabel setAlignment:NSRightTextAlignment];
    [brightnessLabel setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:brightnessLabel];
    y -= 28;

    // Screen blank
    NSTextField *blankText = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX + 10, y, 120, rowH)];
    [blankText setBezeled:NO];
    [blankText setEditable:NO];
    [blankText setSelectable:NO];
    [blankText setDrawsBackground:NO];
    [blankText setStringValue:@"Screen blanks:"];
    [blankText setAlignment:NSRightTextAlignment];
    [blankText setFont:[NSFont systemFontOfSize:12]];
    [blankText setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:blankText];
    [blankText release];

    blankPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, y, controlW, rowH)];
    [blankPopUp addItemWithTitle:@"Never"];
    [blankPopUp addItemWithTitle:@"1 minute"];
    [blankPopUp addItemWithTitle:@"5 minutes"];
    [blankPopUp addItemWithTitle:@"10 minutes"];
    [blankPopUp addItemWithTitle:@"15 minutes"];
    [blankPopUp addItemWithTitle:@"30 minutes"];
    [blankPopUp setTarget:self];
    [blankPopUp setAction:@selector(settingChanged:)];
    [blankPopUp setAutoresizingMask:NSViewMaxYMargin];
    [mainView addSubview:blankPopUp];

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

#pragma mark - Actions

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
    // -- CPU Governor --
    NSString *gov = [[governorPopUp selectedItem] title];
    if (![gov isEqualToString:[self readGovernor]]) {
        [self writeGovernor:gov];
    }

    // -- Brightness --
    int brightness = (int)[brightnessSlider intValue];
    [self writeBrightnessPercent:brightness];

    // -- Screen blank --
    int blankSeconds = 0;
    NSString *blankTitle = [[blankPopUp selectedItem] title];
    if ([blankTitle isEqualToString:@"1 minute"]) {
        blankSeconds = 60;
    } else if ([blankTitle isEqualToString:@"5 minutes"]) {
        blankSeconds = 300;
    } else if ([blankTitle isEqualToString:@"10 minutes"]) {
        blankSeconds = 600;
    } else if ([blankTitle isEqualToString:@"15 minutes"]) {
        blankSeconds = 900;
    } else if ([blankTitle isEqualToString:@"30 minutes"]) {
        blankSeconds = 1800;
    }
    // DPMS: xset dpms <standby> <suspend> <off>
    NSString *blankStr = (blankSeconds > 0) ? [NSString stringWithFormat:@"%d", blankSeconds] : @"0";
    [self runCommand:@"/usr/bin/xset"
                args:[NSArray arrayWithObjects:@"dpms", blankStr, blankStr, blankStr, nil]];
    if (blankSeconds == 0) {
        [self runCommand:@"/usr/bin/xset" args:[NSArray arrayWithObjects:@"-dpms", nil]];
    } else {
        [self runCommand:@"/usr/bin/xset" args:[NSArray arrayWithObjects:@"+dpms", nil]];
    }

    // -- Persist --
    [self persistSettings];
    [self updateStatus:@"Applied"];
}

- (void)refreshFromSystem
{
    isRefreshing = YES;

    // -- Power source / battery --
    NSDictionary *batt = [self readBatteryInfo];
    NSString *source = [batt objectForKey:@"source"];
    int percent = [[batt objectForKey:@"percent"] intValue];
    NSString *status = [batt objectForKey:@"status"];

    if ([source isEqualToString:@"AC"]) {
        NSString *src = @"Source: AC Power";
        if ([status length] > 0) {
            src = [src stringByAppendingFormat:@" (%@)", status];
        }
        [sourceLabel setStringValue:src];
    } else if ([source isEqualToString:@"Battery"]) {
        [sourceLabel setStringValue:@"Source: Battery"];
    } else {
        [sourceLabel setStringValue:@"Source: Unknown"];
    }

    if (percent >= 0) {
        [batteryPercentLabel setStringValue:[NSString stringWithFormat:@"Battery: %d%%", percent]];
        [batteryIndicator setDoubleValue:percent];
    } else {
        [batteryPercentLabel setStringValue:@"Battery: N/A"];
        [batteryIndicator setDoubleValue:0];
    }

    // -- CPU Governor --
    [governorPopUp removeAllItems];
    NSArray *govs = [self availableGovernors];
    for (NSString *gov in govs) {
        if ([gov length] > 0) {
            [governorPopUp addItemWithTitle:gov];
        }
    }
    NSString *currentGov = [self readGovernor];
    if ([currentGov length] > 0) {
        [governorPopUp selectItemWithTitle:currentGov];
    }

    // -- Brightness --
    int pct = [self readBrightnessPercent];
    [brightnessSlider setIntValue:pct];
    [brightnessLabel setStringValue:[NSString stringWithFormat:@"%d%%", pct]];

    // -- Screen blank (read from xset) --
    NSString *xsetOut = [self runCommand:@"/usr/bin/xset" args:[NSArray arrayWithObjects:@"q", nil]];
    BOOL dpmsEnabled = ([xsetOut rangeOfString:@"DPMS is Enabled"].location != NSNotFound);
    if (dpmsEnabled) {
        NSScanner *scanner = [NSScanner scannerWithString:xsetOut];
        if ([scanner scanUpToString:@"Standby:" intoString:nil]) {
            int standby = 0;
            [scanner scanString:@"Standby:" intoString:nil];
            [scanner scanInt:&standby];
            if (standby <= 0) {
                [blankPopUp selectItemWithTitle:@"Never"];
            } else if (standby <= 60) {
                [blankPopUp selectItemWithTitle:@"1 minute"];
            } else if (standby <= 300) {
                [blankPopUp selectItemWithTitle:@"5 minutes"];
            } else if (standby <= 600) {
                [blankPopUp selectItemWithTitle:@"10 minutes"];
            } else if (standby <= 900) {
                [blankPopUp selectItemWithTitle:@"15 minutes"];
            } else {
                [blankPopUp selectItemWithTitle:@"30 minutes"];
            }
        }
    } else {
        [blankPopUp selectItemWithTitle:@"Never"];
    }

    // -- Override with persisted user defaults --
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *persisted = [defaults persistentDomainForName:kEnergyDomain];
        if (persisted) {
            NSNumber *val;

            val = [persisted objectForKey:@"brightness"];
            if (val) {
                [brightnessSlider setIntValue:[val intValue]];
                [brightnessLabel setStringValue:[NSString stringWithFormat:@"%d%%", [val intValue]]];
            }
            val = [persisted objectForKey:@"screenBlank"];
            if (val) {
                [blankPopUp selectItemAtIndex:[val intValue]];
            }
        }
    }

    isRefreshing = NO;
    [self updateStatus:@"Ready"];
}

- (void)persistSettings
{
    NSMutableDictionary *domain = [NSMutableDictionary dictionary];
    [domain setObject:[[governorPopUp selectedItem] title] forKey:@"governor"];
    [domain setObject:[NSNumber numberWithInt:[brightnessSlider intValue]] forKey:@"brightness"];
    [domain setObject:[NSNumber numberWithInt:[blankPopUp indexOfSelectedItem]] forKey:@"screenBlank"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setPersistentDomain:domain forName:kEnergyDomain];
    [defaults synchronize];
}

- (void)updateStatus:(NSString *)message
{
    [statusLabel setStringValue:(message ? message : @"")];
}

#pragma mark - Platform Helpers

- (NSDictionary *)readBatteryInfo
{
    NSString *source = @"Unknown";
    int percent = -1;
    NSString *status = @"";

#if defined(__linux__)
    NSString *acOnline = [self readFile:@"/sys/class/power_supply/AC/online"];
    NSString *battCap = [self readFile:@"/sys/class/power_supply/BAT0/capacity"];
    NSString *battStatus = [self readFile:@"/sys/class/power_supply/BAT0/status"];

    source = [acOnline isEqualToString:@"1"] ? @"AC" : @"Battery";
    if ([battCap length] > 0) percent = [battCap intValue];
    if ([battStatus length] > 0) status = [battStatus capitalizedString];
#elif defined(__FreeBSD__)
    NSString *acline = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.acline", nil]];
    NSString *life = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.battery.life", nil]];
    NSString *state = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.battery.state", nil]];

    source = [acline isEqualToString:@"1"] ? @"AC" : @"Battery";
    if ([life length] > 0) percent = [life intValue];
    if ([state length] > 0) {
        int s = [state intValue];
        status = (s == 1) ? @"Discharging" :
                 (s == 2) ? @"Charging" :
                 (s == 7) ? @"Charged" :
                 (s == 0) ? @"Idle" : state;
    }
#elif defined(__OpenBSD__)
    NSString *acline = [self runCommand:@"/usr/sbin/apm" args:[NSArray arrayWithObjects:@"-a", nil]];
    NSString *life = [self runCommand:@"/usr/sbin/apm" args:[NSArray arrayWithObjects:@"-l", nil]];
    NSString *bstate = [self runCommand:@"/usr/sbin/apm" args:[NSArray arrayWithObjects:@"-b", nil]];

    source = [acline isEqualToString:@"1"] ? @"AC" : @"Battery";
    if ([life length] > 0) percent = [life intValue];
    if ([bstate length] > 0) {
        int s = [bstate intValue];
        status = (s == 0) ? @"High" :
                 (s == 1) ? @"Low" :
                 (s == 2) ? @"Critical" :
                 (s == 3) ? @"Charging" : bstate;
    }
#elif defined(__NetBSD__)
    NSString *acline = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.acline", nil]];
    NSString *life = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.battery.life", nil]];
    NSString *state = [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.acpi.battery.state", nil]];

    source = [acline isEqualToString:@"1"] ? @"AC" : @"Battery";
    if ([life length] > 0) percent = [life intValue];
    if ([state length] > 0) {
        int s = [state intValue];
        status = (s == 1) ? @"Discharging" :
                 (s == 2) ? @"Charging" :
                 (s == 7) ? @"Charged" : state;
    }
#endif
    return [NSDictionary dictionaryWithObjectsAndKeys:
        source, @"source",
        [NSNumber numberWithInt:percent], @"percent",
        status, @"status", nil];
}

- (NSString *)readGovernor
{
#if defined(__linux__)
    return [self readFile:@"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"];
#elif defined(__FreeBSD__)
    return [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"dev.cpu.0.freq", nil]];
#elif defined(__OpenBSD__)
    return [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"hw.setperf", nil]];
#elif defined(__NetBSD__)
    return [self runCommand:@"/sbin/sysctl" args:[NSArray arrayWithObjects:@"-n", @"machdep.cpu.frequency.current", nil]];
#else
    return @"";
#endif
}

- (NSArray *)availableGovernors
{
#if defined(__linux__)
    NSString *raw = [self readFile:@"/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"];
    if ([raw length] == 0) {
        return [NSArray arrayWithObjects:@"powersave", @"performance", nil];
    }
    return [raw componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
#elif defined(__FreeBSD__)
    /* FreeBSD cpufreq: report common frequencies as "governors" */
    return [NSArray arrayWithObjects:@"Auto", @"Maximum", @"Minimum", nil];
#elif defined(__OpenBSD__)
    /* OpenBSD hw.setperf: 0..100 */
    return [NSArray arrayWithObjects:@"Power Save", @"Auto", @"Performance", nil];
#elif defined(__NetBSD__)
    return [NSArray arrayWithObjects:@"Auto", @"Maximum", @"Minimum", nil];
#else
    return [NSArray arrayWithObjects:@"Auto", nil];
#endif
}

- (BOOL)writeGovernor:(NSString *)gov
{
#if defined(__linux__)
    NSString *path = @"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor";
    BOOL ok = [self writeSysfs:path value:gov];
    /* Apply to all online CPUs */
    [self runCommand:@"/bin/sh"
                args:[NSArray arrayWithObjects:@"-c",
                      @"for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do "
                       "printf '%s' \"$1\" | sudo tee \"$cpu\" > /dev/null; done",
                      @"sh", gov, nil]];
    return ok;
#elif defined(__FreeBSD__)
    int freq = 0;
    if ([gov isEqualToString:@"Maximum"]) freq = 100000;
    else if ([gov isEqualToString:@"Minimum"]) freq = 0;
    else freq = -1; /* Auto: let the system decide */
    if (freq >= 0) {
        [self runCommand:@"/sbin/sysctl"
                    args:[NSArray arrayWithObjects:@"dev.cpu.0.freq", [NSString stringWithFormat:@"%d", freq], nil]];
    }
    return YES;
#elif defined(__OpenBSD__)
    int perf = 50;
    if ([gov isEqualToString:@"Performance"]) perf = 100;
    else if ([gov isEqualToString:@"Power Save"]) perf = 0;
    [self runCommand:@"/sbin/sysctl"
                args:[NSArray arrayWithObjects:@"hw.setperf", [NSString stringWithFormat:@"%d", perf], nil]];
    return YES;
#elif defined(__NetBSD__)
    /* NetBSD: mostly read-only; just return YES */
    return YES;
#else
    return YES;
#endif
}

- (int)readBrightnessPercent
{
#if defined(__linux__)
    int maxBrightness = [[self readFile:@"/sys/class/backlight/intel_backlight/max_brightness"] intValue];
    int curBrightness = [[self readFile:@"/sys/class/backlight/intel_backlight/brightness"] intValue];
    if (maxBrightness > 0) {
        return (curBrightness * 100 / maxBrightness);
    }
    return 100;
#elif defined(__FreeBSD__) || defined(__NetBSD__)
    NSString *b = [self runCommand:@"/usr/local/bin/xbacklight"
                             args:[NSArray arrayWithObjects:@"-get", nil]];
    if ([b length] > 0) {
        return (int)([b doubleValue] + 0.5);
    }
    return 100;
#elif defined(__OpenBSD__)
    NSString *b = [self runCommand:@"/usr/sbin/wsconsctl"
                             args:[NSArray arrayWithObjects:@"brightness", nil]];
    if ([b length] == 0) {
        b = [self runCommand:@"/usr/local/bin/xbacklight"
                       args:[NSArray arrayWithObjects:@"-get", nil]];
    }
    if ([b length] > 0) {
        return (int)([b doubleValue] + 0.5);
    }
    return 100;
#else
    return 100;
#endif
}

- (BOOL)writeBrightnessPercent:(int)pct
{
    if (pct < 1) pct = 1;
#if defined(__linux__)
    int maxBrightness = [[self readFile:@"/sys/class/backlight/intel_backlight/max_brightness"] intValue];
    if (maxBrightness > 0) {
        int val = (pct * maxBrightness) / 100;
        return [self writeSysfs:@"/sys/class/backlight/intel_backlight/brightness"
                          value:[NSString stringWithFormat:@"%d", val]];
    }
    return NO;
#elif defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
    /* xbacklight works on all BSDs with X11 */
    [self runCommand:@"/usr/local/bin/xbacklight"
                args:[NSArray arrayWithObjects:@"-set", [NSString stringWithFormat:@"%d", pct], nil]];
    /* On OpenBSD, also try wsconsctl */
#if defined(__OpenBSD__)
    [self runCommand:@"/usr/sbin/wsconsctl"
                args:[NSArray arrayWithObjects:@"brightness", [NSString stringWithFormat:@"%d", pct], nil]];
#endif
    return YES;
#else
    return YES;
#endif
}

#pragma mark - Polling

- (void)pollBattery
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSDictionary *batt = [self readBatteryInfo];
        NSString *source = [batt objectForKey:@"source"];
        int percent = [[batt objectForKey:@"percent"] intValue];
        NSString *status = [batt objectForKey:@"status"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([source isEqualToString:@"AC"]) {
                NSString *src = @"Source: AC Power";
                if ([status length] > 0) {
                    src = [src stringByAppendingFormat:@" (%@)", status];
                }
                [sourceLabel setStringValue:src];
            } else if ([source isEqualToString:@"Battery"]) {
                [sourceLabel setStringValue:@"Source: Battery"];
            }

            if (percent >= 0) {
                [batteryPercentLabel setStringValue:[NSString stringWithFormat:@"Battery: %d%%", percent]];
                [batteryIndicator setDoubleValue:percent];
            }
        });
    });
}

@end

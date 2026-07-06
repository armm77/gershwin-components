/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SysfsBacklightBackend.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dirent.h>
#import <unistd.h>

#ifdef __linux__

@interface SysfsBacklightBackend ()
{
    NSString *_devicePath;
    int _maxBrightness;
}
@end

@implementation SysfsBacklightBackend

- (instancetype)init
{
    self = [super init];
    if (self) {
        _devicePath = [self findBestDevice];
        if (_devicePath) {
            _maxBrightness = [self readIntFromPath:[_devicePath stringByAppendingPathComponent:@"max_brightness"]];
            NSDebugLLog(@"gwcomp", @"SysfsBacklightBackend: using device %@ (max=%d)",
                  _devicePath, _maxBrightness);
        } else {
            NSDebugLLog(@"gwcomp", @"SysfsBacklightBackend: no backlight device found");
        }
    }
    return self;
}

- (NSString *)findBestDevice
{
    const char *dir = "/sys/class/backlight";
    DIR *d = opendir(dir);
    if (!d) {
        return nil;
    }

    NSString *best = nil;
    int bestMax = 0;
    struct dirent *entry;

    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }

        NSString *devPath = [NSString stringWithFormat:@"/sys/class/backlight/%s", entry->d_name];
        int max = [self readIntFromPath:[devPath stringByAppendingPathComponent:@"max_brightness"]];

        if (max > bestMax) {
            bestMax = max;
            best = devPath;
        }
    }

    closedir(d);
    return best;
}

- (int)readIntFromPath:(NSString *)path
{
    FILE *f = fopen([path UTF8String], "r");
    if (!f) {
        return 0;
    }

    char buf[32] = {0};
    int val = 0;
    if (fgets(buf, (int)sizeof(buf), f)) {
        val = atoi(buf);
    }

    fclose(f);
    return val;
}

- (int)current
{
    if (!_devicePath) {
        return 0;
    }

    return [self readIntFromPath:[_devicePath stringByAppendingPathComponent:@"brightness"]];
}

- (int)maximum
{
    return _maxBrightness;
}

- (void)set:(int)value
{
    if (!_devicePath) {
        return;
    }

    int clamped = value;
    if (clamped < 0) clamped = 0;
    if (clamped > _maxBrightness) clamped = _maxBrightness;

    NSString *path = [_devicePath stringByAppendingPathComponent:@"brightness"];
    FILE *f = fopen([path UTF8String], "w");
    if (!f) {
        NSDebugLLog(@"gwcomp", @"SysfsBacklightBackend: failed to open %@ for writing", path);
        return;
    }

    fprintf(f, "%d", clamped);
    fclose(f);

    NSDebugLLog(@"gwcomp", @"SysfsBacklightBackend: set brightness to %d (raw=%d, max=%d)",
          clamped, value, _maxBrightness);
}

@end

#else

@implementation SysfsBacklightBackend

- (instancetype)init
{
    self = [super init];
    return self;
}

- (int)current
{
    return 0;
}

- (int)maximum
{
    return 0;
}

- (void)set:(int)value
{
    (void)value;
}

@end

#endif

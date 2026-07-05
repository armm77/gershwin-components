/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// GSDiskUtilities.m
// GSAssistantFramework - Disk Management Utilities
//

#import "GSDiskUtilities.h"

@implementation GSDisk

@synthesize deviceName, description, size, geomName, isRemovable, isWritable;

@end

@implementation GSDiskUtilities

#pragma mark - Platform detection

+ (BOOL)toolAvailable:(NSString *)path
{
    return [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

+ (NSString *)captureOutputOfTool:(NSString *)path arguments:(NSArray *)args
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:path];
    if (args) [task setArguments:args];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    NSFileHandle *file = [pipe fileHandleForReading];

    @try {
        [task launch];
        [task waitUntilExit];

        NSData *data = [file readDataToEndOfFile];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    } @catch (NSException *exception) {
        return nil;
    }
}

+ (NSString *)valueFromPairsLine:(NSString *)line forKey:(NSString *)key
{
    NSString *pattern = [NSString stringWithFormat:@"%@=\"", key];
    NSRange range = [line rangeOfString:pattern];
    if (range.location == NSNotFound) return nil;

    NSUInteger start = range.location + range.length;
    NSInteger end = start;
    while (end < (NSInteger)[line length] && [line characterAtIndex:end] != '"') {
        end++;
    }
    if (end >= (NSInteger)start) {
        return [line substringWithRange:NSMakeRange(start, end - start)];
    }
    return nil;
}

#pragma mark - Main API (dispatches to platform)

+ (NSArray *)getAvailableDisks
{
    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: getAvailableDisks");

    if ([self toolAvailable:@"/bin/lsblk"]) {
        return [self getAvailableDisksLinux];
    }
    if ([self toolAvailable:@"/sbin/geom"]) {
        return [self getAvailableDisksFreeBSD];
    }
    if ([self toolAvailable:@"/sbin/sysctl"]) {
        return [self getAvailableDisksBSD];
    }

    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: No disk enumeration tool found");
    return @[];
}

+ (GSDisk *)getDiskInfo:(NSString *)deviceName
{
    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: getDiskInfo: %@", deviceName);

    if ([self toolAvailable:@"/bin/lsblk"]) {
        return [self getDiskInfoLinux:deviceName];
    }
    if ([self toolAvailable:@"/sbin/geom"]) {
        return [self getDiskInfoFreeBSD:deviceName];
    }
    if ([self toolAvailable:@"/sbin/sysctl"]) {
        return [self getDiskInfoBSD:deviceName];
    }

    return nil;
}

+ (BOOL)unmountPartitionsForDisk:(NSString *)deviceName
{
    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: unmountPartitionsForDisk: %@", deviceName);

    NSString *diskPattern = [NSString stringWithFormat:@"/dev/%@*", deviceName];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", [NSString stringWithFormat:@"ls %@ 2>/dev/null || true", diskPattern]]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];

    NSFileHandle *file = [pipe fileHandleForReading];

    @try {
        [task launch];
        [task waitUntilExit];

        NSData *data = [file readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        NSArray *partitions = [output componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        for (NSString *partition in partitions) {
            if ([partition length] > 0) {
                NSTask *umountTask = [[NSTask alloc] init];
                [umountTask setLaunchPath:@"/sbin/umount"];
                [umountTask setArguments:@[partition]];

                @try {
                    [umountTask launch];
                    [umountTask waitUntilExit];
                    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Unmounted %@", partition);
                } @catch (NSException *exception) {
                    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Could not unmount %@: %@",
                        partition, [exception reason]);
                }
            }
        }
    } @catch (NSException *exception) {
        NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Error finding partitions: %@",
            [exception reason]);
        return NO;
    }

    return YES;
}

#pragma mark - Linux (lsblk)

+ (NSArray *)getAvailableDisksLinux
{
    NSMutableArray *disks = [NSMutableArray array];

    NSString *output = [self captureOutputOfTool:@"/bin/lsblk"
        arguments:@[@"-d", @"-n", @"-P", @"-b",
            @"-o", @"NAME,SIZE,RM,RO,MODEL,TRAN,VENDOR"]];

    if (!output) return disks;

    NSArray *lines = [output componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        if ([line length] == 0) continue;

        NSString *name = [self valueFromPairsLine:line forKey:@"NAME"];
        if (!name) continue;

        // Skip pseudo-devices
        if ([name hasPrefix:@"loop"] || [name hasPrefix:@"ram"] ||
            [name hasPrefix:@"zram"] || [name hasPrefix:@"dm-"]) {
            continue;
        }

        GSDisk *disk = [[GSDisk alloc] init];
        disk.deviceName = name;
        disk.geomName = name;
        disk.size = [[self valueFromPairsLine:line forKey:@"SIZE"] longLongValue];
        disk.isRemovable = [[self valueFromPairsLine:line forKey:@"RM"] isEqualToString:@"1"];

        NSString *ro = [self valueFromPairsLine:line forKey:@"RO"];
        disk.isWritable = ![ro isEqualToString:@"1"];

        NSString *model = [self valueFromPairsLine:line forKey:@"MODEL"];
        NSString *vendor = [self valueFromPairsLine:line forKey:@"VENDOR"];
        NSString *tran = [self valueFromPairsLine:line forKey:@"TRAN"];

        if ([model length] > 0) {
            disk.description = model;
        } else if ([vendor length] > 0) {
            disk.description = vendor;
        } else {
            disk.description = [NSString stringWithFormat:@"/dev/%@", name];
        }

        // Mark USB transport devices as removable even if RM flag not set
        if ([tran isEqualToString:@"usb"] ||
            [tran isEqualToString:@"ieee1394"] ||
            [tran isEqualToString:@"ssd"] == NO) {
            // Keep existing RM value
        }
        if ([tran isEqualToString:@"usb"]) {
            disk.isRemovable = YES;
        }

        if (disk.size > 0) {
            [disks addObject:disk];
        }
    }

    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Found %lu disks (Linux)",
        (unsigned long)[disks count]);
    return disks;
}

+ (GSDisk *)getDiskInfoLinux:(NSString *)deviceName
{
    NSString *output = [self captureOutputOfTool:@"/bin/lsblk"
        arguments:@[@"-d", @"-n", @"-P", @"-b",
            @"-o", @"NAME,SIZE,RM,RO,MODEL,TRAN,VENDOR",
            [@"/dev/" stringByAppendingString:deviceName]]];

    if (!output) return nil;

    GSDisk *disk = [[GSDisk alloc] init];
    disk.deviceName = deviceName;
    disk.geomName = deviceName;
    disk.size = [[self valueFromPairsLine:output forKey:@"SIZE"] longLongValue];
    disk.isRemovable = [[self valueFromPairsLine:output forKey:@"RM"] isEqualToString:@"1"];
    disk.isWritable = ![[self valueFromPairsLine:output forKey:@"RO"] isEqualToString:@"1"];

    NSString *model = [self valueFromPairsLine:output forKey:@"MODEL"];
    NSString *vendor = [self valueFromPairsLine:output forKey:@"VENDOR"];
    NSString *tran = [self valueFromPairsLine:output forKey:@"TRAN"];

    if ([model length] > 0) {
        disk.description = model;
    } else if ([vendor length] > 0) {
        disk.description = vendor;
    } else {
        disk.description = @"Unknown Device";
    }

    if ([tran isEqualToString:@"usb"]) {
        disk.isRemovable = YES;
    }

    if ([deviceName hasPrefix:@"cd"] || [deviceName hasPrefix:@"sr"]) {
        return nil;
    }

    return disk;
}

#pragma mark - FreeBSD (geom)

+ (NSArray *)getAvailableDisksFreeBSD
{
    NSMutableArray *disks = [NSMutableArray array];

    NSString *output = [self captureOutputOfTool:@"/sbin/geom"
        arguments:@[@"disk", @"status", @"-s"]];

    if (!output) return disks;

    NSArray *lines = [output componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmedLine length] == 0) continue;

        NSArray *components = [trimmedLine componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *filtered = [NSMutableArray array];

        for (NSString *component in components) {
            if ([component length] > 0) {
                [filtered addObject:component];
            }
        }

        if ([filtered count] >= 3) {
            NSString *name = [filtered objectAtIndex:0];
            GSDisk *disk = [self getDiskInfoFreeBSD:name];
            if (disk && disk.size > 0) {
                [disks addObject:disk];
            }
        }
    }

    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Found %lu disks (FreeBSD)",
        (unsigned long)[disks count]);
    return disks;
}

+ (GSDisk *)getDiskInfoFreeBSD:(NSString *)deviceName
{
    NSString *output = [self captureOutputOfTool:@"/sbin/geom"
        arguments:@[@"disk", @"list", deviceName]];

    if (!output) return nil;

    GSDisk *disk = [[GSDisk alloc] init];
    disk.deviceName = deviceName;
    disk.geomName = deviceName;
    disk.description = @"Unknown Device";
    disk.size = 0;
    disk.isRemovable = [deviceName hasPrefix:@"da"];
    disk.isWritable = YES;

    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if ([trimmedLine containsString:@"descr:"]) {
            NSRange range = [trimmedLine rangeOfString:@"descr:"];
            if (range.location != NSNotFound) {
                NSString *desc = [trimmedLine substringFromIndex:range.location + range.length];
                desc = [desc stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                if ([desc length] > 0) {
                    disk.description = desc;
                }
            }
        } else if ([trimmedLine containsString:@"Mediasize:"]) {
            NSRange range = [trimmedLine rangeOfString:@"Mediasize:"];
            if (range.location != NSNotFound) {
                NSString *sizeStr = [trimmedLine substringFromIndex:range.location + range.length];
                sizeStr = [sizeStr stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                NSRange parenRange = [sizeStr rangeOfString:@" "];
                if (parenRange.location != NSNotFound) {
                    sizeStr = [sizeStr substringToIndex:parenRange.location];
                }
                disk.size = [sizeStr longLongValue];
            }
        }
    }

    if ([deviceName hasPrefix:@"cd"]) {
        return nil;
    }

    return disk;
}

#pragma mark - OpenBSD / NetBSD (sysctl)

+ (NSArray *)getAvailableDisksBSD
{
    NSMutableArray *disks = [NSMutableArray array];

    NSString *output = [self captureOutputOfTool:@"/sbin/sysctl"
        arguments:@[@"hw.disknames"]];

    if (!output) return disks;

    // Format: hw.disknames=wd0:xxxx,cd0:xxxx,sd0:xxxx
    NSRange eqRange = [output rangeOfString:@"="];
    if (eqRange.location == NSNotFound) return disks;

    NSString *list = [output substringFromIndex:eqRange.location + 1];
    list = [list stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSArray *entries = [list componentsSeparatedByString:@","];

    for (NSString *entry in entries) {
        if ([entry length] == 0) continue;

        // Each entry: wd0:xxxx  (name:identifier)
        NSRange colonRange = [entry rangeOfString:@":"];
        NSString *name;
        if (colonRange.location != NSNotFound) {
            name = [entry substringToIndex:colonRange.location];
        } else {
            name = entry;
        }

        // Skip CD-ROM drives
        if ([name hasPrefix:@"cd"]) continue;

        GSDisk *disk = [self getDiskInfoBSD:name];
        if (disk && disk.size > 0) {
            [disks addObject:disk];
        }
    }

    // On OpenBSD/NetBSD, also try dmesg for USB device descriptions
    // Fallback: use disklabel to get sizes
    for (GSDisk *disk in disks) {
        if (disk.size == 0) {
            // Try to get size from dk or disklabel
        }
    }

    NSDebugLLog(@"gwcomp", @"GSDiskUtilities: Found %lu disks (BSD via sysctl)",
        (unsigned long)[disks count]);
    return disks;
}

+ (GSDisk *)getDiskInfoBSD:(NSString *)deviceName
{
    GSDisk *disk = [[GSDisk alloc] init];
    disk.deviceName = deviceName;
    disk.geomName = deviceName;
    disk.description = @"Unknown Device";
    disk.size = 0;
    disk.isRemovable = [deviceName hasPrefix:@"sd"]; // USB/SATA drives
    disk.isWritable = YES;

    // Try disklabel for size
    NSString *dlOutput = [self captureOutputOfTool:@"/sbin/disklabel"
        arguments:@[deviceName]];

    if (dlOutput) {
        NSArray *lines = [dlOutput componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];

            // Match: "size: 12345678"
            if ([trimmed hasPrefix:@"size:"]) {
                NSString *sizeStr = [trimmed substringFromIndex:5];
                sizeStr = [sizeStr stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                disk.size = [sizeStr longLongValue];
            }
        }
    }

    // If disklabel gave no size, try dkctl (NetBSD) or read via dmesg
    if (disk.size == 0 && [self toolAvailable:@"/usr/sbin/dkctl"]) {
        [self captureOutputOfTool:@"/usr/sbin/dkctl"
            arguments:@[deviceName, @"listdev"]];
    }

    return disk;
}

#pragma mark - Formatting

+ (NSString *)formatSize:(long long)sizeInBytes
{
    return [self formatSizeWithUnit:sizeInBytes unit:@"auto"];
}

+ (NSString *)formatSizeWithUnit:(long long)sizeInBytes unit:(NSString *)preferredUnit
{
    if ([preferredUnit isEqualToString:@"auto"]) {
        if (sizeInBytes >= 1024LL * 1024LL * 1024LL) {
            double gib = (double)sizeInBytes / (1024.0 * 1024.0 * 1024.0);
            return [NSString stringWithFormat:@"%.1f GiB", gib];
        } else if (sizeInBytes >= 1024LL * 1024LL) {
            double mib = (double)sizeInBytes / (1024.0 * 1024.0);
            return [NSString stringWithFormat:@"%.1f MiB", mib];
        } else {
            double kib = (double)sizeInBytes / 1024.0;
            return [NSString stringWithFormat:@"%.1f KiB", kib];
        }
    } else if ([preferredUnit isEqualToString:@"MB"]) {
        double mb = (double)sizeInBytes / (1000.0 * 1000.0);
        return [NSString stringWithFormat:@"%.1f MB", mb];
    } else if ([preferredUnit isEqualToString:@"GB"]) {
        double gb = (double)sizeInBytes / (1000.0 * 1000.0 * 1000.0);
        return [NSString stringWithFormat:@"%.1f GB", gb];
    }
    return [self formatSize:sizeInBytes];
}

#pragma mark - Convenience methods

+ (NSArray *)getRemovableDisks
{
    NSArray *allDisks = [self getAvailableDisks];
    NSMutableArray *removableDisks = [NSMutableArray array];

    for (GSDisk *disk in allDisks) {
        if (disk.isRemovable) {
            [removableDisks addObject:disk];
        }
    }

    return removableDisks;
}

+ (NSArray *)getDisksWithMinimumSize:(long long)minimumBytes
{
    NSArray *allDisks = [self getAvailableDisks];
    NSMutableArray *suitableDisks = [NSMutableArray array];

    for (GSDisk *disk in allDisks) {
        if (disk.size >= minimumBytes) {
            [suitableDisks addObject:disk];
        }
    }

    return suitableDisks;
}

@end

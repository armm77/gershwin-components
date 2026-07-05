/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// CLMDiskUtility.m
// Create Live Media Assistant - Disk Utility
//

#import "CLMDiskUtility.h"
#import <GSDiskUtilities.h>

@implementation CLMDisk

@synthesize deviceName, description, size, geomName, isRemovable, isWritable;

@end

@implementation CLMDiskUtility

+ (NSArray *)getAvailableDisks
{
    NSDebugLLog(@"gwcomp", @"CLMDiskUtility: delegating to GSDiskUtilities");
    return [GSDiskUtilities getAvailableDisks];
}

+ (CLMDisk *)getDiskInfo:(NSString *)deviceName
{
    NSDebugLLog(@"gwcomp", @"CLMDiskUtility: delegating to GSDiskUtilities");
    GSDisk *gsDisk = [GSDiskUtilities getDiskInfo:deviceName];
    if (!gsDisk) return nil;

    CLMDisk *disk = [[CLMDisk alloc] init];
    disk.deviceName = gsDisk.deviceName;
    disk.description = gsDisk.description;
    disk.size = gsDisk.size;
    disk.geomName = gsDisk.geomName;
    disk.isRemovable = gsDisk.isRemovable;
    disk.isWritable = gsDisk.isWritable;
    return disk;
}

+ (BOOL)unmountPartitionsForDisk:(NSString *)deviceName
{
    return [GSDiskUtilities unmountPartitionsForDisk:deviceName];
}

+ (NSString *)formatSize:(long long)sizeInBytes
{
    return [GSDiskUtilities formatSize:sizeInBytes];
}

@end

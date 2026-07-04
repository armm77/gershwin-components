/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface SystemInfo : NSObject

+ (NSString *)processorName;
+ (NSString *)processorCount;
+ (NSString *)cpuArchitecture;
+ (NSString *)totalMemory;

+ (NSString *)kernelVersion;
+ (NSString *)kernelName;
+ (NSString *)distributionName;
+ (NSString *)systemUptime;

+ (NSString *)hostname;
+ (NSString *)userName;

+ (NSArray *)pciDevices;
+ (NSArray *)usbDevices;
+ (NSArray *)storageDevices;
+ (NSArray *)mountedFilesystems;
+ (NSArray *)networkInterfaces;
+ (NSArray *)inputDevices;
+ (NSArray *)inputDevicePairs;
+ (NSString *)displayInfo;
+ (NSArray *)displayPairs;
+ (NSString *)osVersion;
+ (NSString *)swapInfo;

+ (NSString *)hardwareUUID;
+ (NSString *)bootMode;
+ (NSString *)systemModel;
+ (NSString *)systemManufacturer;
+ (NSString *)systemSerial;

+ (NSArray *)audioDevices;
+ (NSArray *)kernelExtensions;
+ (NSString *)initSystem;
+ (NSArray *)deviceTreeInfo;

@end
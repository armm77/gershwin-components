/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWOSDetector - OS identification utility.
 * Identifies the current operating system by reading /etc/os-release
 * with fallback to uname for BSD systems. Supports testing via
 * path override for the os-release file.
 */

#import <Foundation/Foundation.h>

@interface GWOSDetector : NSObject

// Returns the primary OS identifier, e.g. "debian", "arch", "freebsd", "openbsd"
+ (NSString *)currentOSIdentifier;

// Returns the ordered search list: primary ID followed by ID_LIKE entries
// e.g. @[@"debian", @"ubuntu"] for Ubuntu when ID=ubuntu ID_LIKE=debian
+ (NSArray<NSString *> *)osSearchOrder;

// Testing support: override the path used for os-release detection
// Pass nil to reset to default (/etc/os-release)
+ (void)setOSReleasePathOverride:(nullable NSString *)path;

// Testing support: override uname result (nil resets to real uname)
+ (void)setUnameOverride:(nullable NSString *)unameString;

@end

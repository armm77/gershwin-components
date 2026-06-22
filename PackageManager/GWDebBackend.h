/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWDebBackend - Debian/APT package manager backend.
 * Implements the GWPackageManagerBackend protocol for Debian-based systems,
 * using apt-get for package operations and dpkg for file queries.
 */

#import <Foundation/Foundation.h>
#import "GWPackageManagerBackend.h"
#import "GWSystemCommandExecutor.h"

#pragma mark - GWDebBackend Interface

@interface GWDebBackend : NSObject <GWPackageManagerBackend>
{
@private
  NSString *_capturedErrorOutput;
}

- (instancetype)initWithExecutor:(id<GWSystemCommandExecutor>)executor;

@property (readonly, strong) id<GWSystemCommandExecutor> executor;
@property (readonly) NSString *capturedErrorOutput;

@end

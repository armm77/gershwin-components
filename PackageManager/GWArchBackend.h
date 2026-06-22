/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWArchBackend - Arch Linux (Pacman) package manager backend.
 * Implements the GWPackageManagerBackend protocol for Arch Linux systems,
 * using pacman for package operations and file queries.
 */

#import <Foundation/Foundation.h>
#import "GWPackageManagerBackend.h"
#import "GWSystemCommandExecutor.h"

#pragma mark - GWArchBackend Interface

@interface GWArchBackend : NSObject <GWPackageManagerBackend>
{
@private
  NSString *_capturedErrorOutput;
}

- (instancetype)initWithExecutor:(id<GWSystemCommandExecutor>)executor;

@property (readonly, strong) id<GWSystemCommandExecutor> executor;

@end

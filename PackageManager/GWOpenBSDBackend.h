/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWOpenBSDBackend - OpenBSD package manager backend.
 * Implements the GWPackageManagerBackend protocol for OpenBSD systems,
 * using pkg_add/pkg_delete/pkg_info for package operations.
 */

#import <Foundation/Foundation.h>
#import "GWPackageManagerBackend.h"
#import "GWSystemCommandExecutor.h"

#pragma mark - GWOpenBSDBackend Interface

@interface GWOpenBSDBackend : NSObject <GWPackageManagerBackend>

- (instancetype)initWithExecutor:(id<GWSystemCommandExecutor>)executor;

@property (readonly, strong) id<GWSystemCommandExecutor> executor;

@end

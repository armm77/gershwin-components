/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWFreeBSDBackend - FreeBSD/pkg package manager backend.
 * Implements the GWPackageManagerBackend protocol for FreeBSD systems,
 * using pkg for package operations and file queries.
 */

#import <Foundation/Foundation.h>
#import "GWPackageManagerBackend.h"
#import "GWSystemCommandExecutor.h"

#pragma mark - GWFreeBSDBackend Interface

@interface GWFreeBSDBackend : NSObject <GWPackageManagerBackend>
{
@private
  NSString *_capturedErrorOutput;
}

- (instancetype)initWithExecutor:(id<GWSystemCommandExecutor>)executor;

@property (readonly, strong) id<GWSystemCommandExecutor> executor;

@end

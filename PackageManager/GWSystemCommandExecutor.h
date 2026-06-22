/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWSystemCommandExecutor - Protocol for executing system commands.
 * Provides a mockable interface for testing backends without
 * actually running system commands.
 */

#import <Foundation/Foundation.h>

@protocol GWSystemCommandExecutor <NSObject>

// Execute a command and return the exit status
- (int)execute:(NSString *)path arguments:(NSArray<NSString *> *)args;

// Execute a command and capture stdout
- (int)execute:(NSString *)path arguments:(NSArray<NSString *> *)args
        output:(NSString *__autoreleasing *)output;

// Execute a command and capture both stdout and stderr
- (int)execute:(NSString *)path arguments:(NSArray<NSString *> *)args
        output:(NSString *__autoreleasing *)output
  errorOutput:(NSString *__autoreleasing *)errorOutput;

@end

#pragma mark - Real Implementation (uses NSTask)

@interface GWSystemCommandExecutor : NSObject <GWSystemCommandExecutor>

@property (class, readonly, strong) GWSystemCommandExecutor *sharedExecutor;

@end

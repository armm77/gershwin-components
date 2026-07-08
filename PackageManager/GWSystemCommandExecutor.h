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

// Execute a command with live per-line stderr callback and full stderr capture.
// The callback is invoked for each complete line of stderr output as the command
// runs (including trailing \r characters trimmed).  capturedErrorOutput receives
// every byte written to stderr.
- (int)execute:(NSString *)path
     arguments:(NSArray<NSString *> *)args
 stderrCallback:(nullable void (^)(NSString *line))callback
 capturedErrorOutput:(NSString *__autoreleasing *)errorOutput;

// Execute a command with live per-line callbacks for both stdout and stderr,
// plus full stderr capture.  stdoutCallback/stderrCallback are invoked for
// each complete line as the command runs.
- (int)execute:(NSString *)path
     arguments:(NSArray<NSString *> *)args
 stdoutCallback:(nullable void (^)(NSString *line))stdoutCallback
 stderrCallback:(nullable void (^)(NSString *line))stderrCallback
 capturedErrorOutput:(NSString *__autoreleasing *)errorOutput;

@end

#pragma mark - Real Implementation (uses NSTask)

@interface GWSystemCommandExecutor : NSObject <GWSystemCommandExecutor>

@property (class, readonly, strong) GWSystemCommandExecutor *sharedExecutor;

@end

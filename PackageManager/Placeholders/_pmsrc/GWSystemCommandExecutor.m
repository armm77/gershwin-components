/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * GWSystemCommandExecutor - NSTask-based implementation of the
 * GWSystemCommandExecutor protocol. Runs system commands and captures
 * their output.
 */

#import "GWSystemCommandExecutor.h"

@implementation GWSystemCommandExecutor

static GWSystemCommandExecutor *sharedExecutor = nil;

+ (GWSystemCommandExecutor *)sharedExecutor
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedExecutor = [[self alloc] init];
  });
  return sharedExecutor;
}

- (int)execute:(NSString *)path arguments:(NSArray *)args
{
  return [self execute:path arguments:args output:nil errorOutput:nil];
}

- (int)execute:(NSString *)path arguments:(NSArray *)args
        output:(NSString *__autoreleasing *)output
{
  return [self execute:path arguments:args output:output errorOutput:nil];
}

- (int)execute:(NSString *)path arguments:(NSArray *)args
        output:(NSString *__autoreleasing *)output
  errorOutput:(NSString *__autoreleasing *)errorOutput
{
  NSLog(@"GWSystemCommandExecutor → execute: %@ %@", path, [args componentsJoinedByString:@" "]);

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setArguments:args];

  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  [task setStandardOutput:outPipe];
  [task setStandardError:errPipe];

  @try
    {
      [task launch];
      [task waitUntilExit];

      int status = [task terminationStatus];

      if (output)
        {
          NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
          *output = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
          if (!*output) *output = @"";
        }

      if (errorOutput)
        {
          NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
          *errorOutput = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
          if (!*errorOutput) *errorOutput = @"";
        }

      NSLog(@"GWSystemCommandExecutor ← exit code %d (output length: %lu chars)", status, (unsigned long)[*output length]);
      return status;
    }
  @catch (NSException *e)
    {
      NSLog(@"GWSystemCommandExecutor ✗ exception executing %@: %@", path, e);
      if (output) *output = @"";
      if (errorOutput) *errorOutput = [NSString stringWithFormat:@"%@", e];
      return -1;
    }
}

@end

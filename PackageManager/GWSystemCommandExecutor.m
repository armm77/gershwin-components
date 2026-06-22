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
  NSLog(@"GWSystemCommandExecutor -> execute: %@ %@", path, [args componentsJoinedByString:@" "]);

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

      NSLog(@"GWSystemCommandExecutor <- exit code %d (output length: %lu chars)", status, (unsigned long)[*output length]);
      return status;
    }
  @catch (NSException *e)
    {
      NSLog(@"GWSystemCommandExecutor [FAIL] exception executing %@: %@", path, e);
      if (output) *output = @"";
      if (errorOutput) *errorOutput = [NSString stringWithFormat:@"%@", e];
      return -1;
    }
}

- (int)execute:(NSString *)path
     arguments:(NSArray *)args
 stderrCallback:(void (^)(NSString *line))callback
 capturedErrorOutput:(NSString *__autoreleasing *)errorOutput
{
  NSLog(@"GWSystemCommandExecutor -> execute (live stderr): %@ %@", path, [args componentsJoinedByString:@" "]);

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setArguments:args];

  // Capture nothing on stdout (pipe and discard)
  [task setStandardOutput:[NSPipe pipe]];

  NSPipe *errPipe = [NSPipe pipe];
  [task setStandardError:errPipe];
  NSFileHandle *errHandle = [errPipe fileHandleForReading];

  // Accumulator for the full stderr output
  NSMutableString *captured = [NSMutableString string];
  // Buffer for line reassembly (stderr chunks may split lines)
  NSMutableString *lineBuf = [NSMutableString string];

  id observer = [[NSNotificationCenter defaultCenter]
    addObserverForName:NSFileHandleReadCompletionNotification
                object:errHandle
                 queue:nil
            usingBlock:^(NSNotification *note)
  {
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if ([data length] > 0)
      {
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (chunk)
          {
            @synchronized(captured)
              {
                [captured appendString:chunk];
              }

            // Split into complete lines and call back for each
            [lineBuf appendString:chunk];
            NSRange r;
            while ((r = [lineBuf rangeOfString:@"\n"]).location != NSNotFound)
              {
                NSString *line = [lineBuf substringToIndex:r.location];
                [lineBuf deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
                // Trim trailing carriage returns (common in terminal output)
                line = [line stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                if (callback)
                  callback(line);
              }
          }
      }
    // Re-arm for next chunk
    [[note object] readInBackgroundAndNotify];
  }];

  @try
    {
      [task launch];
      // Prime the async read
      [errHandle readInBackgroundAndNotify];

      // Pump the run loop on this thread while the task runs
      while ([task isRunning])
        {
          [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                   beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

      [task waitUntilExit];
    }
  @catch (NSException *e)
    {
      NSLog(@"GWSystemCommandExecutor [FAIL] exception executing %@: %@", path, e);
      [[NSNotificationCenter defaultCenter] removeObserver:observer];
      if (errorOutput) *errorOutput = [captured copy];
      return -1;
    }

  [[NSNotificationCenter defaultCenter] removeObserver:observer];

  // Flush any partial final line
  if ([lineBuf length] > 0 && callback)
    callback([lineBuf copy]);

  int status = [task terminationStatus];
  if (errorOutput)
    {
      @synchronized(captured)
        {
          *errorOutput = [captured copy];
        }
    }

  NSLog(@"GWSystemCommandExecutor <- exit code %d (stderr: %lu chars)", status, (unsigned long)[captured length]);
  return status;
}

@end

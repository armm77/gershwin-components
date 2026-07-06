/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CLMBlockDeviceWriter.h"
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

@implementation CLMBlockDeviceWriter
{
    int _fd;
    int64_t _bytesWritten;
    NSString *_devicePath;
}

@synthesize devicePath = _devicePath;
@synthesize bytesWritten = _bytesWritten;

- (instancetype)initWithDevicePath:(NSString *)devicePath
{
    self = [super init];
    if (self) {
        _devicePath = [devicePath copy];
        _fd = -1;
        _bytesWritten = 0;
    }
    return self;
}

- (void)dealloc
{
    if (_fd >= 0) {
        close(_fd);
    }
}

- (BOOL)isOpen
{
    return _fd >= 0;
}

- (BOOL)openWithError:(NSError **)error
{
    if (_fd >= 0) {
        return YES;
    }

    _fd = open([_devicePath UTF8String], O_WRONLY | O_SYNC);
    if (_fd < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:errno
                                    userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    NSLocalizedString(@"Failed to open device %@: %s", @""),
                    _devicePath, strerror(errno)]
            }];
        }
        return NO;
    }

    return YES;
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    return [self writeBytes:[data bytes] length:[data length] error:error];
}

- (BOOL)writeBytes:(const void *)bytes length:(size_t)length error:(NSError **)error
{
    if (_fd < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:EBADF
                                    userInfo:@{
                NSLocalizedDescriptionKey: NSLocalizedString(@"Device not open", @"")
            }];
        }
        return NO;
    }

    const char *ptr = (const char *)bytes;
    size_t remaining = length;

    while (remaining > 0) {
        ssize_t written = write(_fd, ptr, remaining);
        if (written < 0) {
            if (errno == EINTR || errno == EAGAIN) {
                continue;
            }
            if (error) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                            code:errno
                                        userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        NSLocalizedString(@"Write error on %@: %s", @""),
                        _devicePath, strerror(errno)]
                }];
            }
            return NO;
        }
        ptr += written;
        remaining -= written;
        _bytesWritten += written;
    }

    return YES;
}

- (BOOL)synchronizeWithError:(NSError **)error
{
    if (_fd < 0) return YES;

    if (fsync(_fd) < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:errno
                                    userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    NSLocalizedString(@"fsync failed on %@: %s", @""),
                    _devicePath, strerror(errno)]
            }];
        }
        return NO;
    }

    return YES;
}

- (BOOL)closeWithError:(NSError **)error
{
    if (_fd < 0) return YES;

    [self synchronizeWithError:NULL];

    if (close(_fd) < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                        code:errno
                                    userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    NSLocalizedString(@"Close failed on %@: %s", @""),
                    _devicePath, strerror(errno)]
            }];
        }
        _fd = -1;
        return NO;
    }

    _fd = -1;
    return YES;
}

@end

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#ifndef _KEYBOARD_MANAGER_H_
#define _KEYBOARD_MANAGER_H_
#import <Foundation/Foundation.h>
#include <pwd.h>
@interface KeyboardManager : NSObject
{
    NSString *_layout;
    NSString *_variant;
    NSString *_options;
    NSString *_model;
    NSString *_lastError;
}
@property (readonly, copy) NSString *layout;
@property (readonly, copy) NSString *variant;
@property (readonly, copy) NSString *options;
@property (readonly, copy) NSString *model;
@property (readonly, copy) NSString *lastError;
- (id)init;
- (void)dealloc;
- (BOOL)detectKeyboardWithPasswd:(const struct passwd *)pwd;
- (BOOL)persistConfiguration;
- (BOOL)applyToXServer;
- (BOOL)setupWithPasswd:(const struct passwd *)pwd;
@end
#endif

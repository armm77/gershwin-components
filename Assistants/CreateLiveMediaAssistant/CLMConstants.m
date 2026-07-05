/*
 * Copyright (c) 2026 Gershwin
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CLMConstants.h"

NSArray<NSString *> *CLMAvailableRepositories(void)
{
    static NSArray<NSString *> *repos = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        repos = @[
            @"https://api.github.com/repos/gershwin-desktop/gershwin-on-freebsd/releases",
            @"https://api.github.com/repos/gershwin-desktop/gershwin-on-ghostbsd/releases",
            @"https://api.github.com/repos/gershwin-desktop/gershwin-on-debian/releases",
            @"https://api.github.com/repos/gershwin-desktop/gershwin-on-arch/releases",
            @"https://api.github.com/repos/pkgdemon/gershwin-on-nextbsd/releases",
            @"https://api.github.com/repos/ventoy/Ventoy/releases",
        ];
    });
    return repos;
}

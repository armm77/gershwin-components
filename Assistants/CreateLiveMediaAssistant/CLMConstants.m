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
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Repositories"
                                                         ofType:@"plist"];
        NSArray *slugs = [NSArray arrayWithContentsOfFile:path];
        NSMutableArray *urls = [NSMutableArray arrayWithCapacity:[slugs count]];
        for (NSString *slug in slugs) {
            [urls addObject:[NSString stringWithFormat:
                @"https://api.github.com/repos/%@/releases", slug]];
        }
        repos = [urls copy];
    });
    return repos;
}

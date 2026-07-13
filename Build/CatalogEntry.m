/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "CatalogEntry.h"

@implementation CatalogEntry

+ (NSArray *)loadCatalog
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *resDir = [bundle resourcePath];
    if (!resDir) return @[];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:resDir error:NULL];
    NSMutableArray *entries = [NSMutableArray array];

    for (NSString *file in files) {
        if (![[file pathExtension] isEqualToString:@"plist"]) continue;
        NSString *path = [resDir stringByAppendingPathComponent:file];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (!dict) continue;

        NSString *name = [dict objectForKey:@"Name"];
        NSString *gitURL = [dict objectForKey:@"GitURL"];
        if ([name length] == 0 || [gitURL length] == 0) continue;

        CatalogEntry *entry = [[CatalogEntry alloc] init];
        entry.name = name;
        entry.gitURL = gitURL;
        entry.desc = [dict objectForKey:@"Description"];
        [entries addObject:entry];
    }

    [entries sortUsingComparator:^NSComparisonResult(CatalogEntry *a, CatalogEntry *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    return entries;
}

@end

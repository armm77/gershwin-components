/*
 * Copyright 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BuildApplication.h"
#import "BuildController.h"
#import "CatalogController.h"
#import "CatalogEntry.h"

@implementation BuildApplication

@synthesize makefilePath;
@synthesize extraArgs;
@synthesize catalogBuildName;
@synthesize autoInstallLaunch;
@synthesize keepBuildDir;

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    NSLog(@"BuildApplication: willTerminate (reason=%@)", [notification userInfo]);
}

- (BOOL)isMakefileName:(NSString *)name
{
    return [name isEqualToString:@"GNUmakefile"]
        || [name isEqualToString:@"GNUmakefile.in"]
        || [name isEqualToString:@"Makefile"]
        || [name isEqualToString:@"makefile"];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    NSString *name = [filename lastPathComponent];
    if (![self isMakefileName:name]) {
        return NO;
    }
    self.makefilePath = filename;
    self.extraArgs = @[];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    for (NSString *filename in filenames) {
        NSString *name = [filename lastPathComponent];
        if ([self isMakefileName:name]) {
            self.makefilePath = filename;
            self.extraArgs = @[];
            return;
        }
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
    if (self.catalogBuildName) {
        [self buildCatalogAppWithName:self.catalogBuildName];
    } else if (self.makefilePath) {
        BuildController *controller = [[BuildController alloc] init];
        [controller setMakefilePath:self.makefilePath];
        [controller setExtraArgs:self.extraArgs];
        [controller setAutoInstallLaunch:self.autoInstallLaunch];
        [controller setKeepBuildDir:self.keepBuildDir];
        [controller showWindow];
    } else {
        CatalogController *catalog = [[CatalogController alloc] init];
        [catalog showWindow];
    }
}

- (void)buildCatalogAppWithName:(NSString *)name
{
    NSArray *entries = [CatalogEntry loadCatalog];
    CatalogEntry *entry = nil;
    for (CatalogEntry *e in entries) {
        if ([[e.name lowercaseString] isEqualToString:[name lowercaseString]]) {
            entry = e;
            break;
        }
    }
    if (!entry) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Catalog Entry Not Found"];
        [alert setInformativeText:[NSString stringWithFormat:@"No catalog entry named '%@'.", name]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSString *template = [NSString stringWithFormat:@"/tmp/Build-catalog-%@-XXXXXXXX",
                          [entry.name stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    char *tmpPath = strdup([template UTF8String]);
    if (!mkdtemp(tmpPath)) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:@"Could not create temporary directory."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        free(tmpPath);
        return;
    }
    NSString *cloneDir = [[NSString stringWithUTF8String:tmpPath] stringByStandardizingPath];
    free(tmpPath);

    NSString *guessedMakefile = [cloneDir stringByAppendingPathComponent:@"GNUmakefile"];

    BuildController *controller = [[BuildController alloc] init];
    [controller setMakefilePath:guessedMakefile];
    [controller setExtraArgs:self.extraArgs ? self.extraArgs : @[]];
    [controller setAutoInstallLaunch:self.autoInstallLaunch];
    [controller setKeepBuildDir:self.keepBuildDir];
    [controller setBuildDir:cloneDir];
    [controller showProgressWindow];
    [NSApp updateWindows];

    /* Clone the repository */
    NSTask *gitTask = [[NSTask alloc] init];
    [gitTask setLaunchPath:@"/usr/bin/git"];
    [gitTask setArguments:@[@"clone", @"--depth=1", entry.gitURL, cloneDir]];
    [gitTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [gitTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];

    @try {
        [gitTask launch];
        [gitTask waitUntilExit];
    } @catch (NSException *e) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:[NSString stringWithFormat:@"git clone failed: %@", [e reason]]];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    if ([gitTask terminationStatus] != 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Clone Failed"];
        [alert setInformativeText:@"git clone returned an error."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *resolvedMakefile = nil;
    for (NSString *mfName in @[@"GNUmakefile", @"GNUmakefile.in", @"Makefile"]) {
        NSString *mf = [cloneDir stringByAppendingPathComponent:mfName];
        if ([fm fileExistsAtPath:mf]) {
            resolvedMakefile = mf;
            break;
        }
    }

    if (!resolvedMakefile) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No Makefile Found"];
        [alert setInformativeText:@"The cloned repository does not contain a GNUmakefile or Makefile."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    [controller setMakefilePath:resolvedMakefile];
    [controller startBuild];
}

@end
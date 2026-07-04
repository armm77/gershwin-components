/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StickyNoteDatabase.h"
#import "StickyNoteDocument.h"

static StickyNoteDatabase *sharedInstance = nil;

@implementation StickyNoteDatabase

@synthesize databasePath;
@synthesize notes;
@synthesize defaults;

+ (StickyNoteDatabase *)sharedDatabase
{
    if (!sharedInstance) {
        sharedInstance = [[StickyNoteDatabase alloc] init];
    }
    return sharedInstance;
}

- (id)init
{
    return [self initWithPath:nil];
}

- (id)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        if (!path) {
            NSArray *libPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
            NSString *libPath = [libPaths count] > 0 ? [libPaths objectAtIndex:0] : 
                [@"~/Library" stringByExpandingTildeInPath];
            NSString *stickiesDir = [libPath stringByAppendingPathComponent:@"Stickies"];
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:stickiesDir]) {
                [fm createDirectoryAtPath:stickiesDir withIntermediateDirectories:YES attributes:nil error:NULL];
            }
            path = [stickiesDir stringByAppendingPathComponent:@"StickiesDatabase"];
        }
        self.databasePath = path;
        self.notes = [NSMutableArray array];
        self.defaults = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

- (void)load
{
    [notes removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:databasePath];
    if (data) {
        NSArray *plist = nil;
        @try {
            id obj = [NSPropertyListSerialization propertyListWithData:data
                                                              options:NSPropertyListImmutable
                                                               format:NULL
                                                                error:NULL];
            if ([obj isKindOfClass:[NSArray class]]) {
                plist = obj;
            }
        } @catch (NSException *e) {
            NSLog(@"[Stickies] Corrupt database: %@", e);
        }
        for (NSDictionary *dict in plist) {
            StickyNoteDocument *note = [[StickyNoteDocument alloc] initWithDictionary:dict];
            if (note) {
                [notes addObject:note];
                [note release];
            }
        }
    }
    if ([notes count] == 0) {
        StickyNoteDocument *sampleNote = [[StickyNoteDocument alloc]
            initWithText:@"Welcome to Stickies!\n\nType or paste text here.\nUse the Note menu to change colors.\nUse Window menu to float or make translucent."
                   color:nil frame:NSMakeRect(200, 300, 280, 240)
                    font:nil
              floatOnTop:NO translucent:NO collapsed:NO
            creationDate:[NSDate date] modificationDate:[NSDate date]];
        [notes addObject:sampleNote];
        [sampleNote release];
    }
}

- (void)save
{
    NSMutableArray *plist = [NSMutableArray arrayWithCapacity:[notes count]];
    for (StickyNoteDocument *note in notes) {
        [plist addObject:[note dictionaryRepresentation]];
    }
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (data) {
        [data writeToFile:databasePath atomically:YES];
    } else {
        NSLog(@"[Stickies] Failed to serialize database: %@", error);
    }
}

- (void)addNote:(StickyNoteDocument *)note
{
    [notes addObject:note];
}

- (void)removeNote:(StickyNoteDocument *)note
{
    [notes removeObject:note];
}

- (void)updateNote:(StickyNoteDocument *)note
{
}

- (NSMutableArray *)allNotes
{
    return notes;
}

- (void)dealloc
{
    [databasePath release];
    [notes release];
    [defaults release];
    [super dealloc];
}

@end
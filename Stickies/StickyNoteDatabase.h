/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class StickyNoteDocument;

@interface StickyNoteDatabase : NSObject
{
    NSString *databasePath;
    NSMutableArray *notes;
    NSUserDefaults *defaults;
}

@property (nonatomic, retain) NSString *databasePath;
@property (nonatomic, retain) NSMutableArray *notes;
@property (nonatomic, retain) NSUserDefaults *defaults;

+ (StickyNoteDatabase *)sharedDatabase;
- (id)initWithPath:(NSString *)path;
- (void)load;
- (void)save;
- (void)addNote:(StickyNoteDocument *)note;
- (void)removeNote:(StickyNoteDocument *)note;
- (void)updateNote:(StickyNoteDocument *)note;
- (NSMutableArray *)allNotes;

@end
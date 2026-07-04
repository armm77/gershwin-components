/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface StickyNoteView : NSView
{
    NSColor *backgroundColor;
    NSTextView *textView;
    NSScrollView *scrollView;
    BOOL resizing;
    NSPoint resizeStartPoint;
    NSRect resizeStartFrame;
}

@property (nonatomic, retain) NSColor *backgroundColor;
@property (nonatomic, readonly) NSTextView *textView;

- (void)setNoteColor:(NSColor *)color;
- (BOOL)isInTitleBar:(NSPoint)point;

@end
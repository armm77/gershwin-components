/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "StickyNoteWindow.h"
#import "StickyNoteView.h"
#import "StickyNoteController.h"

#define TITLE_BAR_HEIGHT 22.0

@implementation StickyNoteWindow

@synthesize isCollapsed;
@synthesize expandedFrame;
@synthesize mouseDownInTitleBar;
@synthesize mouseDownLocation;

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)styleMask
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)deferCreation
{
    self = [super initWithContentRect:contentRect
                            styleMask:NSBorderlessWindowMask
                              backing:bufferingType
                                defer:deferCreation];
    if (self) {
        [self setOpaque:NO];
        [self setHasShadow:YES];
        [self setBackgroundColor:[NSColor clearColor]];
        [self setAcceptsMouseMovedEvents:YES];
        [self setLevel:NSFloatingWindowLevel];
        [self setReleasedWhenClosed:NO];
        isCollapsed = NO;
        expandedFrame = contentRect;
        mouseDownInTitleBar = NO;
    }
    return self;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

- (BOOL)isMovable
{
    return NO;
}

- (void)collapse
{
    if (isCollapsed) return;
    isCollapsed = YES;
    expandedFrame = [self frame];
    NSRect r = expandedFrame;
    r.size.height = TITLE_BAR_HEIGHT + 4;
    [self setFrame:r display:YES animate:YES];
    StickyNoteController *controller = (StickyNoteController *)[self delegate];
    if (controller) {
        [controller setCollapsed:YES];
    }
}

- (void)expand
{
    if (!isCollapsed) return;
    isCollapsed = NO;
    [self setFrame:expandedFrame display:YES animate:YES];
    StickyNoteController *controller = (StickyNoteController *)[self delegate];
    if (controller) {
        [controller setCollapsed:NO];
    }
}

- (void)toggleCollapse
{
    if (isCollapsed) {
        [self expand];
    } else {
        [self collapse];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    StickyNoteView *cv = (StickyNoteView *)[self contentView];
    NSPoint viewPoint = [cv convertPoint:[event locationInWindow] fromView:nil];

    if ([cv isInTitleBar:viewPoint]) {
        mouseDownInTitleBar = YES;
        mouseDownLocation = [event locationInWindow];

        if ([event clickCount] == 2) {
            [self toggleCollapse];
            return;
        }
    } else {
        mouseDownInTitleBar = NO;
        [super mouseDown:event];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (mouseDownInTitleBar) {
        NSPoint current = [event locationInWindow];
        NSPoint origin = [self frame].origin;
        origin.x += current.x - mouseDownLocation.x;
        origin.y += current.y - mouseDownLocation.y;
        [self setFrameOrigin:origin];
    } else {
        [super mouseDragged:event];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    mouseDownInTitleBar = NO;
    [super mouseUp:event];
}

- (void)becomeKeyWindow
{
    [super becomeKeyWindow];
    [[self contentView] setNeedsDisplay:YES];
}

- (void)resignKeyWindow
{
    [super resignKeyWindow];
    [[self contentView] setNeedsDisplay:YES];
}

@end
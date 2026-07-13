/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class DisplayInfo;

@interface X11DisplayManager : NSObject
{
    void *_display;     // Display*
    int _screen;
    unsigned long _root; // Window
}

- (BOOL)isAvailable;

// Query outputs and populate DisplayInfo objects.  Returns nil on error.
- (NSArray<DisplayInfo *> *)listOutputs;

// Atomically set mode and position for one output.
- (BOOL)setMode:(NSString *)output
          mode:(NSString *)modeId
    positionX:(int)x
    positionY:(int)y;

// Set CRTC position while preserving the current mode.
- (BOOL)setPosition:(NSString *)output x:(int)x y:(int)y;

// Apply multiple position changes in one batch, expanding/shrinking the
// virtual screen to match the bounding box before moving CRTCs.
- (BOOL)applyPositions:(NSDictionary<NSString *, NSValue *> *)placements;

// Ensure the virtual screen is at least width x height.
- (BOOL)setScreenSize:(int)width height:(int)height;

// Mark an output as the primary display.
- (BOOL)setPrimaryOutput:(NSString *)output;

@end

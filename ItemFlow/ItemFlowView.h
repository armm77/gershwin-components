/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class ItemFlowView;

@protocol ItemFlowViewDataSource <NSObject>
- (NSUInteger)numberOfItemsInItemFlowView:(ItemFlowView *)view;
- (NSImage *)itemFlowView:(ItemFlowView *)view imageAtIndex:(NSUInteger)index;
@end

@protocol ItemFlowViewDelegate <NSObject>
@optional
- (void)itemFlowView:(ItemFlowView *)view didSelectItemAtIndex:(NSUInteger)index;
@end

@interface ItemFlowView : NSOpenGLView

@property (nonatomic, assign) id<ItemFlowViewDataSource> dataSource;
@property (nonatomic, assign) id<ItemFlowViewDelegate> delegate;
@property (nonatomic, assign) NSUInteger selectedIndex;

- (void)reloadData;

- (void)updateTexturesForIndices:(NSIndexSet *)indices;

/**
 * Resize the internal item array to count without destroying existing
 * textures.  New entries start as zero (placeholder); trailing entries
 * that are removed have their GL textures freed.
 */
- (void)setItemCount:(NSUInteger)count;

@end

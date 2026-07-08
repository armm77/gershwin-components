/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef SERVICELISTVIEW_H
#define SERVICELISTVIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSScrollView.h>
#import <Foundation/NSArray.h>

@class ServiceDetailsView;
@class ServiceListView;

@protocol ServiceListViewDelegate <NSObject>
- (void)serviceListViewSelectionDidChange:(ServiceListView *)sender;
@end

@interface ServiceListView : NSView <NSTableViewDataSource, NSTableViewDelegate>
{
  NSTableView *tableView;
  NSScrollView *scrollView;
  NSMutableArray *services;
  ServiceDetailsView *detailsView;
  id<ServiceListViewDelegate> selectionDelegate;
}

- (id)initWithFrame:(NSRect)frame;
- (void)setDetailsView:(ServiceDetailsView *)view;
- (void)setSelectionDelegate:(id<ServiceListViewDelegate>)delegate;
- (void)addService:(NSNetService *)service;
- (void)removeService:(NSNetService *)service;
- (void)clearServices;
- (NSArray *)services;
- (NSNetService *)selectedService;

@end

#endif // SERVICELISTVIEW_H

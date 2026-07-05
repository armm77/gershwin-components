/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GSStepBulletView.h"

@implementation GSStepBulletView

@synthesize state = _state;
@synthesize baseColor = _baseColor;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        _state = 0;
        _baseColor = [NSColor colorWithCalibratedRed:0.0 green:0.478 blue:1.0 alpha:1.0];
    }
    return self;
}

- (void)setState:(NSInteger)state
{
    _state = state;
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    NSColor *color;
    if (_state == 0) {
        color = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    } else if (_state == 1) {
        color = _baseColor;
    } else {
        color = [_baseColor shadowWithLevel:0.15];
    }

    [self drawAquaOrbInRect:self.bounds withBaseColor:color];
}

- (void)drawAquaOrbInRect:(NSRect)rect withBaseColor:(NSColor *)color
{
    color = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (!color) color = [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1.0];

    NSRect frame = NSInsetRect(rect, 0.5, 0.5);
    float luminosity = 0.5;

    NSColor *gradientDownColor1 = [color highlightWithLevel:luminosity];
    NSColor *gradientDownColor2 = [color colorWithAlphaComponent:0];
    NSColor *shadowColor1 = [color shadowWithLevel:0.4];
    NSColor *shadowColor2 = [color shadowWithLevel:0.6];
    NSColor *gradientStrokeColor2 = [shadowColor1 highlightWithLevel:luminosity];
    NSColor *gradientUpColor1 = [color highlightWithLevel:luminosity + 0.2];
    NSColor *gradientUpColor2 = [gradientUpColor1 colorWithAlphaComponent:0.5];
    NSColor *gradientUpColor3 = [gradientUpColor1 colorWithAlphaComponent:0];
    NSColor *light1 = [NSColor whiteColor];
    NSColor *light2 = [light1 colorWithAlphaComponent:0];

    NSGradient *gradientUp = [[NSGradient alloc] initWithColorsAndLocations:
        gradientUpColor1, 0.1, gradientUpColor2, 0.3, gradientUpColor3, 1.0, nil];
    NSGradient *gradientDown = [[NSGradient alloc] initWithColorsAndLocations:
        gradientDownColor1, 0.0, gradientDownColor2, 1.0, nil];
    NSGradient *baseGradient = [[NSGradient alloc] initWithColorsAndLocations:
        color, 0.0, shadowColor1, 0.80, nil];
    NSGradient *gradientStroke = [[NSGradient alloc] initWithColorsAndLocations:
        light1, 0.2, light2, 1.0, nil];
    NSGradient *gradientStroke2 = [[NSGradient alloc] initWithColorsAndLocations:
        shadowColor2, 0.47, gradientStrokeColor2, 1.0, nil];

    // Outer stroke rings
    NSBezierPath *outerRing = [NSBezierPath bezierPathWithOvalInRect:frame];
    [gradientStroke drawInBezierPath:outerRing angle:90];
    NSRect innerRingRect = NSInsetRect(frame, 0.5, 0.5);
    NSBezierPath *innerRing = [NSBezierPath bezierPathWithOvalInRect:innerRingRect];
    [gradientStroke2 drawInBezierPath:innerRing angle:-90];

    // Base circle with radial gradient
    NSRect baseRect = NSInsetRect(frame, 1.5, 1.5);
    NSBezierPath *basePath = [NSBezierPath bezierPathWithOvalInRect:baseRect];
    CGFloat resizeRatio = MIN(NSWidth(baseRect) / 13.0, NSHeight(baseRect) / 13.0);
    [NSGraphicsContext saveGraphicsState];
    [basePath addClip];
    [baseGradient drawFromCenter:NSMakePoint(NSMidX(baseRect), NSMidY(baseRect))
                          radius:2.85 * resizeRatio
                        toCenter:NSMakePoint(NSMidX(baseRect), NSMidY(baseRect))
                          radius:7.32 * resizeRatio
                         options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    [NSGraphicsContext restoreGraphicsState];

    // Bottom highlight
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *basePath2 = [NSBezierPath bezierPathWithOvalInRect:baseRect];
    [basePath2 addClip];
    [gradientDown drawFromCenter:NSMakePoint(NSMidX(baseRect) - 0.98 * resizeRatio,
                                             NSMidY(baseRect) - 6.5 * resizeRatio)
                          radius:1.54 * resizeRatio
                        toCenter:NSMakePoint(NSMidX(baseRect) - 1.86 * resizeRatio,
                                             NSMidY(baseRect) - 8.73 * resizeRatio)
                          radius:8.65 * resizeRatio
                         options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
    [NSGraphicsContext restoreGraphicsState];

    // Top specular highlight (half-circle)
    NSBezierPath *halfcircle = [NSBezierPath bezierPath];
    NSRect f = frame;
    [halfcircle moveToPoint:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.78652 * NSWidth(f), NSMinY(f) + 0.81548 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.94476 * NSWidth(f), NSMinY(f) + 0.66376 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.21348 * NSWidth(f), NSMinY(f) + 0.81548 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.62828 * NSWidth(f), NSMinY(f) + 0.96721 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.37172 * NSWidth(f), NSMinY(f) + 0.96721 * NSHeight(f))];
    [halfcircle curveToPoint:NSMakePoint(NSMinX(f) + 0.06684 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))
               controlPoint1:NSMakePoint(NSMinX(f) + 0.05524 * NSWidth(f), NSMinY(f) + 0.66376 * NSHeight(f))
               controlPoint2:NSMakePoint(NSMinX(f) + 0.06684 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle lineToPoint:NSMakePoint(NSMinX(f) + 0.93316 * NSWidth(f), NSMinY(f) + 0.46157 * NSHeight(f))];
    [halfcircle closePath];
    [gradientUp drawInBezierPath:halfcircle angle:-90];
}

@end

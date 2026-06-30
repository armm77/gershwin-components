/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sound Data Models Implementation
 */

#import "SoundBackend.h"
#import <AppKit/AppKit.h>

#pragma mark - AudioControl Implementation

@implementation AudioControl

@synthesize identifier;
@synthesize name;
@synthesize value;
@synthesize minValue;
@synthesize maxValue;
@synthesize isMuted;
@synthesize hasMuteControl;
@synthesize isReadOnly;

- (id)init
{
    self = [super init];
    if (self) {
        identifier = nil;
        name = nil;
        value = 0.0;
        minValue = 0.0;
        maxValue = 1.0;
        isMuted = NO;
        hasMuteControl = YES;
        isReadOnly = NO;
    }
    return self;
}

- (void)dealloc
{
    [identifier release];
    [name release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    AudioControl *copy = [[AudioControl allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.name = self.name;
    copy.value = self.value;
    copy.minValue = self.minValue;
    copy.maxValue = self.maxValue;
    copy.isMuted = self.isMuted;
    copy.hasMuteControl = self.hasMuteControl;
    copy.isReadOnly = self.isReadOnly;
    return copy;
}

- (int)percentValue
{
    if (maxValue <= minValue) return 0;
    return (int)(((value - minValue) / (maxValue - minValue)) * 100.0);
}

- (void)setPercentValue:(int)percent
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    value = minValue + ((maxValue - minValue) * percent / 100.0);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AudioControl: %@ = %.0f%% %@>",
            name, value * 100, isMuted ? @"(muted)" : @""];
}

@end

#pragma mark - AudioPort Implementation

@implementation AudioPort

@synthesize identifier;
@synthesize name;
@synthesize displayName;
@synthesize type;
@synthesize direction;
@synthesize isActive;
@synthesize isAvailable;
@synthesize priority;

- (id)init
{
    self = [super init];
    if (self) {
        identifier = nil;
        name = nil;
        displayName = nil;
        type = AudioDeviceTypeUnknown;
        direction = AudioDeviceDirectionOutput;
        isActive = NO;
        isAvailable = YES;
        priority = 0;
    }
    return self;
}

- (void)dealloc
{
    [identifier release];
    [name release];
    [displayName release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    AudioPort *copy = [[AudioPort allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.name = self.name;
    copy.displayName = self.displayName;
    copy.type = self.type;
    copy.direction = self.direction;
    copy.isActive = self.isActive;
    copy.isAvailable = self.isAvailable;
    copy.priority = self.priority;
    return copy;
}

- (NSImage *)icon
{
    NSString *iconName = nil;
    
    switch (type) {
        case AudioDeviceTypeHeadphones:
        case AudioDeviceTypeHeadsetMicrophone:
            iconName = @"NSHeadphones";
            break;
        case AudioDeviceTypeBuiltInSpeaker:
            iconName = @"NSSpeaker";
            break;
        case AudioDeviceTypeBuiltInMicrophone:
            iconName = @"NSMicrophone";
            break;
        case AudioDeviceTypeLineIn:
        case AudioDeviceTypeLineOut:
            iconName = @"NSAudioPort";
            break;
        default:
            iconName = @"NSAudioDevice";
            break;
    }
    
    NSImage *icon = [NSImage imageNamed:iconName];
    if (!icon) {
        icon = [NSImage imageNamed:NSImageNameComputer];
    }
    return icon;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AudioPort: %@ (%@)>",
            displayName ?: name, isActive ? @"active" : @"inactive"];
}

@end

#pragma mark - AudioDevice Implementation

@implementation AudioDevice

@synthesize identifier;
@synthesize name;
@synthesize displayName;
@synthesize manufacturer;
@synthesize type;
@synthesize direction;
@synthesize state;
@synthesize isDefault;
@synthesize isSystemDefault;
@synthesize volumeControl;
@synthesize balanceControl;
@synthesize ports;
@synthesize activePort;
@synthesize sampleRate;
@synthesize channels;
@synthesize bitDepth;
@synthesize cardIndex;
@synthesize deviceIndex;
@synthesize cardName;
@synthesize mixerName;
@synthesize stableDeviceId;

- (id)init
{
    self = [super init];
    if (self) {
        identifier = nil;
        name = nil;
        displayName = nil;
        manufacturer = nil;
        type = AudioDeviceTypeUnknown;
        direction = AudioDeviceDirectionOutput;
        state = AudioDeviceStateUnknown;
        isDefault = NO;
        isSystemDefault = NO;
        volumeControl = nil;
        balanceControl = nil;
        ports = [[NSMutableArray alloc] init];
        activePort = nil;
        sampleRate = 44100;
        channels = 2;
        bitDepth = 16;
        cardIndex = -1;
        deviceIndex = 0;
        cardName = nil;
        mixerName = nil;
        stableDeviceId = nil;
    }
    return self;
}

- (void)dealloc
{
    [identifier release];
    [name release];
    [displayName release];
    [manufacturer release];
    [volumeControl release];
    [balanceControl release];
    [ports release];
    [activePort release];
    [cardName release];
    [mixerName release];
    [stableDeviceId release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    AudioDevice *copy = [[AudioDevice allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.name = self.name;
    copy.displayName = self.displayName;
    copy.manufacturer = self.manufacturer;
    copy.type = self.type;
    copy.direction = self.direction;
    copy.state = self.state;
    copy.isDefault = self.isDefault;
    copy.isSystemDefault = self.isSystemDefault;
    copy.volumeControl = [[self.volumeControl copy] autorelease];
    copy.balanceControl = [[self.balanceControl copy] autorelease];
    copy.activePort = [[self.activePort copy] autorelease];
    copy.sampleRate = self.sampleRate;
    copy.channels = self.channels;
    copy.bitDepth = self.bitDepth;
    copy.cardIndex = self.cardIndex;
    copy.deviceIndex = self.deviceIndex;
    copy.cardName = self.cardName;
    copy.mixerName = self.mixerName;
    copy.stableDeviceId = self.stableDeviceId;
    
    for (AudioPort *port in self.ports) {
        [copy.ports addObject:[[port copy] autorelease]];
    }
    
    return copy;
}

- (NSString *)stateString
{
    switch (state) {
        case AudioDeviceStateAvailable:
            return @"Available";
        case AudioDeviceStateUnavailable:
            return @"Unavailable";
        case AudioDeviceStateBusy:
            return @"In Use";
        case AudioDeviceStateUnplugged:
            return @"Unplugged";
        default:
            return @"Unknown";
    }
}

- (NSString *)typeString
{
    switch (type) {
        case AudioDeviceTypeBuiltInSpeaker:
            return @"Built-in Speaker";
        case AudioDeviceTypeBuiltInMicrophone:
            return @"Built-in Microphone";
        case AudioDeviceTypeHeadphones:
            return @"Headphones";
        case AudioDeviceTypeHeadsetMicrophone:
            return @"Headset Microphone";
        case AudioDeviceTypeUSBAudio:
            return @"USB Audio";
        case AudioDeviceTypeHDMI:
            return @"HDMI";
        case AudioDeviceTypeDisplayPort:
            return @"DisplayPort";
        case AudioDeviceTypeBluetooth:
            return @"Bluetooth";
        case AudioDeviceTypeLineIn:
            return @"Line In";
        case AudioDeviceTypeLineOut:
            return @"Line Out";
        case AudioDeviceTypeSPDIF:
            return @"Digital Out";
        case AudioDeviceTypeAggregate:
            return @"Aggregate Device";
        case AudioDeviceTypeVirtual:
            return @"Virtual Device";
        default:
            return @"Audio Device";
    }
}

- (NSImage *)icon
{
    NSString *iconName = nil;
    
    switch (type) {
        case AudioDeviceTypeHeadphones:
            iconName = @"NSHeadphones";
            break;
        case AudioDeviceTypeBuiltInSpeaker:
        case AudioDeviceTypeLineOut:
            iconName = @"NSSpeaker";
            break;
        case AudioDeviceTypeBuiltInMicrophone:
        case AudioDeviceTypeHeadsetMicrophone:
            iconName = @"NSMicrophone";
            break;
        case AudioDeviceTypeUSBAudio:
            iconName = @"NSUSBDevice";
            break;
        case AudioDeviceTypeHDMI:
        case AudioDeviceTypeDisplayPort:
            iconName = @"NSDisplay";
            break;
        case AudioDeviceTypeBluetooth:
            iconName = @"NSBluetooth";
            break;
        default:
            iconName = @"NSAudioDevice";
            break;
    }
    
    NSImage *icon = [NSImage imageNamed:iconName];
    if (!icon) {
        // Fall back to a generic computer icon
        icon = [NSImage imageNamed:NSImageNameComputer];
    }
    return icon;
}

- (NSString *)formatDescription
{
    if (sampleRate > 0 && channels > 0) {
        NSString *channelStr = (channels == 1) ? @"Mono" : 
                               (channels == 2) ? @"Stereo" : 
                               [NSString stringWithFormat:@"%d channels", channels];
        
        float rateKHz = sampleRate / 1000.0;
        if (bitDepth > 0) {
            return [NSString stringWithFormat:@"%.1f kHz, %d-bit, %@", 
                    rateKHz, bitDepth, channelStr];
        } else {
            return [NSString stringWithFormat:@"%.1f kHz, %@", rateKHz, channelStr];
        }
    }
    return @"";
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AudioDevice: %@ (%@) %@ %@>",
            displayName ?: name, 
            [self typeString],
            direction == AudioDeviceDirectionOutput ? @"Output" : @"Input",
            isDefault ? @"[Default]" : @""];
}

@end

#pragma mark - AlertSound Implementation

@implementation AlertSound

@synthesize name;
@synthesize displayName;
@synthesize path;
@synthesize isSystemSound;

- (id)init
{
    self = [super init];
    if (self) {
        name = nil;
        displayName = nil;
        path = nil;
        isSystemSound = NO;
    }
    return self;
}

- (void)dealloc
{
    [name release];
    [displayName release];
    [path release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AlertSound: %@>", displayName ?: name];
}

@end

/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Sharing Controller Implementation
 */

#import "SharingController.h"
#import "GSServiceDiscoveryManager.h"
#import <dispatch/dispatch.h>
#import <sys/utsname.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <ifaddrs.h>

// AppearanceMetrics design philosophy - do NOT hardcode layout values
// All spacing shall be multiples of 4px (4, 8, 12, 16, 20, 24)
static const float METRICS_CONTENT_SIDE_MARGIN = 24.0;
static const float METRICS_CONTENT_TOP_MARGIN = 15.0;
static const float METRICS_CONTENT_BOTTOM_MARGIN = 20.0;
static const float METRICS_TEXT_INPUT_FIELD_HEIGHT = 22.0;
static const float METRICS_BUTTON_HEIGHT = 20.0;
static const float METRICS_BUTTON_MIN_WIDTH = 69.0;
static const float METRICS_RADIO_BUTTON_SIZE = 18.0;
static const float METRICS_SPACE_8 = 8.0;  // Between control and its label
static const float METRICS_SPACE_12 = 12.0;  // Between buttons
static const float METRICS_SPACE_16 = 16.0;  // Between controls in a group
static const float METRICS_SPACE_20 = 20.0;  // Between control groups, checkbox baseline-to-baseline


@implementation SharingController

- (id)init
{
    self = [super init];
    if (self) {
        NSDebugLog(@"SharingController: init starting");
        
        sshEnabled = NO;
        vncEnabled = NO;
        sftpEnabled = NO;
        afpEnabled = NO;
        smbEnabled = NO;
        webEnabled = NO;
        mediaEnabled = NO;
        currentHostname = nil;
        
        // Find helper path
        NSString *systemLibrary = @"/System/Library";
        helperPath = [[systemLibrary stringByAppendingPathComponent:@"Tools/sharing-helper"] retain];
        
        NSDebugLog(@"SharingController: Helper path set to: %@", helperPath);
        
        // Check if helper exists
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:helperPath]) {
            NSDebugLog(@"SharingController: WARNING - Helper not found at %@", helperPath);
        }
        
        // Don't initialize serviceDiscoveryManager here - do it lazily when needed
        serviceDiscoveryManager = nil;
        
        NSDebugLog(@"SharingController: init complete (lightweight init, manager will be created on demand)");
    }
    return self;
}

- (GSServiceDiscoveryManager *)ensureServiceDiscoveryManager
{
    if (serviceDiscoveryManager == nil) {
        NSDebugLog(@"SharingController: Creating GSServiceDiscoveryManager on demand");
        @try {
            serviceDiscoveryManager = [[GSServiceDiscoveryManager sharedManager] retain];
            NSDebugLog(@"SharingController: Successfully initialized GSServiceDiscoveryManager");
            if (serviceDiscoveryManager) {
                NSDebugLog(@"SharingController: mDNS backend: %@, available: %@", 
                      [serviceDiscoveryManager backendName],
                      [serviceDiscoveryManager isAvailable] ? @"YES" : @"NO");
            }
        } @catch (NSException *exception) {
            NSDebugLog(@"SharingController: EXCEPTION initializing GSServiceDiscoveryManager: %@", exception);
            serviceDiscoveryManager = nil;
        }
    }
    return serviceDiscoveryManager;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [hostnameField release];
    [applyHostnameButton release];
    [hostnameStatusLabel release];
    [sshCheckbox release];
    [vncCheckbox release];
    [sftpCheckbox release];
    [afpCheckbox release];
    [smbCheckbox release];
    [webCheckbox release];
    [mediaCheckbox release];
    [sshStatusLabel release];
    [vncStatusLabel release];
    [sftpStatusLabel release];
    [afpStatusLabel release];
    [smbStatusLabel release];
    [webStatusLabel release];
    [mediaStatusLabel release];
    [sshInfoLabel release];
    [vncInfoLabel release];
    [sftpInfoLabel release];
    [afpInfoLabel release];
    [smbInfoLabel release];
    [webInfoLabel release];
    [mediaInfoLabel release];
    [mdnsStatusLabel release];
    [currentHostname release];
    [helperPath release];
    [serviceDiscoveryManager release];
    [super dealloc];
}

#pragma mark - Helper Execution

- (NSString *)runHelper:(NSString *)command
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:helperPath]) {
        NSDebugLog(@"SharingController: Helper not found at %@", helperPath);
        return nil;
    }
    
    if (![fm isExecutableFileAtPath:helperPath]) {
        NSDebugLog(@"SharingController: Helper at %@ is not executable", helperPath);
        return nil;
    }
    
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    
    [task setLaunchPath:helperPath];
    [task setArguments:[NSArray arrayWithObject:command]];
    [task setStandardOutput:pipe];
    [task setStandardError:errorPipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    NSFileHandle *errorFile = [errorPipe fileHandleForReading];
    
    @try {
        NSDebugLog(@"SharingController: Launching helper with command: %@", command);
        [task launch];
        // Read pipe data BEFORE waitUntilExit to avoid deadlock when
        // the child fills the pipe buffer.
        NSData *data = [file readDataToEndOfFile];
        NSData *errorData = [errorFile readDataToEndOfFile];
        [task waitUntilExit];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        
        int status = [task terminationStatus];
        
        if (status != 0) {
            NSDebugLog(@"SharingController: Helper command '%@' failed with status %d: %@", 
                  command, status, errorOutput);
        }
        
        [errorOutput release];
        [task release];
        
        return [output autorelease];
    } @catch (NSException *exception) {
        NSDebugLog(@"SharingController: Exception running helper: %@", exception);
        [task release];
        return nil;
    }
}

- (BOOL)runHelperWithSudo:(NSString *)command
{
    // Use sudo -A -E to prompt for password if needed
    // -A uses SUDO_ASKPASS for graphical password prompt (if set in environment)
    // -E preserves environment
    NSString *fullCommand = [NSString stringWithFormat:@"sudo -A -E %@ %@", helperPath, command];
    
    // Use NSTask with /bin/sh to run the sudo command
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:[NSArray arrayWithObjects:@"-c", fullCommand, nil]];
    [task setStandardOutput:pipe];
    [task setStandardError:errorPipe];
    
    @try {
        [task launch];
        // Drain pipes before waitUntilExit to avoid deadlock
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];

        int status = [task terminationStatus];

        if (status != 0) {
            NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSDebugLog(@"SharingController: Command failed with status %d: %@\nError: %@", status, command, errorOutput);
            [errorOutput release];
        } else {
            NSDebugLog(@"SharingController: Successfully executed: %@", command);
        }
        
        [task release];
        return (status == 0);
    } @catch (NSException *exception) {
        NSDebugLog(@"SharingController: Exception running sudo command: %@", exception);
        [task release];
        return NO;
    }
}

#pragma mark - Status Queries

- (NSString *)getHostname
{
    NSString *output = [self runHelper:@"get-hostname"];
    if (output) {
        return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    
    // Fallback to uname
    struct utsname buf;
    if (uname(&buf) == 0) {
        return [NSString stringWithUTF8String:buf.nodename];
    }
    
    return @"localhost";
}

- (BOOL)getSSHStatus
{
    NSString *output = [self runHelper:@"ssh-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getVNCStatus
{
    NSString *output = [self runHelper:@"vnc-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getSFTPStatus
{
    NSString *output = [self runHelper:@"sftp-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getAFPStatus
{
    NSString *output = [self runHelper:@"afp-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getSMBStatus
{
    NSString *output = [self runHelper:@"smb-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getSSHInstalled
{
    NSString *output = [self runHelper:@"ssh-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    // Default: assume installed if helper fails (so we don't block the user unnecessarily)
    return YES;
}

- (BOOL)getVNCInstalled
{
    NSString *output = [self runHelper:@"vnc-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (BOOL)getSFTPInstalled
{
    NSString *output = [self runHelper:@"sftp-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (BOOL)getAFPInstalled
{
    NSString *output = [self runHelper:@"afp-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (BOOL)getSMBInstalled
{
    NSString *output = [self runHelper:@"smb-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (BOOL)getWebStatus
{
    NSString *output = [self runHelper:@"web-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getWebInstalled
{
    NSString *output = [self runHelper:@"web-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (BOOL)getMediaStatus
{
    NSString *output = [self runHelper:@"media-status"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"running"];
    }
    return NO;
}

- (BOOL)getMediaInstalled
{
    NSString *output = [self runHelper:@"media-installed"];
    if (output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [trimmed isEqualToString:@"installed"];
    }
    return YES;
}

- (NSString *)getLocalIPAddress
{
    NSMutableString *addresses = [NSMutableString string];
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            // Defensive: ifa_addr can be NULL on some systems
            if (temp_addr->ifa_addr != NULL && temp_addr->ifa_addr->sa_family == AF_INET) {
                // Skip loopback
                if (strcmp(temp_addr->ifa_name, "lo") != 0 &&
                    strcmp(temp_addr->ifa_name, "lo0") != 0) {
                    char addressBuffer[INET_ADDRSTRLEN];
                    const void *addr = &((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr;
                    if (inet_ntop(AF_INET, addr, addressBuffer, sizeof(addressBuffer)) != NULL) {
                        if ([addresses length] > 0) {
                            [addresses appendString:@", "];
                        }
                        [addresses appendString:[NSString stringWithUTF8String:addressBuffer]];
                    } else {
                        NSDebugLog(@"SharingController: inet_ntop failed for interface %s", temp_addr->ifa_name);
                    }
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    
    return [addresses length] > 0 ? addresses : @"No network connection";
}

#pragma mark - Actions

- (void)applyHostname:(id)sender
{
    NSString *newHostname = [hostnameField stringValue];
    
    // Validate hostname
    if ([newHostname length] == 0) {
        NSRunAlertPanel(@"Invalid Hostname", 
                       @"Hostname cannot be empty.", 
                       @"OK", nil, nil);
        return;
    }
    
    // Basic hostname validation (RFC 1123)
    NSCharacterSet *allowedChars = [NSCharacterSet characterSetWithCharactersInString:
                                   @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:newHostname];
    
    if (![allowedChars isSupersetOfSet:inputChars] || 
        [newHostname hasPrefix:@"-"] || 
        [newHostname hasSuffix:@"-"] ||
        [newHostname length] > 63) {
        NSRunAlertPanel(@"Invalid Hostname", 
                       @"Hostname must contain only letters, numbers, and hyphens, "
                       @"cannot start or end with a hyphen, and must be 63 characters or less.", 
                       @"OK", nil, nil);
        return;
    }
    
    NSDebugLog(@"SharingController: Setting hostname to: %@", newHostname);
    
    NSString *command = [NSString stringWithFormat:@"set-hostname %@", newHostname];
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        ASSIGN(currentHostname, newHostname);

        // Update mDNS service name and re-announce all active services
        GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
        if (mgr && [mgr isAvailable]) {
            [mgr setComputerName:newHostname];
            NSDebugLog(@"SharingController: Updated mDNS computer name to %@ and re-announced services", newHostname);
        } else {
            NSDebugLog(@"SharingController: mDNS not available, hostname changed without mDNS update");
        }

        // Refresh the UI immediately to reflect the new hostname
        [applyHostnameButton setEnabled:NO];
        [self refreshStatus:nil];

        NSDebugLog(@"SharingController: Hostname changed to %@", newHostname);

    } else {
        NSRunAlertPanel(@"Hostname Error", 
                       @"Failed to change hostname. Check system logs for details.", 
                       @"OK", nil, nil);
    }
}

- (void)clearHostnameStatus
{
    [hostnameStatusLabel setStringValue:@""];
}

- (void)hostnameDidChange:(NSNotification *)notification
{
    NSString *newValue = [hostnameField stringValue];
    BOOL changed = ![newValue isEqualToString:currentHostname];
    [applyHostnameButton setEnabled:changed];
}

- (void)toggleSSH:(id)sender
{
    BOOL shouldEnable = [sshCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"ssh-start" : @"ssh-stop";
    
    NSDebugLog(@"SharingController: %@ SSH", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        sshEnabled = shouldEnable;
        
        // Announce or unannounce via mDNS
        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                // Announce SSH service
                BOOL announced = [mgr announceService:GSServiceTypeSSH 
                                                                     port:22 
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: SSH service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce SSH service via mDNS");
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeSSH];
                NSDebugLog(@"SharingController: SSH service unannounced from mDNS");
            }
        }
        
        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: SSH %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [sshCheckbox setState:sshEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"SSH Error", 
                       @"Failed to modify SSH service. Check system logs for details.", 
                       @"OK", nil, nil);
    }
}

- (void)toggleVNC:(id)sender
{
    BOOL shouldEnable = [vncCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"vnc-start" : @"vnc-stop";
    
    NSDebugLog(@"SharingController: %@ VNC", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        vncEnabled = shouldEnable;
        
        // Announce or unannounce via mDNS
        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                // Announce VNC service (RFB)
                BOOL announced = [mgr announceService:GSServiceTypeVNC 
                                                                     port:5900 
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: VNC service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce VNC service via mDNS");
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeVNC];
                NSDebugLog(@"SharingController: VNC service unannounced from mDNS");
            }
        }
        
        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: VNC %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [vncCheckbox setState:vncEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"VNC Error", 
                       @"Failed to modify VNC service. Check system logs for details.", 
                       @"OK", nil, nil);
    }
}

- (void)toggleSFTP:(id)sender
{
    BOOL shouldEnable = [sftpCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"sftp-start" : @"sftp-stop";
    
    NSDebugLog(@"SharingController: %@ SFTP", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        sftpEnabled = shouldEnable;
        
        // Announce or unannounce via mDNS
        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                // Announce SFTP service
                BOOL announced = [mgr announceService:GSServiceTypeSFTP 
                                                                     port:22 
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: SFTP service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce SFTP service via mDNS");
                    NSRunAlertPanel(@"SFTP Warning", 
                                   @"SFTP service started but could not be announced on the network.", 
                                   @"OK", nil, nil);
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeSFTP];
                NSDebugLog(@"SharingController: SFTP service unannounced from mDNS");
            }
        }
        
        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: SFTP %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [sftpCheckbox setState:sftpEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"SFTP Error", 
                       @"Failed to modify SFTP service.\n\n"
                       @"SFTP requires SSH to be installed and properly configured. "
                       @"Please ensure OpenSSH server is installed and the SFTP subsystem is enabled in sshd_config.", 
                       @"OK", nil, nil);
    }
}

- (void)toggleAFP:(id)sender
{
    BOOL shouldEnable = [afpCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"afp-start" : @"afp-stop";
    
    NSDebugLog(@"SharingController: %@ AFP", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        afpEnabled = shouldEnable;
        
        // Announce or unannounce via mDNS
        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                // Announce AFP service
                BOOL announced = [mgr announceService:GSServiceTypeAFP 
                                                                     port:548 
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: AFP service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce AFP service via mDNS");
                    NSRunAlertPanel(@"AFP Warning", 
                                   @"AFP service started but could not be announced on the network.", 
                                   @"OK", nil, nil);
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeAFP];
                NSDebugLog(@"SharingController: AFP service unannounced from mDNS");
            }
        }
        
        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: AFP %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [afpCheckbox setState:afpEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"AFP Error", 
                       @"Failed to modify AFP service.\n\n"
                       @"AFP (Apple Filing Protocol) requires Netatalk to be installed. "
                       @"Please install Netatalk using your system's package manager:\n"
                       @"• Debian/Ubuntu: sudo apt-get install netatalk\n"
                       @"• Fedora/RHEL: sudo dnf install netatalk\n"
                       @"• FreeBSD: sudo pkg install netatalk3\n"
                       @"• Arch: sudo pacman -S netatalk", 
                       @"OK", nil, nil);
    }
}

- (void)toggleSMB:(id)sender
{
    BOOL shouldEnable = [smbCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"smb-start" : @"smb-stop";
    
    NSDebugLog(@"SharingController: %@ SMB", shouldEnable ? @"Starting" : @"Stopping");
    
    BOOL success = [self runHelperWithSudo:command];
    
    if (success) {
        smbEnabled = shouldEnable;
        
        // Announce or unannounce via mDNS
        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                // Announce SMB service
                BOOL announced = [mgr announceService:GSServiceTypeSMB 
                                                                     port:445 
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: SMB service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce SMB service via mDNS");
                    NSRunAlertPanel(@"SMB Warning", 
                                   @"SMB service started but could not be announced on the network.", 
                                   @"OK", nil, nil);
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeSMB];
                NSDebugLog(@"SharingController: SMB service unannounced from mDNS");
            }
        }
        
        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: SMB %@", shouldEnable ? @"started" : @"stopped");
    } else {
        // Revert checkbox state
        [smbCheckbox setState:smbEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"Samba Error", 
                       @"Failed to modify Samba service.\n\n"
                       @"Samba (Windows file sharing) requires the Samba server to be installed. "
                       @"Please install Samba using your system's package manager:\n"
                       @"• Debian/Ubuntu: sudo apt-get install samba\n"
                       @"• Fedora/RHEL: sudo dnf install samba\n"
                       @"• FreeBSD: sudo pkg install samba413\n"
                       @"• Arch: sudo pacman -S samba\n\n"
                       @"You may also need to configure Samba in /etc/samba/smb.conf", 
                       @"OK", nil, nil);
    }
}

- (void)toggleMedia:(id)sender
{
    BOOL shouldEnable = [mediaCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"media-start" : @"media-stop";

    NSDebugLog(@"SharingController: %@ Media Sharing", shouldEnable ? @"Starting" : @"Stopping");

    BOOL success = [self runHelperWithSudo:command];

    if (success) {
        mediaEnabled = shouldEnable;

        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                BOOL announced = [mgr announceService:GSServiceTypeMedia
                                                                     port:8200
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: Media Sharing service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce Media Sharing service via mDNS");
                    NSRunAlertPanel(@"Media Sharing Warning",
                                   @"Media Sharing started but could not be announced on the network.",
                                   @"OK", nil, nil);
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeMedia];
                NSDebugLog(@"SharingController: Media Sharing service unannounced from mDNS");
            }
        }

        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: Media Sharing %@", shouldEnable ? @"started" : @"stopped");
    } else {
        [mediaCheckbox setState:mediaEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"Media Sharing Error",
                       @"Failed to modify Media Sharing service.\n\n"
                       @"Media Sharing requires MiniDLNA (ReadyMedia) to be installed.\n"
                       @"Please install using your system's package manager:\n"
                       @"• Debian/Ubuntu: sudo apt-get install minidlna\n"
                       @"• Fedora/RHEL: sudo dnf install minidlna\n"
                       @"• FreeBSD: sudo pkg install minidlna\n"
                       @"• Arch: sudo pacman -S minidlna",
                       @"OK", nil, nil);
    }
}

- (void)toggleWeb:(id)sender
{
    BOOL shouldEnable = [webCheckbox state] == NSOnState;
    NSString *command = shouldEnable ? @"web-start" : @"web-stop";

    NSDebugLog(@"SharingController: %@ Web Server", shouldEnable ? @"Starting" : @"Stopping");

    BOOL success = [self runHelperWithSudo:command];

    if (success) {
        webEnabled = shouldEnable;

        if (shouldEnable) {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                BOOL announced = [mgr announceService:GSServiceTypeWeb
                                                                     port:80
                                                                txtRecord:nil];
                if (announced) {
                    NSDebugLog(@"SharingController: Web Server service announced via mDNS");
                } else {
                    NSDebugLog(@"SharingController: Failed to announce Web Server service via mDNS");
                    NSRunAlertPanel(@"Web Server Warning",
                                   @"Web Server started but could not be announced on the network.",
                                   @"OK", nil, nil);
                }
            }
        } else {
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable]) {
                [mgr unannounceService:GSServiceTypeWeb];
                NSDebugLog(@"SharingController: Web Server service unannounced from mDNS");
            }
        }

        [self refreshStatus:nil];
        NSDebugLog(@"SharingController: Web Server %@", shouldEnable ? @"started" : @"stopped");
    } else {
        [webCheckbox setState:webEnabled ? NSOnState : NSOffState];
        NSRunAlertPanel(@"Web Server Error",
                       @"Failed to modify Web Server service.\n\n"
                       @"Web Server requires nginx to be installed.\n"
                       @"Please install nginx using your system's package manager:\n"
                       @"• Debian/Ubuntu: sudo apt-get install nginx\n"
                       @"• Fedora/RHEL: sudo dnf install nginx\n"
                       @"• FreeBSD: sudo pkg install nginx\n"
                       @"• Arch: sudo pacman -S nginx",
                       @"OK", nil, nil);
    }
}

- (void)refreshStatus:(id)sender
{
    NSDebugLog(@"SharingController: Refreshing service status");

    // Safety check: ensure UI elements exist before trying to update them
    if (!hostnameField || !sshCheckbox) {
        NSDebugLog(@"SharingController: UI not yet initialized, skipping refresh");
        return;
    }

    if (isRefreshingStatus) {
        NSDebugLog(@"SharingController: Refresh already in progress, skipping");
        return;
    }
    isRefreshingStatus = YES;

    // Run all blocking helper queries on a background thread, then
    // update the UI back on the main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *hostname = [self getHostname];
        BOOL ssh  = [self getSSHStatus];
        BOOL vnc  = [self getVNCStatus];
        BOOL sftp = [self getSFTPStatus];
        BOOL afp  = [self getAFPStatus];
        BOOL smb  = [self getSMBStatus];
        BOOL web  = [self getWebStatus];
        BOOL media  = [self getMediaStatus];
        // Also query installation state for each service
        BOOL isSshInstalled  = [self getSSHInstalled];
        BOOL isVncInstalled  = [self getVNCInstalled];
        BOOL isSftpInstalled = [self getSFTPInstalled];
        BOOL isAfpInstalled  = [self getAFPInstalled];
        BOOL isSmbInstalled  = [self getSMBInstalled];
        BOOL isWebInstalled  = [self getWebInstalled];
        BOOL isMediaInstalled  = [self getMediaInstalled];

        dispatch_async(dispatch_get_main_queue(), ^{
            isRefreshingStatus = NO;
            [self updateUIWithHostname:hostname
                                   ssh:ssh vnc:vnc sftp:sftp afp:afp smb:smb web:web media:media
                          sshInstalled:isSshInstalled vncInstalled:isVncInstalled
                         sftpInstalled:isSftpInstalled afpInstalled:isAfpInstalled
                          smbInstalled:isSmbInstalled webInstalled:isWebInstalled mediaInstalled:isMediaInstalled];
        });
    });
}

- (void)updateUIWithHostname:(NSString *)hostname
                          ssh:(BOOL)ssh vnc:(BOOL)vnc sftp:(BOOL)sftp
                          afp:(BOOL)afp smb:(BOOL)smb web:(BOOL)web media:(BOOL)media
                 sshInstalled:(BOOL)isSshInstalled vncInstalled:(BOOL)isVncInstalled
                sftpInstalled:(BOOL)isSftpInstalled afpInstalled:(BOOL)isAfpInstalled
                 smbInstalled:(BOOL)isSmbInstalled webInstalled:(BOOL)isWebInstalled mediaInstalled:(BOOL)isMediaInstalled
{
    // Safety check in case the pane was unselected while we were querying
    if (!hostnameField || !sshCheckbox) {
        return;
    }

    // Update hostname only when the user is not actively editing the field
    if ([hostnameField currentEditor] == nil) {
        [hostnameField setStringValue:hostname];
        ASSIGN(currentHostname, hostname);
    }

    // Clear transient hostname status message (it's set by applyHostname on success)
    [hostnameStatusLabel setStringValue:@""];

    // Light grey for "N/A" (not installed) status
    NSColor *naColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];

    // Update mDNS status label with current hostname
    GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
    if (mgr && [mgr isAvailable]) {
        int announcedCount = [[mgr announcedServices] count];
        NSString *statusText = [NSString stringWithFormat:@"Service Discovery: Available (%@)\n"
                               @"Publishing services as \"%@\" on the local network.",
                               [mgr backendName], hostname];
        if (announcedCount > 0) {
            statusText = [NSString stringWithFormat:@"Service Discovery: Available (%@)\n"
                                   @"Publishing services as \"%@\" on the local network (%d active).",
                                   [mgr backendName], hostname, announcedCount];
        }
        [mdnsStatusLabel setStringValue:statusText];
        [mdnsStatusLabel setTextColor:[NSColor darkGrayColor]];
    } else {
        [mdnsStatusLabel setStringValue:@"Service Discovery: Not available\nInstall avahi-daemon or mDNSResponder for automatic network service announcement."];
        [mdnsStatusLabel setTextColor:[NSColor grayColor]];
    }

    // Determine the address to show in connection info.
    // If mDNS is available, use hostname.local for cleaner, portable connection strings
    // that work across the local network without knowing the IP.
    NSString *serviceAddress;
    if (mgr && [mgr isAvailable]) {
        serviceAddress = [NSString stringWithFormat:@"%@.local", hostname];
    } else {
        serviceAddress = [self getLocalIPAddress];
    }

    // --- SSH ---
    if (!isSshInstalled) {
        [sshCheckbox setEnabled:NO];
        [sshCheckbox setState:NSOffState];
        [sshStatusLabel setStringValue:@"N/A"];
        [sshStatusLabel setTextColor:naColor];
        [sshInfoLabel setStringValue:@"Install OpenSSH server (openssh-server) to enable Remote Login."];
        [sshInfoLabel setHidden:NO];
    } else {
        [sshCheckbox setEnabled:YES];
        sshEnabled = ssh;
        [sshCheckbox setState:sshEnabled ? NSOnState : NSOffState];

        if (sshEnabled) {
            [sshStatusLabel setStringValue:@"On"];
            [sshStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"To connect: ssh user@%@", serviceAddress];
            [sshInfoLabel setStringValue:info];
            [sshInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeSSH]) {
                [mgr announceService:GSServiceTypeSSH port:22 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced SSH service via mDNS");
            }
        } else {
            [sshStatusLabel setStringValue:@"Off"];
            [sshStatusLabel setTextColor:[NSColor grayColor]];
            [sshInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeSSH]) {
                [mgr unannounceService:GSServiceTypeSSH];
                NSDebugLog(@"SharingController: Unannounced SSH service from mDNS");
            }
        }
    }

    // --- VNC ---
    if (!isVncInstalled) {
        [vncCheckbox setEnabled:NO];
        [vncCheckbox setState:NSOffState];
        [vncStatusLabel setStringValue:@"N/A"];
        [vncStatusLabel setTextColor:naColor];
        [vncInfoLabel setStringValue:@"Install a VNC server (x11vnc, TigerVNC, or TightVNC) to enable Screen Sharing."];
        [vncInfoLabel setHidden:NO];
    } else {
        [vncCheckbox setEnabled:YES];
        vncEnabled = vnc;
        [vncCheckbox setState:vncEnabled ? NSOnState : NSOffState];

        if (vncEnabled) {
            [vncStatusLabel setStringValue:@"On"];
            [vncStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"To connect: %@ (port 5900)", serviceAddress];
            [vncInfoLabel setStringValue:info];
            [vncInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeVNC]) {
                [mgr announceService:GSServiceTypeVNC port:5900 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced VNC service via mDNS");
            }
        } else {
            [vncStatusLabel setStringValue:@"Off"];
            [vncStatusLabel setTextColor:[NSColor grayColor]];
            [vncInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeVNC]) {
                [mgr unannounceService:GSServiceTypeVNC];
                NSDebugLog(@"SharingController: Unannounced VNC service from mDNS");
            }
        }
    }

    // --- SFTP ---
    if (!isSftpInstalled) {
        [sftpCheckbox setEnabled:NO];
        [sftpCheckbox setState:NSOffState];
        [sftpStatusLabel setStringValue:@"N/A"];
        [sftpStatusLabel setTextColor:naColor];
        [sftpInfoLabel setStringValue:@"SFTP requires the OpenSSH server with SFTP subsystem enabled."];
        [sftpInfoLabel setHidden:NO];
    } else {
        [sftpCheckbox setEnabled:YES];
        sftpEnabled = sftp;
        [sftpCheckbox setState:sftpEnabled ? NSOnState : NSOffState];

        if (sftpEnabled) {
            [sftpStatusLabel setStringValue:@"On"];
            [sftpStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"SFTP via SSH: sftp user@%@", serviceAddress];
            [sftpInfoLabel setStringValue:info];
            [sftpInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeSFTP]) {
                [mgr announceService:GSServiceTypeSFTP port:22 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced SFTP service via mDNS");
            }
        } else {
            [sftpStatusLabel setStringValue:@"Off"];
            [sftpStatusLabel setTextColor:[NSColor grayColor]];
            [sftpInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeSFTP]) {
                [mgr unannounceService:GSServiceTypeSFTP];
                NSDebugLog(@"SharingController: Unannounced SFTP service from mDNS");
            }
        }
    }

    // --- AFP ---
    if (!isAfpInstalled) {
        [afpCheckbox setEnabled:NO];
        [afpCheckbox setState:NSOffState];
        [afpStatusLabel setStringValue:@"N/A"];
        [afpStatusLabel setTextColor:naColor];
        [afpInfoLabel setStringValue:@"Install Netatalk to enable Apple File Sharing (AFP)."];
        [afpInfoLabel setHidden:NO];
    } else {
        [afpCheckbox setEnabled:YES];
        afpEnabled = afp;
        [afpCheckbox setState:afpEnabled ? NSOnState : NSOffState];

        if (afpEnabled) {
            [afpStatusLabel setStringValue:@"On"];
            [afpStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"AFP available at: afp://%@ (port 548)", serviceAddress];
            [afpInfoLabel setStringValue:info];
            [afpInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeAFP]) {
                [mgr announceService:GSServiceTypeAFP port:548 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced AFP service via mDNS");
            }
        } else {
            [afpStatusLabel setStringValue:@"Off"];
            [afpStatusLabel setTextColor:[NSColor grayColor]];
            [afpInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeAFP]) {
                [mgr unannounceService:GSServiceTypeAFP];
                NSDebugLog(@"SharingController: Unannounced AFP service from mDNS");
            }
        }
    }

    // --- SMB ---
    if (!isSmbInstalled) {
        [smbCheckbox setEnabled:NO];
        [smbCheckbox setState:NSOffState];
        [smbStatusLabel setStringValue:@"N/A"];
        [smbStatusLabel setTextColor:naColor];
        [smbInfoLabel setStringValue:@"Install Samba to enable Windows File Sharing (SMB)."];
        [smbInfoLabel setHidden:NO];
    } else {
        [smbCheckbox setEnabled:YES];
        smbEnabled = smb;
        [smbCheckbox setState:smbEnabled ? NSOnState : NSOffState];

        if (smbEnabled) {
            [smbStatusLabel setStringValue:@"On"];
            [smbStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"SMB available at: smb://%@", serviceAddress];
            [smbInfoLabel setStringValue:info];
            [smbInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeSMB]) {
                [mgr announceService:GSServiceTypeSMB port:445 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced SMB service via mDNS");
            }
        } else {
            [smbStatusLabel setStringValue:@"Off"];
            [smbStatusLabel setTextColor:[NSColor grayColor]];
            [smbInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeSMB]) {
                [mgr unannounceService:GSServiceTypeSMB];
                NSDebugLog(@"SharingController: Unannounced SMB service from mDNS");
            }
        }
    }

    // --- Web Server ---
    if (!isWebInstalled) {
        [webCheckbox setEnabled:NO];
        [webCheckbox setState:NSOffState];
        [webStatusLabel setStringValue:@"N/A"];
        [webStatusLabel setTextColor:naColor];
        [webInfoLabel setStringValue:@"Install nginx to enable Web Server."];
        [webInfoLabel setHidden:NO];
    } else {
        [webCheckbox setEnabled:YES];
        webEnabled = web;
        [webCheckbox setState:webEnabled ? NSOnState : NSOffState];

        if (webEnabled) {
            [webStatusLabel setStringValue:@"On"];
            [webStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"Web Server available at: http://%@", serviceAddress];
            [webInfoLabel setStringValue:info];
            [webInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeWeb]) {
                [mgr announceService:GSServiceTypeWeb port:80 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced Web Server service via mDNS");
            }
        } else {
            [webStatusLabel setStringValue:@"Off"];
            [webStatusLabel setTextColor:[NSColor grayColor]];
            [webInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeWeb]) {
                [mgr unannounceService:GSServiceTypeWeb];
                NSDebugLog(@"SharingController: Unannounced Web Server service from mDNS");
            }
        }
    }

    // --- Media Sharing ---
    if (!isMediaInstalled) {
        [mediaCheckbox setEnabled:NO];
        [mediaCheckbox setState:NSOffState];
        [mediaStatusLabel setStringValue:@"N/A"];
        [mediaStatusLabel setTextColor:naColor];
        [mediaInfoLabel setStringValue:@"Install MiniDLNA (ReadyMedia) to enable Media Sharing."];
        [mediaInfoLabel setHidden:NO];
    } else {
        [mediaCheckbox setEnabled:YES];
        mediaEnabled = media;
        [mediaCheckbox setState:mediaEnabled ? NSOnState : NSOffState];

        if (mediaEnabled) {
            [mediaStatusLabel setStringValue:@"On"];
            [mediaStatusLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.0 alpha:1.0]];

            NSString *info = [NSString stringWithFormat:@"Media Sharing available at: http://%@:8200", serviceAddress];
            [mediaInfoLabel setStringValue:info];
            [mediaInfoLabel setHidden:NO];

            // Ensure mDNS announcement is active
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                ![mgr isServiceAnnounced:GSServiceTypeMedia]) {
                [mgr announceService:GSServiceTypeMedia port:8200 txtRecord:nil];
                NSDebugLog(@"SharingController: Re-announced Media Sharing service via mDNS");
            }
        } else {
            [mediaStatusLabel setStringValue:@"Off"];
            [mediaStatusLabel setTextColor:[NSColor grayColor]];
            [mediaInfoLabel setHidden:YES];

            // Ensure mDNS announcement is stopped
            GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
            if (mgr && [mgr isAvailable] &&
                [mgr isServiceAnnounced:GSServiceTypeMedia]) {
                [mgr unannounceService:GSServiceTypeMedia];
                NSDebugLog(@"SharingController: Unannounced Media Sharing service from mDNS");
            }
        }
    }
}

#pragma mark - UI Creation

- (NSView *)createMainView
{
    // Following AppearanceMetrics design philosophy:
    // - All spacing must be multiples of 4px (4, 8, 12, 16, 20, 24)
    // - Use spacing to group controls rather than group boxes
    // - Checkboxes spaced 20px baseline-to-baseline
    // - 24px margins from window edges
    // - 8px between control and its label
    // - 20px between control groups
    
    CGFloat viewHeight = 476;
    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 595, viewHeight)];
    [mainView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    CGFloat yPos = viewHeight - METRICS_CONTENT_TOP_MARGIN;  // Start from top with proper margin
    CGFloat leftMargin = METRICS_CONTENT_SIDE_MARGIN;  // 24px from window edge
    CGFloat width = 595 - (METRICS_CONTENT_SIDE_MARGIN * 2);  // 24px margins on both sides
    
    // Computer Name Section
    // Use emphasized bold font for section grouping (per metrics)
    NSTextField *computerNameTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, yPos, width, 17)];
    [computerNameTitle setStringValue:@"Computer Name"];
    [computerNameTitle setBezeled:NO];
    [computerNameTitle setDrawsBackground:NO];
    [computerNameTitle setEditable:NO];
    [computerNameTitle setSelectable:NO];
    [computerNameTitle setFont:[NSFont boldSystemFontOfSize:13]];  // METRICS_FONT_SYSTEM_BOLD_13
    [mainView addSubview:computerNameTitle];
    [computerNameTitle release];
    
    yPos -= METRICS_SPACE_16;  // 16px between title and first control
    
    // Hostname label and field
    NSTextField *hostnameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_TEXT_INPUT_FIELD_HEIGHT, 60, 17)];
    [hostnameLabel setStringValue:@"Name:"];
    [hostnameLabel setBezeled:NO];
    [hostnameLabel setDrawsBackground:NO];
    [hostnameLabel setEditable:NO];
    [hostnameLabel setSelectable:NO];
    [hostnameLabel setFont:[NSFont systemFontOfSize:13]];  // METRICS_FONT_SYSTEM_REGULAR_13
    [mainView addSubview:hostnameLabel];
    [hostnameLabel release];
    
    CGFloat fieldLeft = leftMargin + 60 + METRICS_SPACE_8;  // Label + 8px gap
    CGFloat buttonWidth = MAX(METRICS_BUTTON_MIN_WIDTH, 75.0);  // Ensure minimum width
    CGFloat fieldWidth = width - 60 - METRICS_SPACE_8 - buttonWidth - METRICS_SPACE_12;  // Space for button + 12px gap
    
    hostnameField = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldLeft, yPos - METRICS_TEXT_INPUT_FIELD_HEIGHT, fieldWidth, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
    [hostnameField setStringValue:@""];
    [hostnameField setFont:[NSFont systemFontOfSize:13]];  // METRICS_FONT_SYSTEM_REGULAR_13
    [hostnameField setTarget:self];
    [hostnameField setAction:@selector(applyHostname:)];
    [mainView addSubview:hostnameField];
    
    applyHostnameButton = [[NSButton alloc] initWithFrame:NSMakeRect(fieldLeft + fieldWidth + METRICS_SPACE_12, yPos - METRICS_BUTTON_HEIGHT - 1, buttonWidth, METRICS_BUTTON_HEIGHT)];
    [applyHostnameButton setTitle:@"Apply"];
    [applyHostnameButton setTarget:self];
    [applyHostnameButton setAction:@selector(applyHostname:)];
    [applyHostnameButton setBezelStyle:NSRoundedBezelStyle];
    [applyHostnameButton setFont:[NSFont systemFontOfSize:13]];  // METRICS_FONT_SYSTEM_REGULAR_13
    [applyHostnameButton setEnabled:NO];
    [mainView addSubview:applyHostnameButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hostnameDidChange:)
                                                 name:NSControlTextDidChangeNotification
                                               object:hostnameField];

    yPos -= METRICS_TEXT_INPUT_FIELD_HEIGHT + METRICS_SPACE_8;  // Move below field + 8px gap
    
    hostnameStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldLeft, yPos, fieldWidth, 17)];
    [hostnameStatusLabel setStringValue:@""];
    [hostnameStatusLabel setBezeled:NO];
    [hostnameStatusLabel setDrawsBackground:NO];
    [hostnameStatusLabel setEditable:NO];
    [hostnameStatusLabel setSelectable:NO];
    [hostnameStatusLabel setFont:[NSFont systemFontOfSize:11]];  // METRICS_FONT_SYSTEM_REGULAR_11
    [mainView addSubview:hostnameStatusLabel];
    
    yPos -= 17 + METRICS_SPACE_20;  // 20px gap between control groups
    
    // Services Section - using spacing-based grouping, no box
    NSTextField *servicesTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, yPos, width, 17)];
    [servicesTitle setStringValue:@"Services"];
    [servicesTitle setBezeled:NO];
    [servicesTitle setDrawsBackground:NO];
    [servicesTitle setEditable:NO];
    [servicesTitle setSelectable:NO];
    [servicesTitle setFont:[NSFont boldSystemFontOfSize:13]];  // METRICS_FONT_SYSTEM_BOLD_13
    [mainView addSubview:servicesTitle];
    [servicesTitle release];
    
    yPos -= METRICS_SPACE_16;  // 16px between title and first control
    
    // Each service row: checkbox + info label + spacing to next row
    CGFloat serviceRowHeight = METRICS_RADIO_BUTTON_SIZE + 17 + METRICS_SPACE_8;  // 43px per row
    
    // SSH Service
    sshCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 200, METRICS_RADIO_BUTTON_SIZE)];
    [sshCheckbox setTitle:@"Remote Login (SSH)"];
    [sshCheckbox setButtonType:NSSwitchButton];
    [sshCheckbox setTarget:self];
    [sshCheckbox setAction:@selector(toggleSSH:)];
    [sshCheckbox setFont:[NSFont systemFontOfSize:13]];  // METRICS_FONT_SYSTEM_REGULAR_13
    [mainView addSubview:sshCheckbox];
    
    sshStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 200 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [sshStatusLabel setStringValue:@"Off"];
    [sshStatusLabel setBezeled:NO];
    [sshStatusLabel setDrawsBackground:NO];
    [sshStatusLabel setEditable:NO];
    [sshStatusLabel setSelectable:NO];
    [sshStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];  // METRICS_FONT_SYSTEM_BOLD_13
    [sshStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:sshStatusLabel];
    
    sshInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [sshInfoLabel setStringValue:@""];
    [sshInfoLabel setBezeled:NO];
    [sshInfoLabel setDrawsBackground:NO];
    [sshInfoLabel setEditable:NO];
    [sshInfoLabel setSelectable:YES];
    [sshInfoLabel setFont:[NSFont systemFontOfSize:11]];  // METRICS_FONT_SYSTEM_REGULAR_11 for info text
    [sshInfoLabel setTextColor:[NSColor darkGrayColor]];
    [sshInfoLabel setHidden:YES];
    [mainView addSubview:sshInfoLabel];
    
    yPos -= serviceRowHeight;  // Move to next service row
    
    // SFTP Service
    sftpCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 200, METRICS_RADIO_BUTTON_SIZE)];
    [sftpCheckbox setTitle:@"File Transfer (SFTP)"];
    [sftpCheckbox setButtonType:NSSwitchButton];
    [sftpCheckbox setTarget:self];
    [sftpCheckbox setAction:@selector(toggleSFTP:)];
    [sftpCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:sftpCheckbox];
    
    sftpStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 200 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [sftpStatusLabel setStringValue:@"Off"];
    [sftpStatusLabel setBezeled:NO];
    [sftpStatusLabel setDrawsBackground:NO];
    [sftpStatusLabel setEditable:NO];
    [sftpStatusLabel setSelectable:NO];
    [sftpStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [sftpStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:sftpStatusLabel];
    
    sftpInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [sftpInfoLabel setStringValue:@""];
    [sftpInfoLabel setBezeled:NO];
    [sftpInfoLabel setDrawsBackground:NO];
    [sftpInfoLabel setEditable:NO];
    [sftpInfoLabel setSelectable:YES];
    [sftpInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [sftpInfoLabel setTextColor:[NSColor darkGrayColor]];
    [sftpInfoLabel setHidden:YES];
    [mainView addSubview:sftpInfoLabel];
    
    yPos -= serviceRowHeight;  // Move to next service row
    
    // AFP Service
    afpCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 230, METRICS_RADIO_BUTTON_SIZE)];
    [afpCheckbox setTitle:@"Apple File Sharing (AFP)"];
    [afpCheckbox setButtonType:NSSwitchButton];
    [afpCheckbox setTarget:self];
    [afpCheckbox setAction:@selector(toggleAFP:)];
    [afpCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:afpCheckbox];
    
    afpStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 230 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [afpStatusLabel setStringValue:@"Off"];
    [afpStatusLabel setBezeled:NO];
    [afpStatusLabel setDrawsBackground:NO];
    [afpStatusLabel setEditable:NO];
    [afpStatusLabel setSelectable:NO];
    [afpStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [afpStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:afpStatusLabel];
    
    afpInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [afpInfoLabel setStringValue:@""];
    [afpInfoLabel setBezeled:NO];
    [afpInfoLabel setDrawsBackground:NO];
    [afpInfoLabel setEditable:NO];
    [afpInfoLabel setSelectable:YES];
    [afpInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [afpInfoLabel setTextColor:[NSColor darkGrayColor]];
    [afpInfoLabel setHidden:YES];
    [mainView addSubview:afpInfoLabel];
    
    yPos -= serviceRowHeight;  // Move to next service row
    
    // SMB/Samba Service
    smbCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 250, METRICS_RADIO_BUTTON_SIZE)];
    [smbCheckbox setTitle:@"Windows File Sharing (SMB)"];
    [smbCheckbox setButtonType:NSSwitchButton];
    [smbCheckbox setTarget:self];
    [smbCheckbox setAction:@selector(toggleSMB:)];
    [smbCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:smbCheckbox];
    
    smbStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 250 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [smbStatusLabel setStringValue:@"Off"];
    [smbStatusLabel setBezeled:NO];
    [smbStatusLabel setDrawsBackground:NO];
    [smbStatusLabel setEditable:NO];
    [smbStatusLabel setSelectable:NO];
    [smbStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [smbStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:smbStatusLabel];
    
    smbInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [smbInfoLabel setStringValue:@""];
    [smbInfoLabel setBezeled:NO];
    [smbInfoLabel setDrawsBackground:NO];
    [smbInfoLabel setEditable:NO];
    [smbInfoLabel setSelectable:YES];
    [smbInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [smbInfoLabel setTextColor:[NSColor darkGrayColor]];
    [smbInfoLabel setHidden:YES];
    [mainView addSubview:smbInfoLabel];
    
    yPos -= serviceRowHeight;  // Move to next service row
    
    // VNC Service
    vncCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 200, METRICS_RADIO_BUTTON_SIZE)];
    [vncCheckbox setTitle:@"Screen Sharing (VNC)"];
    [vncCheckbox setButtonType:NSSwitchButton];
    [vncCheckbox setTarget:self];
    [vncCheckbox setAction:@selector(toggleVNC:)];
    [vncCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:vncCheckbox];
    
    vncStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 200 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [vncStatusLabel setStringValue:@"Off"];
    [vncStatusLabel setBezeled:NO];
    [vncStatusLabel setDrawsBackground:NO];
    [vncStatusLabel setEditable:NO];
    [vncStatusLabel setSelectable:NO];
    [vncStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [vncStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:vncStatusLabel];
    
    vncInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [vncInfoLabel setStringValue:@""];
    [vncInfoLabel setBezeled:NO];
    [vncInfoLabel setDrawsBackground:NO];
    [vncInfoLabel setEditable:NO];
    [vncInfoLabel setSelectable:YES];
    [vncInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [vncInfoLabel setTextColor:[NSColor darkGrayColor]];
    [vncInfoLabel setHidden:YES];
    [mainView addSubview:vncInfoLabel];
    
    yPos -= serviceRowHeight;  // Move to next service row

    // Web Server (nginx) Service
    webCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 200, METRICS_RADIO_BUTTON_SIZE)];
    [webCheckbox setTitle:@"Web Server (nginx)"];
    [webCheckbox setButtonType:NSSwitchButton];
    [webCheckbox setTarget:self];
    [webCheckbox setAction:@selector(toggleWeb:)];
    [webCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:webCheckbox];

    webStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 200 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [webStatusLabel setStringValue:@"Off"];
    [webStatusLabel setBezeled:NO];
    [webStatusLabel setDrawsBackground:NO];
    [webStatusLabel setEditable:NO];
    [webStatusLabel setSelectable:NO];
    [webStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [webStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:webStatusLabel];

    webInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [webInfoLabel setStringValue:@""];
    [webInfoLabel setBezeled:NO];
    [webInfoLabel setDrawsBackground:NO];
    [webInfoLabel setEditable:NO];
    [webInfoLabel setSelectable:YES];
    [webInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [webInfoLabel setTextColor:[NSColor darkGrayColor]];
    [webInfoLabel setHidden:YES];
    [mainView addSubview:webInfoLabel];

    yPos -= serviceRowHeight;  // Move to next service row

    // Media Sharing (MiniDLNA) Service
    mediaCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, yPos - METRICS_RADIO_BUTTON_SIZE, 230, METRICS_RADIO_BUTTON_SIZE)];
    [mediaCheckbox setTitle:@"Media Sharing (MiniDLNA)"];
    [mediaCheckbox setButtonType:NSSwitchButton];
    [mediaCheckbox setTarget:self];
    [mediaCheckbox setAction:@selector(toggleMedia:)];
    [mediaCheckbox setFont:[NSFont systemFontOfSize:13]];
    [mainView addSubview:mediaCheckbox];

    mediaStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + 230 + METRICS_SPACE_8, yPos - 17, 60, 17)];
    [mediaStatusLabel setStringValue:@"Off"];
    [mediaStatusLabel setBezeled:NO];
    [mediaStatusLabel setDrawsBackground:NO];
    [mediaStatusLabel setEditable:NO];
    [mediaStatusLabel setSelectable:NO];
    [mediaStatusLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [mediaStatusLabel setTextColor:[NSColor grayColor]];
    [mainView addSubview:mediaStatusLabel];

    mediaInfoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin + METRICS_SPACE_16, yPos - METRICS_RADIO_BUTTON_SIZE - 17, width - METRICS_SPACE_16, 17)];
    [mediaInfoLabel setStringValue:@""];
    [mediaInfoLabel setBezeled:NO];
    [mediaInfoLabel setDrawsBackground:NO];
    [mediaInfoLabel setEditable:NO];
    [mediaInfoLabel setSelectable:YES];
    [mediaInfoLabel setFont:[NSFont systemFontOfSize:11]];
    [mediaInfoLabel setTextColor:[NSColor darkGrayColor]];
    [mediaInfoLabel setHidden:YES];
    [mainView addSubview:mediaInfoLabel];

    yPos -= 17 + METRICS_SPACE_20;  // 20px gap between control groups
    
    // mDNS Status Section
    mdnsStatusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(leftMargin, METRICS_CONTENT_BOTTOM_MARGIN, width, 40)];
    [mdnsStatusLabel setBezeled:NO];
    [mdnsStatusLabel setDrawsBackground:NO];
    [mdnsStatusLabel setEditable:NO];
    [mdnsStatusLabel setSelectable:NO];
    [mdnsStatusLabel setFont:[NSFont systemFontOfSize:11]];  // METRICS_FONT_SYSTEM_REGULAR_11
    [mdnsStatusLabel setTextColor:[NSColor darkGrayColor]];
    
    GSServiceDiscoveryManager *mgr = [self ensureServiceDiscoveryManager];
    if (mgr && [mgr isAvailable]) {
        NSString *statusText = [NSString stringWithFormat:@"Service Discovery: Available (%@)\nEnabled services will be announced on the local network.",
                               [mgr backendName]];
        [mdnsStatusLabel setStringValue:statusText];
    } else {
        [mdnsStatusLabel setStringValue:@"Service Discovery: Not available\nInstall avahi-daemon or mDNSResponder for automatic network service announcement."];
    }
    [mainView addSubview:mdnsStatusLabel];
    
    // Don't call refreshStatus here - it will be called in mainViewDidLoad
    // when the pane is actually displayed
    
    return [mainView autorelease];
}

@end

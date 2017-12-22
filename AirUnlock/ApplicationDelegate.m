#import "ApplicationDelegate.h"
#import <ServiceManagement/ServiceManagement.h>
#import <Security/Authorization.h>
#import <CoreFoundation/CFArray.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLibDefs.h>
#import <IOKit/pwr_mgt/IOPMKeys.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <CoreBluetooth/CoreBluetooth.h>

#import <Availability.h>



@interface ApplicationDelegate ()

@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableService *service;

@property (nonatomic, strong) MenubarController *menubarController;
@property (nonatomic, strong, readonly) PanelController *panelController;

@property Boolean bScreenLocked;

@end


@implementation ApplicationDelegate

@synthesize panelController = _panelController;
@synthesize menubarController = _menubarController;

#pragma mark -

- (void)dealloc
{
    [_panelController removeObserver:self forKeyPath:@"hasActivePanel"];
}

#pragma mark -

void *kContextActivePanel = &kContextActivePanel;

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kContextActivePanel) {
        self.menubarController.hasActiveIcon = self.panelController.hasActivePanel;
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    
    // inital controler and BLE peripheral manager
    self.menubarController = [[MenubarController alloc] init];
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    
    // user's default keychain
    self.panelController.keychain = NULL;
    // inital keychain information
    self.panelController.keyChain_accountName = @"AirUnlock";
    self.panelController.keyChain_serviceName = @"AirUnlock";
    self.panelController.keyChain_passwordData = @"AirUnlock";
    
    // check keychain access permission
        void *password = NULL;
        UInt32 nLength;
        OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                         (UInt32)[self.panelController.keyChain_serviceName lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                         self.panelController.keyChain_serviceName.UTF8String,
                                                         (UInt32)[self.panelController.keyChain_accountName lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                         self.panelController.keyChain_accountName.UTF8String,
                                                         &nLength,&password,
                                                         NULL);
        if(status == noErr) {
            self.panelController.keyChain_passwordData = [[NSString alloc] initWithBytes:password length:nLength encoding:NSUTF8StringEncoding];
        }
        else if(status == errSecAuthFailed)
        {
            
            [NSApp activateIgnoringOtherApps:YES];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"We need permission to store your password in system key chain."];
            [alert addButtonWithTitle:@"Ok"];
            [alert addButtonWithTitle:@"Exit"];
            [alert setAlertStyle:NSCriticalAlertStyle];
            [alert setIcon:[NSImage imageNamed:@"mbp-un"]];
            NSInteger button = [alert runModal];
            if (button != NSAlertFirstButtonReturn) {
                [NSApp terminate:self];
            }
        }
        else if(status == errSecItemNotFound){
            [NSApp activateIgnoringOtherApps:YES];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"You have not set a password to unlock."];
            [alert addButtonWithTitle:@"Set password"];
            [alert addButtonWithTitle:@"Later"];
            [alert setAlertStyle:NSCriticalAlertStyle];
            [alert setIcon:[NSImage imageNamed:@"mbp-un"]];
            NSInteger button = [alert runModal];
            if (button == NSAlertFirstButtonReturn) {
                [self.panelController showUpdatePasswordDialog];
            }
        }
        else{
            NSLog(@"%@", (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL)); // User canceled the operation.
        }
    if (password) SecKeychainItemFreeContent(NULL, password);  // Free memory
    
    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(screenLocked)
                   name:@"com.apple.screenIsLocked"
                 object:nil
     ];
    [center addObserver:self
               selector:@selector(screenUnlocked)
                   name:@"com.apple.screenIsUnlocked"
                 object:nil
     ];
    

    



    if(kBluetoothHCIPowerStateOFF == [[IOBluetoothHostController defaultController] powerState]){
        //show up turn on bt alert
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"Bluetooth Hardware is Off"];
        [alert setInformativeText:@"In order to use AirUnlock, the Bluetooth hardware must be on."];
        [alert addButtonWithTitle:@"Turn Bluetooth On"];
        [alert addButtonWithTitle:@"Leave Bluetooth Off"];
        [alert setAlertStyle:NSWarningAlertStyle];
        //[alert setShowsSuppressionButton:YES];
        NSModalResponse button = [alert runModal];
        
        if (button == NSAlertFirstButtonReturn) {
            IOBluetoothPreferenceSetControllerPowerState(1);
            //[[(id)NSClassFromString(@"IOBluetoothPreferences") performSelector:NSSelectorFromString(@"sharedPreferences") withObject:nil] performSelector:NSSelectorFromString(@"_setPoweredOn:") withObject:[NSNumber numberWithBool:YES]];
            //https://github.com/onmyway133/Runtime-Headers/blob/master/macOS/10.12/IOBluetooth.framework/IOBluetoothPreferences.h
        }
    }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Explicitly remove the icon from the menu bar
    self.menubarController = nil;
    return NSTerminateNow;
}

#pragma mark - Actions

- (IBAction)togglePanel:(id)sender
{
    
    self.menubarController.hasActiveIcon = !self.menubarController.hasActiveIcon;
    self.panelController.hasActivePanel = self.menubarController.hasActiveIcon;
}

#pragma mark - Public accessors

- (PanelController *)panelController
{
    if (_panelController == nil) {
        _panelController = [[PanelController alloc] initWithDelegate:self];
        [_panelController addObserver:self forKeyPath:@"hasActivePanel" options:0 context:kContextActivePanel];
    }
    return _panelController;
}

#pragma mark - PanelControllerDelegate

- (StatusItemView *)statusItemViewForPanelController:(PanelController *)controller
{
    return self.menubarController.statusItemView;
}


- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    NSLog(@"peripheralManagerDidUpdateState: %d", (int)peripheral.state);
    
    if (CBPeripheralManagerStatePoweredOn == peripheral.state) {
        //當藍牙打開
        // inital unlock setting for generate QR code
        // QR code encode content is BT's MAC Address, unlock Keyword, lock keyword
        // for exampele "AA-AA-AA-AA-AA-AA,unlock!,lock!"
        // we need to save these to avoid user scan qrcode when app relaunch
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        const NSString *btAddress = [[IOBluetoothHostController defaultController] addressAsString];
        
        NSDictionary *appDefaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                                     btAddress, @"ADDRESS",
                                     @"lock", @"LOCK",
                                     @"unlock",@"UNLOCK",
                                     nil];
        [defaults registerDefaults:appDefaults];
        

        [peripheral startAdvertising:@{
                                       CBAdvertisementDataLocalNameKey: @"Air Unlock",
                                       CBAdvertisementDataServiceUUIDsKey: @[[CBUUID UUIDWithString:@"BD0F6577-4A38-4D71-AF1B-4E8F57708080"]]
                                       }];
        CBMutableCharacteristic *characteristic = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:@"A6282AC7-7FCA-4852-A2E6-1D69121FD44A"] properties:CBCharacteristicPropertyWrite value:nil permissions:CBAttributePermissionsWriteable];
        
        CBMutableService *includedService = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:@"A5B288C3-FC55-491F-AF38-27D2F7D7BF25"] primary:YES];
        
        includedService.characteristics= @[characteristic];
        
        [self.peripheralManager addService:includedService];
        
    }else {
        // 當藍芽被關地的時候或其他狀態
        
        [peripheral stopAdvertising];
        [peripheral removeAllServices];
    }
    
    
}


- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if(error!=nil)
        NSLog(@"peripheralManagerDidStartAdvertising: %@", error);
    else
        NSLog(@"peripheralManagerDidStartAdvertising:");
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(CBService *)service error:(NSError *)error
{
    if(error!=nil)
        NSLog(@"peripheralManagerDidAddService: %@ %@", service, error);
    else
        NSLog(@"peripheralManagerDidAddService: %@", service);

}
- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveWriteRequests:(NSArray *)requests{
    NSLog(@"didReceiveWriteRequests");
    CBATTRequest *request = requests[0];
    
    
    if (request.characteristic.properties & CBCharacteristicPropertyWrite) {
        //並沒有要真正改動值...只是拿來看一下符不符合解鎖的暗碼
        //CBMutableCharacteristic *c =(CBMutableCharacteristic *)request.characteristic;
        //c.value = request.value;
        
        
        
        NSString *conetnt = [[NSString alloc] initWithData:request.value encoding:NSUTF8StringEncoding];
        NSString* lockKeyword = [[NSUserDefaults standardUserDefaults] stringForKey:@"LOCK"];
        NSString* unlockKeyword = [[NSUserDefaults standardUserDefaults] stringForKey:@"UNLOCK"];
        if([conetnt isEqualToString:lockKeyword] && !self.bScreenLocked){
            NSLog(@"lock screen!");
            SACLockScreenImmediate();
            //10.10-10.12
            //NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/Utilities/Keychain Access.app/Contents/Resources/Keychain.menu"];
            //Class principalClass = [bundle principalClass];
            //id instance = [[principalClass alloc] init];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            //[instance performSelector:NSSelectorFromString(@"_lockScreenMenuHit:") withObject:nil];
#pragma clang diagnostic pop
            sleep(3);
        }
        else if ([conetnt isEqualToString:unlockKeyword] && self.bScreenLocked){
            NSLog(@"unlock screen!");
            //wake up
            //need privileges (need to create helper)
            // sample code :https://developer.apple.com/library/mac/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html#//apple_ref/doc/uid/DTS40013768-Intro-DontLinkElementID_2
//            IOPMAssertionID assertionID;
//            IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
//            CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
//            CFDateRef wakeFromSleepAt = CFDateCreate(NULL, currentTime + 60);
//            IOPMSchedulePowerEvent(wakeFromSleepAt,
//                                    NULL,
//                                    CFSTR(kIOPMAutoWake));
            
                
            // 10.10-10.12 can work for wake up with out privileges..
            IOPMAssertionID assertionID;
            IOPMAssertionDeclareUserActivity(CFSTR("AirUnlock"), kIOPMUserActiveLocal, &assertionID);
            sleep(1);
            NSString *unlockScript = [NSString stringWithFormat:@"tell application \"System Events\" \nkeystroke \"%@\" \nkeystroke return \nend tell", self.panelController.keyChain_passwordData];
            NSAppleScript *unlocker = [[NSAppleScript alloc] initWithSource:unlockScript];
            //NSLog(unlockScript);
            [unlocker executeAndReturnError:nil];
            IOPMAssertionRelease(assertionID);
        }
        [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
    }else{
        [peripheral respondToRequest:request withResult:CBATTErrorWriteNotPermitted];
    }
}

- (void)screenLocked{
    self.bScreenLocked = true;
    NSLog(@"Screen is locked!");
}
- (void)screenUnlocked
{
    self.bScreenLocked = false;
    NSLog(@"Screen is unlocked!");
}

@end




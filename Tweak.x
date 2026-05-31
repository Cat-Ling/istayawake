#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <netdb.h>

// Private APIs for CPPowerAssertion
@interface CPPowerAssertion : NSObject
- (id)initWithIdentifier:(NSString *)identifier timeout:(double)timeout;
- (void)take;
- (void)releaseAssertion;
@end

// Power Management APIs
typedef uint32_t IOPMAssertionLevel;
typedef uint32_t IOPMAssertionID;
typedef int32_t IOReturn;

#define kIOPMAssertionLevelOn 255

static IOPMAssertionID keepAwakeAssertionID = 0;
static id cppAssertion = nil;
static NSTimer *keepAliveTimer = nil;

void startWiFiKeepAliveTimer() {
    if (keepAliveTimer) return;
    
    NSLog(@"[istayawake] Starting repeating background Wi-Fi keep-alive timer.");
    keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            // Perform a lightweight network activity to keep the Wi-Fi chip awake.
            // 1. Resolve localhost to activate network daemon loops.
            getaddrinfo("localhost", NULL, NULL, NULL);
            
            // 2. Send a tiny UDP packet to a broadcast discard port (Port 9).
            // This forces the physical Wi-Fi hardware to transmit a packet, preventing power-saving sleep.
            int sock = socket(AF_INET, SOCK_DGRAM, 0);
            if (sock >= 0) {
                // Set broadcast option
                int broadcastEnable = 1;
                setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));
                
                struct sockaddr_in addr;
                memset(&addr, 0, sizeof(addr));
                addr.sin_family = AF_INET;
                addr.sin_port = htons(9); // Discard port
                addr.sin_addr.s_addr = inet_addr("255.255.255.255"); // Broadcast to local network
                
                const char *msg = "keepalive";
                sendto(sock, msg, strlen(msg), 0, (struct sockaddr *)&addr, sizeof(addr));
                close(sock);
            }
        });
    }];
    
    // Ensure the timer runs in all run loop modes including common modes
    [[NSRunLoop mainRunLoop] addTimer:keepAliveTimer forMode:NSRunLoopCommonModes];
}

void initializeKeepAlive() {
    NSLog(@"[istayawake] Initializing background keep-awake mechanisms.");
    
    // 1. Create a power assertion using IOKit
    void *ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (ioKit) {
        IOReturn (*assertionCreate)(CFStringRef, IOPMAssertionLevel, CFStringRef, IOPMAssertionID *) =
            (IOReturn (*)(CFStringRef, IOPMAssertionLevel, CFStringRef, IOPMAssertionID *))dlsym(ioKit, "IOPMAssertionCreateWithName");
        
        if (assertionCreate) {
            CFStringRef assertionType = CFSTR("PreventUserIdleSystemSleep");
            CFStringRef assertionName = CFSTR("KeepSSHAndWiFiAliveTweak");
            
            IOReturn result = assertionCreate(assertionType, kIOPMAssertionLevelOn, assertionName, &keepAwakeAssertionID);
            if (result == 0) {
                NSLog(@"[istayawake] IOPMAssertion successfully created with ID: %d", keepAwakeAssertionID);
            } else {
                NSLog(@"[istayawake] Failed to create IOPMAssertion: %d", result);
            }
        } else {
            NSLog(@"[istayawake] Failed to locate IOPMAssertionCreateWithName symbol.");
        }
        dlclose(ioKit);
    } else {
        NSLog(@"[istayawake] Failed to load IOKit.framework.");
    }
    
    // 2. Create a secondary power assertion using AppSupport's CPPowerAssertion
    Class CPPowerAssertionClass = NSClassFromString(@"CPPowerAssertion");
    if (CPPowerAssertionClass) {
        cppAssertion = [[CPPowerAssertionClass alloc] initWithIdentifier:@"com.yourname.istayawake" timeout:0.0];
        if (cppAssertion) {
            [cppAssertion take];
            NSLog(@"[istayawake] CPPowerAssertion taken successfully.");
        } else {
            NSLog(@"[istayawake] Failed to initialize CPPowerAssertion.");
        }
    } else {
        NSLog(@"[istayawake] CPPowerAssertion class not found.");
    }
    
    // 3. Start the Wi-Fi hardware keep-alive timer
    startWiFiKeepAliveTimer();
}

%ctor {
    @autoreleasepool {
        // Ensure we are indeed in SpringBoard
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            NSLog(@"[istayawake] Tweak loaded inside SpringBoard process.");
            
            // Wait for system to finish booting/initializing before taking assertions
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                initializeKeepAlive();
            });
        }
    }
}

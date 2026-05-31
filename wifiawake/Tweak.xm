/*
 * wifiawake — Tweak.xm
 *
 * Prevents iOS from sleeping the WiFi radio by:
 *   1. Blocking -allowIdleSleep on the correct SpringBoard class for the
 *      running iOS version (SBIdleSleepController on iOS 13-15,
 *      SBAwayController on iOS 9-12, SBBacklightController as a last resort).
 *   2. Creating a kernel-level IOPMAssertion of type "NetworkClientActive"
 *      so the WiFi chip never enters PSM even if the hook misses a path.
 *
 * Target: rootless Dopamine, iOS 15, iPhone 6s Plus (arm64 / arm64e)
 * Author: Cat-Ling
 */

#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <dlfcn.h>

// ── IOKit power assertion (private, but accessible as root in jailbreak) ────
typedef uint32_t IOPMAssertionID;
typedef int      IOReturn;
#define kIOReturnSuccess        0
#define kIOPMNullAssertionID    0
#define kIOPMAssertionLevelOn   255

static IOPMAssertionID gNetworkAssertionID = kIOPMNullAssertionID;
static IOPMAssertionID gNoSleepAssertionID = kIOPMNullAssertionID;

typedef IOReturn (*IOPMAssertionCreateWithNameFn)(
    CFStringRef type, uint32_t level, CFStringRef name, IOPMAssertionID *outID);

static void createPowerAssertions(void) {
    void *iokit = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_NOLOAD);
    if (!iokit)
        iokit = dlopen(
            "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) return;

    IOPMAssertionCreateWithNameFn fn =
        (IOPMAssertionCreateWithNameFn)dlsym(iokit, "IOPMAssertionCreateWithName");
    if (!fn) { dlclose(iokit); return; }

    // Assert that a network client is active → keeps WiFi radio out of PSM
    if (gNetworkAssertionID == kIOPMNullAssertionID) {
        IOReturn r = fn(CFSTR("NetworkClientActive"), kIOPMAssertionLevelOn,
                        CFSTR("wifiawake: SSH keep-alive"), &gNetworkAssertionID);
        if (r != kIOReturnSuccess) gNetworkAssertionID = kIOPMNullAssertionID;
    }

    // Belt-and-suspenders: also assert no idle system sleep
    if (gNoSleepAssertionID == kIOPMNullAssertionID) {
        IOReturn r = fn(CFSTR("NoIdleSleep"), kIOPMAssertionLevelOn,
                        CFSTR("wifiawake: prevent idle sleep"), &gNoSleepAssertionID);
        if (r != kIOReturnSuccess) gNoSleepAssertionID = kIOPMNullAssertionID;
    }

    dlclose(iokit);
}

// ── Hook group: iOS 13-15 ────────────────────────────────────────────────────
%group Modern  // SBIdleSleepController (iOS 13+)

%hook SBIdleSleepController

// Block the call that actually permits the system to sleep
- (void)allowIdleSleep {
    // intentionally empty — never %orig
}

// Block the assertion-invalidation path (secondary sleep trigger on iOS 14-15)
- (void)_invalidateIdleSleepAssertions {
}

// Report idle sleep as disabled so callers stop trying
- (BOOL)idleSleepEnabled {
    return NO;
}

%end

%end  // group Modern

// ── Hook group: iOS 9-12 ─────────────────────────────────────────────────────
%group Legacy  // SBAwayController

%hook SBAwayController

- (void)allowIdleSleep {
}

- (void)_startIdleSleepTimer {
    // Never start the countdown
}

%end

%end  // group Legacy

// ── Hook group: last-resort fallback ─────────────────────────────────────────
%group Fallback  // SBBacklightController

%hook SBBacklightController

- (void)allowIdleSleep {
}

%end

%end  // group Fallback

// ── Constructor: pick the right group and create power assertions ─────────────
%ctor {
    @autoreleasepool {
        if (objc_getClass("SBIdleSleepController")) {
            %init(Modern);
        } else if (objc_getClass("SBAwayController")) {
            %init(Legacy);
        } else {
            %init(Fallback);
        }

        // Create IOPMAssertions on the main run-loop after SpringBoard is ready
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{ createPowerAssertions(); });
    }
}

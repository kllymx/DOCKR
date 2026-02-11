#import "DockLockController.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

static NSString *const kDefaultsEnabledKey = @"dockr.enabled";
static NSString *const kDefaultsDisplayUUIDKey = @"dockr.selectedDisplayUUID";

typedef NS_ENUM(NSInteger, DockOrientation) {
  DockOrientationBottom,
  DockOrientationLeft,
  DockOrientationRight,
};

static CGEventRef DockLockEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

@interface DockLockController ()
@property (nonatomic, assign) BOOL lockEnabled;
@property (nonatomic, copy, nullable) NSString *selectedDisplayUUIDValue;
@property (nonatomic, strong) NSTimer *healthTimer;
@property (nonatomic, assign) BOOL isRelocking;
@property (nonatomic, assign) CFAbsoluteTime lastRelockAt;
@property (nonatomic, assign) CFMachPortRef eventTap;
@property (nonatomic, assign) CFRunLoopSourceRef eventTapRunLoopSource;
@end

@implementation DockLockController

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  self.lockEnabled = [defaults objectForKey:kDefaultsEnabledKey] ? [defaults boolForKey:kDefaultsEnabledKey] : YES;
  self.selectedDisplayUUIDValue = [defaults stringForKey:kDefaultsDisplayUUIDKey];
  self.lastRelockAt = 0;
  self.eventTap = NULL;
  self.eventTapRunLoopSource = NULL;

  [self ensureSelectedDisplayExists];
  [self startHealthTimer];
  [self observeSystemEvents];

  if (self.lockEnabled) {
    if (![self activateProtectionWithPrompt:NO]) {
      self.lockEnabled = NO;
      [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultsEnabledKey];
    }
  }

  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.healthTimer invalidate];
  [self stopEventTap];
}

#pragma mark - Public API

- (NSArray<NSDictionary *> *)availableDisplays {
  uint32_t displayCount = 0;
  CGGetActiveDisplayList(0, NULL, &displayCount);
  if (displayCount == 0) {
    return @[];
  }

  CGDirectDisplayID ids[displayCount];
  CGGetActiveDisplayList(displayCount, ids, &displayCount);

  NSMutableDictionary<NSNumber *, NSString *> *screenNames = [NSMutableDictionary dictionary];
  for (NSScreen *screen in [NSScreen screens]) {
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    if (screenNumber == nil) {
      continue;
    }

    NSString *name = @"Display";
    if (@available(macOS 10.15, *)) {
      name = screen.localizedName ?: @"Display";
    }
    screenNames[screenNumber] = name;
  }

  DockOrientation orientation = [self currentDockOrientation];
  NSMutableArray<NSDictionary *> *displays = [NSMutableArray array];
  for (uint32_t i = 0; i < displayCount; i++) {
    CGDirectDisplayID displayID = ids[i];
    NSString *uuid = [self uuidStringForDisplayID:displayID];
    if (uuid.length == 0) {
      continue;
    }

    CGRect bounds = CGDisplayBounds(displayID);
    BOOL isBuiltin = CGDisplayIsBuiltin(displayID);
    NSString *name = screenNames[@(displayID)] ?: [NSString stringWithFormat:@"Display %u", displayID];
    BOOL canHost = [self displayIDCanHostDockForOrientation:displayID orientation:orientation];

    NSDictionary *display = @{
      @"displayID": @(displayID),
      @"uuid": uuid,
      @"name": name,
      @"isBuiltin": @(isBuiltin),
      @"canHostCurrentOrientation": @(canHost),
      @"x": @(CGRectGetMinX(bounds)),
      @"y": @(CGRectGetMinY(bounds)),
      @"width": @(CGRectGetWidth(bounds)),
      @"height": @(CGRectGetHeight(bounds)),
    };
    [displays addObject:display];
  }

  [displays sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    BOOL lhsBuiltin = [lhs[@"isBuiltin"] boolValue];
    BOOL rhsBuiltin = [rhs[@"isBuiltin"] boolValue];
    if (lhsBuiltin != rhsBuiltin) {
      return lhsBuiltin ? NSOrderedDescending : NSOrderedAscending;
    }

    double lhsY = [lhs[@"y"] doubleValue];
    double rhsY = [rhs[@"y"] doubleValue];
    if (lhsY != rhsY) {
      return lhsY < rhsY ? NSOrderedAscending : NSOrderedDescending;
    }

    double lhsX = [lhs[@"x"] doubleValue];
    double rhsX = [rhs[@"x"] doubleValue];
    if (lhsX == rhsX) {
      return NSOrderedSame;
    }
    return lhsX < rhsX ? NSOrderedAscending : NSOrderedDescending;
  }];

  return displays;
}

- (nullable NSString *)selectedDisplayUUID {
  return self.selectedDisplayUUIDValue;
}

- (NSString *)selectedDisplayLabel {
  NSString *selectedUUID = self.selectedDisplayUUIDValue;
  if (selectedUUID.length == 0) {
    return @"No display selected";
  }

  for (NSDictionary *display in [self availableDisplays]) {
    if ([display[@"uuid"] isEqualToString:selectedUUID]) {
      NSString *name = display[@"name"];
      NSString *suffix = [display[@"isBuiltin"] boolValue] ? @" (Built-in)" : @" (External)";
      return [name stringByAppendingString:suffix];
    }
  }

  return @"Selected display disconnected";
}

- (NSString *)dockOrientationLabel {
  DockOrientation orientation = [self currentDockOrientation];
  switch (orientation) {
    case DockOrientationBottom:
      return @"bottom";
    case DockOrientationLeft:
      return @"left";
    case DockOrientationRight:
      return @"right";
  }
}

- (BOOL)isEnabled {
  return self.lockEnabled;
}

- (NSString *)statusLine {
  if (!self.lockEnabled) {
    return [NSString stringWithFormat:@"Lock off | %@", [self selectedDisplayLabel]];
  }

  if (![self isAccessibilityTrusted]) {
    return [NSString stringWithFormat:@"Lock on | %@ | accessibility required", [self selectedDisplayLabel]];
  }

  if (self.eventTap == NULL) {
    return [NSString stringWithFormat:@"Lock on | %@ | protection inactive", [self selectedDisplayLabel]];
  }

  if (![self selectedDisplayCanHostCurrentDockOrientation]) {
    return [NSString stringWithFormat:@"Lock on | %@ | not eligible for %@ dock", [self selectedDisplayLabel], [self dockOrientationLabel]];
  }

  CGDirectDisplayID dockDisplay = [self currentDockDisplayID];
  CGDirectDisplayID targetDisplay = [self targetDisplayID];

  NSString *dockStatus = @"dock unknown";
  if (dockDisplay != kCGNullDirectDisplay) {
    dockStatus = (dockDisplay == targetDisplay) ? @"on target" : @"off target";
  }

  return [NSString stringWithFormat:@"Lock on | %@ | %@", [self selectedDisplayLabel], dockStatus];
}

- (void)setEnabled:(BOOL)enabled {
  if (enabled) {
    if (![self activateProtectionWithPrompt:YES]) {
      self.lockEnabled = NO;
      [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultsEnabledKey];
      [self notifyStateChange];
      return;
    }

    self.lockEnabled = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDefaultsEnabledKey];
    [self relockNowWithReason:@"Enabled"];
    [self notifyStateChange];
    return;
  }

  self.lockEnabled = NO;
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultsEnabledKey];
  [self stopEventTap];
  [self notifyStateChange];
}

- (void)toggleEnabled {
  [self setEnabled:!self.lockEnabled];
}

- (void)selectDisplayUUID:(NSString *)displayUUID {
  if (displayUUID.length == 0) {
    return;
  }

  self.selectedDisplayUUIDValue = displayUUID;
  [[NSUserDefaults standardUserDefaults] setObject:displayUUID forKey:kDefaultsDisplayUUIDKey];

  if (self.lockEnabled) {
    [self relockNowWithReason:@"Display changed"];
  }

  [self notifyStateChange];
}

- (void)relockNowWithReason:(NSString *)reason {
  if (!self.lockEnabled || self.isRelocking) {
    return;
  }

  if (![self activateProtectionWithPrompt:NO]) {
    return;
  }

  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - self.lastRelockAt < 4.0) {
    return;
  }

  CGDirectDisplayID targetDisplay = [self targetDisplayID];
  if (targetDisplay == kCGNullDirectDisplay) {
    return;
  }

  DockOrientation orientation = [self currentDockOrientation];
  BOOL targetCanHost = [self displayIDCanHostDockForOrientation:targetDisplay orientation:orientation];
  if (!targetCanHost) {
    if ([reason isEqualToString:@"Manual relock"] || [reason isEqualToString:@"Display changed"]) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleInformational;
      alert.messageText = @"Display Not Eligible for Side Dock";
      alert.informativeText = [NSString stringWithFormat:@"With Dock on %@, macOS can only place it on displays touching the outer %@ edge. Choose an eligible display or switch Dock to bottom.", [self dockOrientationLabel], [self dockOrientationLabel]];
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
    }
    [self notifyStateChange];
    return;
  }

  CGDirectDisplayID dockDisplay = [self currentDockDisplayID];
  BOOL shouldTrustDetection = (orientation == DockOrientationBottom);
  BOOL forceRelock = [reason isEqualToString:@"Manual relock"] || [reason isEqualToString:@"Display changed"];
  if (!forceRelock && shouldTrustDetection && dockDisplay == targetDisplay) {
    return;
  }

  [self performDockRelockToDisplayID:targetDisplay];
  self.lastRelockAt = now;
  [self notifyStateChange];
}

#pragma mark - Monitoring

- (void)startHealthTimer {
  self.healthTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(handleHealthTimer:)
                                                    userInfo:nil
                                                     repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:self.healthTimer forMode:NSRunLoopCommonModes];
}

- (void)handleHealthTimer:(NSTimer *)timer {
  #pragma unused(timer)

  if (!self.lockEnabled) {
    return;
  }

  if (![self isAccessibilityTrusted]) {
    self.lockEnabled = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultsEnabledKey];
    [self stopEventTap];
    [self notifyStateChange];
    return;
  }

  if (self.eventTap == NULL || !CFMachPortIsValid(self.eventTap)) {
    [self stopEventTap];
    [self startEventTap];
    [self notifyStateChange];
  }
}

- (BOOL)activateProtectionWithPrompt:(BOOL)prompt {
  if (![self ensureAccessibilityPermissionWithPrompt:prompt]) {
    return NO;
  }

  if (self.eventTap == NULL) {
    return [self startEventTap];
  }

  if (!CFMachPortIsValid(self.eventTap)) {
    [self stopEventTap];
    return [self startEventTap];
  }

  return YES;
}

- (BOOL)ensureAccessibilityPermissionWithPrompt:(BOOL)prompt {
  if ([self isAccessibilityTrusted]) {
    return YES;
  }

  if (prompt) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Accessibility Required";
    alert.informativeText = @"DOCKR needs Accessibility access to prevent Dock moves on non-target displays. Grant access in System Settings > Privacy & Security > Accessibility, then re-enable lock.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  }

  return [self isAccessibilityTrusted];
}

- (BOOL)isAccessibilityTrusted {
  return AXIsProcessTrusted();
}

- (BOOL)startEventTap {
  if (self.eventTap != NULL) {
    return YES;
  }

  CGEventMask eventMask = CGEventMaskBit(kCGEventMouseMoved);

  self.eventTap = CGEventTapCreate(kCGSessionEventTap,
                                   kCGHeadInsertEventTap,
                                   kCGEventTapOptionDefault,
                                   eventMask,
                                   DockLockEventTapCallback,
                                   (__bridge void *)self);
  if (self.eventTap == NULL) {
    return NO;
  }

  self.eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
  if (self.eventTapRunLoopSource == NULL) {
    [self stopEventTap];
    return NO;
  }

  CFRunLoopAddSource(CFRunLoopGetMain(), self.eventTapRunLoopSource, kCFRunLoopCommonModes);
  CGEventTapEnable(self.eventTap, true);
  return YES;
}

- (void)stopEventTap {
  if (self.eventTap != NULL) {
    CGEventTapEnable(self.eventTap, false);
  }

  if (self.eventTapRunLoopSource != NULL) {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), self.eventTapRunLoopSource, kCFRunLoopCommonModes);
    CFRelease(self.eventTapRunLoopSource);
    self.eventTapRunLoopSource = NULL;
  }

  if (self.eventTap != NULL) {
    CFRelease(self.eventTap);
    self.eventTap = NULL;
  }
}

- (CGEventRef)handleEventTapWithProxy:(CGEventTapProxy)proxy type:(CGEventType)type event:(CGEventRef)event {
  #pragma unused(proxy)

  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
    if (self.eventTap != NULL) {
      CGEventTapEnable(self.eventTap, true);
    }
    return event;
  }

  if (type != kCGEventMouseMoved) {
    return event;
  }

  if (self.isRelocking) {
    int64_t marker = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
    if (marker == 0xD0C4A5C4) {
      return event;
    }
    return NULL;
  }

  CGPoint location = CGEventGetLocation(event);
  if ([self shouldBlockDockMovementAtPoint:location]) {
    return NULL;
  }

  return event;
}

- (BOOL)shouldBlockDockMovementAtPoint:(CGPoint)point {
  if (!self.lockEnabled) {
    return NO;
  }

  NSArray<NSDictionary *> *displays = [self availableDisplays];
  if (displays.count <= 1) {
    return NO;
  }

  CGDirectDisplayID targetDisplay = [self targetDisplayID];
  if (targetDisplay == kCGNullDirectDisplay) {
    return NO;
  }

  DockOrientation orientation = [self currentDockOrientation];
  if (![self displayIDCanHostDockForOrientation:targetDisplay orientation:orientation]) {
    return NO;
  }

  for (NSDictionary *display in displays) {
    CGDirectDisplayID displayID = (CGDirectDisplayID)[display[@"displayID"] unsignedIntValue];
    if (displayID == targetDisplay) {
      continue;
    }

    CGRect frame = CGRectMake([display[@"x"] doubleValue],
                              [display[@"y"] doubleValue],
                              [display[@"width"] doubleValue],
                              [display[@"height"] doubleValue]);
    CGRect triggerZone = [self dockTriggerZoneForBounds:frame orientation:orientation];
    if (CGRectContainsPoint(triggerZone, point)) {
      return YES;
    }
  }

  return NO;
}

#pragma mark - System notifications

- (void)observeSystemEvents {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self
             selector:@selector(handleSystemEvent:)
                 name:NSApplicationDidChangeScreenParametersNotification
               object:nil];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                          selector:@selector(handleSystemEvent:)
                                                              name:NSWorkspaceDidWakeNotification
                                                            object:nil];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                          selector:@selector(handleSystemEvent:)
                                                              name:NSWorkspaceActiveSpaceDidChangeNotification
                                                            object:nil];
}

- (void)handleSystemEvent:(NSNotification *)notification {
  #pragma unused(notification)

  [self ensureSelectedDisplayExists];

  if (!self.lockEnabled) {
    [self notifyStateChange];
    return;
  }

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self relockNowWithReason:@"System event"];
  });
}

#pragma mark - Core relock logic

- (void)performDockRelockToDisplayID:(CGDirectDisplayID)displayID {
  CGRect bounds = CGDisplayBounds(displayID);
  if (CGRectIsEmpty(bounds)) {
    return;
  }

  DockOrientation orientation = [self currentDockOrientation];
  CGPoint originalMouse = [self currentMouseLocation];

  NSArray<NSNumber *> *fractions = nil;
  if (orientation == DockOrientationBottom) {
    fractions = @[@0.50, @0.20, @0.80];
  } else {
    fractions = @[@0.05, @0.15, @0.25, @0.35, @0.45, @0.55, @0.65, @0.75, @0.85, @0.95];
  }

  self.isRelocking = YES;
  CGDisplayHideCursor(kCGDirectMainDisplay);

  CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

  for (NSNumber *fractionValue in fractions) {
    double fraction = fractionValue.doubleValue;
    CGPoint approach = [self approachPointForBounds:bounds orientation:orientation edgeFraction:fraction];
    CGPoint trigger = [self triggerPointForDisplayBounds:bounds orientation:orientation edgeFraction:fraction];

    CGWarpMouseCursorPosition(approach);
    usleep(35000);

    NSInteger travelSteps = (orientation == DockOrientationBottom) ? 8 : 14;
    NSInteger holdSteps = (orientation == DockOrientationBottom) ? 8 : 28;
    useconds_t travelDelay = (orientation == DockOrientationBottom) ? 14000 : 17000;
    useconds_t holdDelay = (orientation == DockOrientationBottom) ? 26000 : 24000;

    for (NSInteger i = 0; i < travelSteps; i++) {
      double progress = (double)i / (double)MAX(travelSteps - 1, 1);
      CGPoint stepPoint = CGPointMake(approach.x + (trigger.x - approach.x) * progress,
                                      approach.y + (trigger.y - approach.y) * progress);
      CGWarpMouseCursorPosition(stepPoint);
      if (source != NULL) {
        CGEventRef event = CGEventCreateMouseEvent(source, kCGEventMouseMoved, stepPoint, kCGMouseButtonLeft);
        if (event != NULL) {
          CGEventSetIntegerValueField(event, kCGEventSourceUserData, 0xD0C4A5C4);
          CGEventPost(kCGHIDEventTap, event);
          CFRelease(event);
        }
      }
      usleep(travelDelay);
    }

    for (NSInteger hold = 0; hold < holdSteps; hold++) {
      CGPoint holdPoint = trigger;
      if (orientation != DockOrientationBottom) {
        CGFloat jitter = (hold % 2 == 0) ? -20.0 : 20.0;
        holdPoint.y = MAX(CGRectGetMinY(bounds) + 8.0, MIN(CGRectGetMaxY(bounds) - 8.0, trigger.y + jitter));
      }

      CGWarpMouseCursorPosition(holdPoint);
      if (source != NULL) {
        CGEventRef event = CGEventCreateMouseEvent(source, kCGEventMouseMoved, holdPoint, kCGMouseButtonLeft);
        if (event != NULL) {
          CGPoint delta = [self edgePressureDeltaForOrientation:orientation];
          CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, (int64_t)llround(delta.x));
          CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, (int64_t)llround(delta.y));
          CGEventSetIntegerValueField(event, kCGEventSourceUserData, 0xD0C4A5C4);
          CGEventPost(kCGHIDEventTap, event);
          CFRelease(event);
        }
      }
      usleep(holdDelay);
    }

    if ([self currentDockDisplayID] == displayID) {
      break;
    }
  }

  if (source != NULL) {
    CFRelease(source);
  }

  CGWarpMouseCursorPosition(originalMouse);
  CGDisplayShowCursor(kCGDirectMainDisplay);
  self.isRelocking = NO;
}

#pragma mark - Dock state helpers

- (DockOrientation)currentDockOrientation {
  CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("orientation"), CFSTR("com.apple.dock"));
  if (value == NULL) {
    return DockOrientationBottom;
  }

  DockOrientation orientation = DockOrientationBottom;
  if (CFGetTypeID(value) == CFStringGetTypeID()) {
    NSString *orientationValue = (__bridge_transfer NSString *)value;
    if ([orientationValue isEqualToString:@"left"]) {
      orientation = DockOrientationLeft;
    } else if ([orientationValue isEqualToString:@"right"]) {
      orientation = DockOrientationRight;
    }
  } else {
    CFRelease(value);
  }

  return orientation;
}

- (CGDirectDisplayID)currentDockDisplayID {
  CGDirectDisplayID byAX = [self currentDockDisplayIDUsingAccessibility];
  if (byAX != kCGNullDirectDisplay) {
    return byAX;
  }

  return [self currentDockDisplayIDUsingWindowInfo];
}

- (CGDirectDisplayID)currentDockDisplayIDUsingAccessibility {
  NSArray<NSRunningApplication *> *dockApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
  NSRunningApplication *dock = dockApps.firstObject;
  if (dock == nil) {
    return kCGNullDirectDisplay;
  }

  AXUIElementRef appElement = AXUIElementCreateApplication(dock.processIdentifier);
  if (appElement == NULL) {
    return kCGNullDirectDisplay;
  }

  CFTypeRef windowsValue = NULL;
  AXError windowsErr = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &windowsValue);
  if (windowsErr != kAXErrorSuccess || windowsValue == NULL || CFGetTypeID(windowsValue) != CFArrayGetTypeID()) {
    if (windowsValue != NULL) {
      CFRelease(windowsValue);
    }
    CFRelease(appElement);
    return kCGNullDirectDisplay;
  }

  CFArrayRef windows = (CFArrayRef)windowsValue;
  CFIndex count = CFArrayGetCount(windows);
  CGDirectDisplayID foundDisplay = kCGNullDirectDisplay;

  for (CFIndex i = 0; i < count; i++) {
    AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
    if (window == NULL) {
      continue;
    }

    CFTypeRef positionValue = NULL;
    AXError posErr = AXUIElementCopyAttributeValue(window, kAXPositionAttribute, &positionValue);
    if (posErr != kAXErrorSuccess || positionValue == NULL || CFGetTypeID(positionValue) != AXValueGetTypeID()) {
      if (positionValue != NULL) {
        CFRelease(positionValue);
      }
      continue;
    }

    CGPoint position = CGPointZero;
    if (AXValueGetValue((AXValueRef)positionValue, kAXValueCGPointType, &position)) {
      foundDisplay = [self displayContainingPoint:position];
      CFRelease(positionValue);
      if (foundDisplay != kCGNullDirectDisplay) {
        break;
      }
      continue;
    }

    CFRelease(positionValue);
  }

  CFRelease(windowsValue);
  CFRelease(appElement);
  return foundDisplay;
}

- (CGDirectDisplayID)currentDockDisplayIDUsingWindowInfo {
  CFArrayRef windowInfoRef = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
  if (windowInfoRef == NULL) {
    return kCGNullDirectDisplay;
  }

  NSArray *windows = CFBridgingRelease(windowInfoRef);
  CGRect chosenRect = CGRectNull;
  CGFloat chosenArea = 0;

  for (NSDictionary *window in windows) {
    NSString *owner = window[(id)kCGWindowOwnerName];
    if (![owner isEqualToString:@"Dock"]) {
      continue;
    }

    NSNumber *layer = window[(id)kCGWindowLayer];
    if (layer != nil && layer.integerValue != 20) {
      continue;
    }

    NSDictionary *boundsDict = window[(id)kCGWindowBounds];
    if (![boundsDict isKindOfClass:[NSDictionary class]]) {
      continue;
    }

    CGRect rect = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &rect)) {
      continue;
    }

    CGFloat area = rect.size.width * rect.size.height;
    if (area <= chosenArea || area < 1000) {
      continue;
    }

    chosenArea = area;
    chosenRect = rect;
  }

  if (CGRectIsNull(chosenRect) || chosenArea <= 0) {
    return kCGNullDirectDisplay;
  }

  CGPoint center = CGPointMake(CGRectGetMidX(chosenRect), CGRectGetMidY(chosenRect));
  return [self displayContainingPoint:center];
}

#pragma mark - Display helpers

- (void)ensureSelectedDisplayExists {
  NSArray<NSDictionary *> *displays = [self availableDisplays];
  if (displays.count == 0) {
    self.selectedDisplayUUIDValue = nil;
    return;
  }

  NSString *selectedUUID = self.selectedDisplayUUIDValue;
  if (selectedUUID.length > 0) {
    for (NSDictionary *display in displays) {
      if ([display[@"uuid"] isEqualToString:selectedUUID]) {
        return;
      }
    }
  }

  NSDictionary *fallback = nil;
  for (NSDictionary *display in displays) {
    if (![display[@"isBuiltin"] boolValue]) {
      fallback = display;
      break;
    }
  }
  if (fallback == nil) {
    fallback = displays.firstObject;
  }

  self.selectedDisplayUUIDValue = fallback[@"uuid"];
  [[NSUserDefaults standardUserDefaults] setObject:self.selectedDisplayUUIDValue forKey:kDefaultsDisplayUUIDKey];
}

- (CGDirectDisplayID)targetDisplayID {
  NSString *uuid = self.selectedDisplayUUIDValue;
  if (uuid.length == 0) {
    return kCGNullDirectDisplay;
  }

  for (NSDictionary *display in [self availableDisplays]) {
    if ([display[@"uuid"] isEqualToString:uuid]) {
      return (CGDirectDisplayID)[display[@"displayID"] unsignedIntValue];
    }
  }

  return kCGNullDirectDisplay;
}

- (BOOL)selectedDisplayCanHostCurrentDockOrientation {
  CGDirectDisplayID targetDisplay = [self targetDisplayID];
  if (targetDisplay == kCGNullDirectDisplay) {
    return NO;
  }

  return [self displayIDCanHostDockForOrientation:targetDisplay orientation:[self currentDockOrientation]];
}

- (BOOL)displayIDCanHostDockForOrientation:(CGDirectDisplayID)displayID orientation:(DockOrientation)orientation {
  if (orientation == DockOrientationBottom) {
    return YES;
  }

  uint32_t displayCount = 0;
  CGGetActiveDisplayList(0, NULL, &displayCount);
  if (displayCount == 0) {
    return NO;
  }

  CGDirectDisplayID ids[displayCount];
  CGGetActiveDisplayList(displayCount, ids, &displayCount);

  CGRect targetBounds = CGDisplayBounds(displayID);
  CGFloat minX = CGFLOAT_MAX;
  CGFloat maxX = -CGFLOAT_MAX;
  for (uint32_t i = 0; i < displayCount; i++) {
    CGRect bounds = CGDisplayBounds(ids[i]);
    minX = MIN(minX, CGRectGetMinX(bounds));
    maxX = MAX(maxX, CGRectGetMaxX(bounds));
  }

  CGFloat epsilon = 1.0;
  if (orientation == DockOrientationLeft) {
    return fabs(CGRectGetMinX(targetBounds) - minX) <= epsilon;
  }

  if (orientation == DockOrientationRight) {
    return fabs(CGRectGetMaxX(targetBounds) - maxX) <= epsilon;
  }

  return YES;
}

- (NSString *)uuidStringForDisplayID:(CGDirectDisplayID)displayID {
  CFUUIDRef uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID);
  if (uuidRef == NULL) {
    return nil;
  }

  CFStringRef uuidStringRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
  CFRelease(uuidRef);
  if (uuidStringRef == NULL) {
    return nil;
  }

  NSString *uuid = [(__bridge NSString *)uuidStringRef copy];
  CFRelease(uuidStringRef);
  return uuid;
}

- (CGDirectDisplayID)displayContainingPoint:(CGPoint)point {
  uint32_t matched = 0;
  CGDirectDisplayID found[8] = {0};
  CGError err = CGGetDisplaysWithPoint(point, 8, found, &matched);
  if (err == kCGErrorSuccess && matched > 0) {
    return found[0];
  }

  return kCGNullDirectDisplay;
}

- (CGPoint)currentMouseLocation {
  CGEventRef event = CGEventCreate(NULL);
  if (event == NULL) {
    return CGPointZero;
  }

  CGPoint point = CGEventGetLocation(event);
  CFRelease(event);
  return point;
}

- (CGPoint)triggerPointForDisplayBounds:(CGRect)bounds orientation:(DockOrientation)orientation edgeFraction:(double)edgeFraction {
  switch (orientation) {
    case DockOrientationBottom:
      return CGPointMake(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) * edgeFraction, CGRectGetMaxY(bounds) - 1.0);
    case DockOrientationLeft:
      return CGPointMake(CGRectGetMinX(bounds) + 1.0, CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * edgeFraction);
    case DockOrientationRight:
      return CGPointMake(CGRectGetMaxX(bounds) - 1.0, CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * edgeFraction);
  }
}

- (CGPoint)approachPointForBounds:(CGRect)bounds orientation:(DockOrientation)orientation edgeFraction:(double)edgeFraction {
  switch (orientation) {
    case DockOrientationBottom:
      return CGPointMake(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) * edgeFraction, CGRectGetMaxY(bounds) - 45.0);
    case DockOrientationLeft:
      return CGPointMake(CGRectGetMinX(bounds) + 45.0, CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * edgeFraction);
    case DockOrientationRight:
      return CGPointMake(CGRectGetMaxX(bounds) - 45.0, CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * edgeFraction);
  }
}

- (CGRect)dockTriggerZoneForBounds:(CGRect)bounds orientation:(DockOrientation)orientation {
  static CGFloat const kZoneThickness = 12.0;

  switch (orientation) {
    case DockOrientationBottom:
      return CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - kZoneThickness, CGRectGetWidth(bounds), kZoneThickness);
    case DockOrientationLeft:
      return CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), kZoneThickness, CGRectGetHeight(bounds));
    case DockOrientationRight:
      return CGRectMake(CGRectGetMaxX(bounds) - kZoneThickness, CGRectGetMinY(bounds), kZoneThickness, CGRectGetHeight(bounds));
  }
}

- (CGPoint)edgePressureDeltaForOrientation:(DockOrientation)orientation {
  switch (orientation) {
    case DockOrientationBottom:
      return CGPointMake(0.0, 30.0);
    case DockOrientationLeft:
      return CGPointMake(-40.0, 0.0);
    case DockOrientationRight:
      return CGPointMake(40.0, 0.0);
  }
}

- (void)notifyStateChange {
  if (self.stateDidChangeHandler != nil) {
    self.stateDidChangeHandler();
  }
}

@end

static CGEventRef DockLockEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
  DockLockController *controller = (__bridge DockLockController *)refcon;
  return [controller handleEventTapWithProxy:proxy type:type event:event];
}

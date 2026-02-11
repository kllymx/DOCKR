#import "AppDelegate.h"

#import "DockLockController.h"
#import "GitHubUpdater.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) DockLockController *controller;
@property (nonatomic, strong) GitHubUpdater *updater;
@property (nonatomic, strong) NSTimer *backgroundUpdateTimer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  #pragma unused(notification)

  self.controller = [[DockLockController alloc] init];
  self.updater = [[GitHubUpdater alloc] initWithBundle:[NSBundle mainBundle]];

  __weak typeof(self) weakSelf = self;
  self.controller.stateDidChangeHandler = ^{
    [weakSelf rebuildMenu];
    [weakSelf updateStatusItemAppearance];
  };

  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  self.menu = [[NSMenu alloc] initWithTitle:@"DockLock"];
  self.menu.delegate = self;
  self.statusItem.menu = self.menu;

  [self updateStatusItemAppearance];
  [self rebuildMenu];

  // Silent background update checks every 12 hours.
  self.backgroundUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:12 * 60 * 60
                                                                target:self
                                                              selector:@selector(checkForUpdatesInBackground:)
                                                              userInfo:nil
                                                               repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:self.backgroundUpdateTimer forMode:NSRunLoopCommonModes];

  [self.updater checkForUpdatesInteractive:NO];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  #pragma unused(notification)
  [self.backgroundUpdateTimer invalidate];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
  #pragma unused(menu)
  [self rebuildMenu];
}

- (void)updateStatusItemAppearance {
  if (self.statusItem == nil) {
    return;
  }

  NSString *symbolName = [self.controller isEnabled] ? @"lock.shield.fill" : @"lock.open";
  NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:@"DockLock"];
  if (image != nil) {
    image.template = YES;
    self.statusItem.button.image = image;
    self.statusItem.button.title = @"";
  } else {
    self.statusItem.button.title = [self.controller isEnabled] ? @"DL" : @"DL*";
  }

  self.statusItem.button.toolTip = [self.controller statusLine];
}

- (void)rebuildMenu {
  if (self.menu == nil) {
    return;
  }

  [self.menu removeAllItems];

  NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"DockLock" action:nil keyEquivalent:@""];
  titleItem.enabled = NO;
  titleItem.image = [self menuSymbol:@"lock.shield"];
  [self.menu addItem:titleItem];

  NSMenuItem *statusItem = [[NSMenuItem alloc] initWithTitle:[self.controller statusLine] action:nil keyEquivalent:@""];
  statusItem.enabled = NO;
  [self.menu addItem:statusItem];

  NSMenuItem *orientationItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Dock orientation: %@", [self.controller dockOrientationLabel]] action:nil keyEquivalent:@""];
  orientationItem.enabled = NO;
  orientationItem.image = [self menuSymbol:@"dock.rectangle"];
  [self.menu addItem:orientationItem];

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSString *toggleTitle = [self.controller isEnabled] ? @"Disable Lock" : @"Enable Lock";
  NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:toggleTitle action:@selector(toggleLock:) keyEquivalent:@""];
  toggle.target = self;
  toggle.image = [self menuSymbol:[self.controller isEnabled] ? @"lock.open" : @"lock.fill"];
  [self.menu addItem:toggle];

  NSMenuItem *relock = [[NSMenuItem alloc] initWithTitle:@"Relock Now" action:@selector(relockNow:) keyEquivalent:@""];
  relock.target = self;
  relock.enabled = [self.controller isEnabled];
  relock.image = [self menuSymbol:@"arrow.triangle.2.circlepath"];
  [self.menu addItem:relock];

  NSMenuItem *displaysHeader = [[NSMenuItem alloc] initWithTitle:@"Target Display" action:nil keyEquivalent:@""];
  displaysHeader.enabled = NO;
  displaysHeader.image = [self menuSymbol:@"display"];
  [self.menu addItem:displaysHeader];

  NSString *selectedUUID = [self.controller selectedDisplayUUID] ?: @"";
  NSArray<NSDictionary *> *displays = [self.controller availableDisplays];
  BOOL hasUnavailableDisplay = NO;

  if (displays.count == 0) {
    NSMenuItem *noneItem = [[NSMenuItem alloc] initWithTitle:@"No displays found" action:nil keyEquivalent:@""];
    noneItem.enabled = NO;
    [self.menu addItem:noneItem];
  } else {
    for (NSDictionary *display in displays) {
      NSString *name = display[@"name"] ?: @"Display";
      BOOL isBuiltin = [display[@"isBuiltin"] boolValue];
      BOOL canHost = [display[@"canHostCurrentOrientation"] boolValue];
      NSString *title = [name stringByAppendingString:isBuiltin ? @" (Built-in)" : @" (External)"];
      if (!canHost) {
        hasUnavailableDisplay = YES;
        title = [title stringByAppendingString:@" (Unavailable for current Dock side)"];
      }

      NSMenuItem *displayItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(selectDisplay:) keyEquivalent:@""];
      displayItem.target = self;
      displayItem.representedObject = display[@"uuid"];
      displayItem.state = [selectedUUID isEqualToString:display[@"uuid"]] ? NSControlStateValueOn : NSControlStateValueOff;
      displayItem.enabled = canHost;
      displayItem.image = [self menuSymbol:canHost ? @"display" : @"nosign"];
      [self.menu addItem:displayItem];
    }
  }

  if (hasUnavailableDisplay) {
    NSString *orientation = [self.controller dockOrientationLabel];
    NSString *hint = [NSString stringWithFormat:@"Only outermost %@-edge displays can host Dock", orientation];
    NSMenuItem *hintItem = [[NSMenuItem alloc] initWithTitle:hint action:nil keyEquivalent:@""];
    hintItem.enabled = NO;
    [self.menu addItem:hintItem];
  }

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..." action:@selector(checkForUpdates:) keyEquivalent:@""];
  updates.target = self;
  updates.image = [self menuSymbol:@"arrow.down.circle"];
  [self.menu addItem:updates];

  NSMenuItem *releases = [[NSMenuItem alloc] initWithTitle:@"Open Releases Page" action:@selector(openReleasesPage:) keyEquivalent:@""];
  releases.target = self;
  releases.image = [self menuSymbol:@"safari"];
  [self.menu addItem:releases];

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit DockLock" action:@selector(quitApp:) keyEquivalent:@"q"];
  quitItem.target = self;
  quitItem.image = [self menuSymbol:@"xmark.circle"];
  [self.menu addItem:quitItem];
}

- (NSImage *)menuSymbol:(NSString *)symbolName {
  NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
  if (image == nil) {
    return nil;
  }
  image.template = YES;
  image.size = NSMakeSize(14, 14);
  return image;
}

- (void)toggleLock:(id)sender {
  #pragma unused(sender)
  [self.controller toggleEnabled];
}

- (void)relockNow:(id)sender {
  #pragma unused(sender)
  [self.controller relockNowWithReason:@"Manual relock"]; 
}

- (void)selectDisplay:(id)sender {
  if (![sender isKindOfClass:[NSMenuItem class]]) {
    return;
  }

  NSString *displayUUID = ((NSMenuItem *)sender).representedObject;
  if ([displayUUID isKindOfClass:[NSString class]] && displayUUID.length > 0) {
    [self.controller selectDisplayUUID:displayUUID];
  }
}

- (void)checkForUpdates:(id)sender {
  #pragma unused(sender)
  [self.updater checkForUpdatesInteractive:YES];
}

- (void)openReleasesPage:(id)sender {
  #pragma unused(sender)
  [self.updater openReleasesPage];
}

- (void)quitApp:(id)sender {
  #pragma unused(sender)
  [NSApp terminate:nil];
}

- (void)checkForUpdatesInBackground:(NSTimer *)timer {
  #pragma unused(timer)
  [self.updater checkForUpdatesInteractive:NO];
}

@end

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

  NSString *symbolName = [self.controller isEnabled] ? @"lock.fill" : @"lock.open";
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

  NSMenuItem *statusItem = [[NSMenuItem alloc] initWithTitle:[self.controller statusLine] action:nil keyEquivalent:@""];
  statusItem.enabled = NO;
  [self.menu addItem:statusItem];

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *toggle = [[NSMenuItem alloc] initWithTitle:@"Enable Lock" action:@selector(toggleLock:) keyEquivalent:@""];
  toggle.target = self;
  toggle.state = [self.controller isEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
  [self.menu addItem:toggle];

  NSMenuItem *relock = [[NSMenuItem alloc] initWithTitle:@"Relock Now" action:@selector(relockNow:) keyEquivalent:@""];
  relock.target = self;
  relock.enabled = [self.controller isEnabled];
  [self.menu addItem:relock];

  NSMenuItem *displaysHeader = [[NSMenuItem alloc] initWithTitle:@"Lock Target" action:nil keyEquivalent:@""];
  displaysHeader.enabled = NO;
  [self.menu addItem:displaysHeader];

  NSString *selectedUUID = [self.controller selectedDisplayUUID] ?: @"";
  NSArray<NSDictionary *> *displays = [self.controller availableDisplays];

  if (displays.count == 0) {
    NSMenuItem *noneItem = [[NSMenuItem alloc] initWithTitle:@"No displays found" action:nil keyEquivalent:@""];
    noneItem.enabled = NO;
    [self.menu addItem:noneItem];
  } else {
    for (NSDictionary *display in displays) {
      NSString *name = display[@"name"] ?: @"Display";
      BOOL isBuiltin = [display[@"isBuiltin"] boolValue];
      NSString *title = [name stringByAppendingString:isBuiltin ? @" (Built-in)" : @" (External)"];

      NSMenuItem *displayItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(selectDisplay:) keyEquivalent:@""];
      displayItem.target = self;
      displayItem.representedObject = display[@"uuid"];
      displayItem.state = [selectedUUID isEqualToString:display[@"uuid"]] ? NSControlStateValueOn : NSControlStateValueOff;
      [self.menu addItem:displayItem];
    }
  }

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..." action:@selector(checkForUpdates:) keyEquivalent:@""];
  updates.target = self;
  [self.menu addItem:updates];

  NSMenuItem *releases = [[NSMenuItem alloc] initWithTitle:@"Open Releases Page" action:@selector(openReleasesPage:) keyEquivalent:@""];
  releases.target = self;
  [self.menu addItem:releases];

  [self.menu addItem:[NSMenuItem separatorItem]];

  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit DockLock" action:@selector(quitApp:) keyEquivalent:@"q"];
  quitItem.target = self;
  [self.menu addItem:quitItem];
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

#import "GitHubUpdater.h"

#import <AppKit/AppKit.h>

@interface GitHubUpdater ()
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, copy) NSString *owner;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, copy) NSString *branch;
@property (nonatomic, assign) BOOL checkInFlight;
@property (nonatomic, assign) BOOL pendingUpdate;
@property (nonatomic, copy) NSString *pendingVersion;
@property (nonatomic, copy) NSString *pendingTag;
@property (nonatomic, copy) NSString *pendingReleaseURL;
@end

@implementation GitHubUpdater

- (instancetype)initWithBundle:(NSBundle *)bundle {
  self = [super init];
  if (self == nil) {
    return nil;
  }

  self.bundle = bundle;
  NSString *owner = [bundle objectForInfoDictionaryKey:@"GitHubOwner"];
  NSString *repo = [bundle objectForInfoDictionaryKey:@"GitHubRepo"];
  NSString *branch = [bundle objectForInfoDictionaryKey:@"GitDefaultBranch"];

  self.owner = owner.length > 0 ? owner : @"";
  self.repo = repo.length > 0 ? repo : @"";
  self.branch = branch.length > 0 ? branch : @"main";
  self.pendingUpdate = NO;
  self.pendingVersion = @"";
  self.pendingTag = @"";
  self.pendingReleaseURL = @"";

  return self;
}

- (void)openReleasesPage {
  if (![self hasRepoConfig]) {
    return;
  }

  NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@/releases", self.owner, self.repo];
  NSURL *url = [NSURL URLWithString:urlString];
  if (url != nil) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
}

- (BOOL)hasPendingUpdate {
  return self.pendingUpdate;
}

- (NSString *)pendingUpdateTitle {
  if (!self.pendingUpdate) {
    return @"Restart to Update";
  }

  if (self.pendingVersion.length > 0) {
    return [NSString stringWithFormat:@"Restart to Update (%@)", self.pendingVersion];
  }

  if (self.pendingTag.length > 0) {
    return [NSString stringWithFormat:@"Restart to Update (%@)", self.pendingTag];
  }

  return @"Restart to Update";
}

- (void)checkForUpdatesInteractive:(BOOL)interactive {
  if (![self hasRepoConfig]) {
    if (interactive) {
      [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub update metadata is not configured in this build."];
    }
    return;
  }

  if (self.checkInFlight) {
    return;
  }

  self.checkInFlight = YES;
  [self checkReleaseUpdateWithCompletion:^(BOOL hasUpdate, NSString *latestVersion, NSString *latestTag, NSString *releaseURL, NSError *error) {
    self.checkInFlight = NO;

    if (error != nil) {
      if (interactive) {
        [self showInfoAlertWithTitle:@"DOCKR" message:@"Could not check for updates right now."];
      }
      return;
    }

    [self setPendingUpdate:hasUpdate latestVersion:latestVersion latestTag:latestTag releaseURL:releaseURL];

    if (!interactive) {
      return;
    }

    if (!hasUpdate) {
      [self showInfoAlertWithTitle:@"DOCKR" message:@"You are up to date."];
      return;
    }

    NSString *currentVersion = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"DOCKR Update Ready";
    alert.informativeText = [NSString stringWithFormat:@"Version %@ is available (you have %@).\n\nDOCKR will restart to apply the update.", latestVersion.length > 0 ? latestVersion : latestTag, currentVersion];
    [alert addButtonWithTitle:@"Restart to Update"];
    [alert addButtonWithTitle:@"Later"];
    [alert addButtonWithTitle:@"View Release"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [self installPendingUpdateInteractive:NO];
    } else if (response == NSAlertThirdButtonReturn) {
      NSURL *downloadURL = [NSURL URLWithString:releaseURL.length > 0 ? releaseURL : [NSString stringWithFormat:@"https://github.com/%@/%@/releases/latest", self.owner, self.repo]];
      if (downloadURL != nil) {
        [[NSWorkspace sharedWorkspace] openURL:downloadURL];
      }
    }
  }];
}

- (void)installPendingUpdateInteractive:(BOOL)interactive {
  if (![self hasPendingUpdate]) {
    if (interactive) {
      [self showInfoAlertWithTitle:@"DOCKR" message:@"No update is pending. Check for updates first."];
    }
    return;
  }

  if (interactive) {
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.alertStyle = NSAlertStyleInformational;
    confirm.messageText = @"Restart DOCKR to update?";
    confirm.informativeText = @"DOCKR will quit, install the latest stable release, and relaunch.";
    [confirm addButtonWithTitle:@"Restart and Update"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) {
      return;
    }
  }

  NSString *scriptURL = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/scripts/update-in-place.sh", self.owner, self.repo, self.branch];
  NSString *bundleID = [self.bundle bundleIdentifier] ?: @"io.dockr.app";
  NSString *pidString = [NSString stringWithFormat:@"%d", [NSProcessInfo processInfo].processIdentifier];

  NSString *command = [NSString stringWithFormat:@"OWNER=%@ REPO=%@ TARGET_APP_PATH=%@ APP_BUNDLE_ID=%@ APP_PID=%@ bash <(curl -fsSL %@)",
                       [self shellEscape:self.owner],
                       [self shellEscape:self.repo],
                       [self shellEscape:@"/Applications/DOCKR.app"],
                       [self shellEscape:bundleID],
                       [self shellEscape:pidString],
                       [self shellEscape:scriptURL]];

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ];

  @try {
    [task launch];
  } @catch (NSException *exception) {
    #pragma unused(exception)
    NSURL *fallback = [NSURL URLWithString:scriptURL];
    if (fallback != nil) {
      [[NSWorkspace sharedWorkspace] openURL:fallback];
    }
    if (interactive) {
      [self showInfoAlertWithTitle:@"DOCKR" message:@"Could not start update installer."];
    }
  }
}

#pragma mark - Release updates

- (void)checkReleaseUpdateWithCompletion:(void (^)(BOOL hasUpdate, NSString *latestVersion, NSString *latestTag, NSString *releaseURL, NSError *error))completion {
  NSString *apiString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/releases/latest", self.owner, self.repo];
  NSURL *url = [NSURL URLWithString:apiString];
  if (url == nil) {
    completion(NO, @"", @"", @"", [NSError errorWithDomain:@"DOCKR.Update" code:-3 userInfo:nil]);
    return;
  }

  [self fetchJSONFromURL:url completion:^(NSDictionary *json, NSError *error, NSInteger statusCode) {
    if (error != nil || statusCode < 200 || statusCode >= 300 || ![json isKindOfClass:[NSDictionary class]]) {
      completion(NO, @"", @"", @"", error ?: [NSError errorWithDomain:@"DOCKR.Update" code:-4 userInfo:nil]);
      return;
    }

    NSString *latestTag = [json[@"tag_name"] isKindOfClass:[NSString class]] ? json[@"tag_name"] : @"";
    NSString *releaseURL = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : @"";
    if (latestTag.length == 0) {
      completion(NO, @"", @"", @"", [NSError errorWithDomain:@"DOCKR.Update" code:-5 userInfo:nil]);
      return;
    }

    NSString *latestVersion = [self normalizedVersionFromTag:latestTag];
    NSString *currentVersion = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    BOOL hasUpdate = [self isVersion:latestVersion newerThan:currentVersion];

    completion(hasUpdate, latestVersion, latestTag, releaseURL, nil);
  }];
}

- (void)setPendingUpdate:(BOOL)hasUpdate
           latestVersion:(NSString *)latestVersion
               latestTag:(NSString *)latestTag
              releaseURL:(NSString *)releaseURL {
  BOOL stateChanged = (self.pendingUpdate != hasUpdate) ||
    ![self.pendingVersion isEqualToString:latestVersion ?: @""] ||
    ![self.pendingTag isEqualToString:latestTag ?: @""] ||
    ![self.pendingReleaseURL isEqualToString:releaseURL ?: @""];

  self.pendingUpdate = hasUpdate;
  self.pendingVersion = latestVersion ?: @"";
  self.pendingTag = latestTag ?: @"";
  self.pendingReleaseURL = releaseURL ?: @"";

  if (stateChanged) {
    [self notifyStateDidChange];
  }
}

- (BOOL)hasRepoConfig {
  return self.owner.length > 0 && self.repo.length > 0;
}

#pragma mark - Shared helpers

- (void)notifyStateDidChange {
  if (self.stateDidChangeHandler == nil) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    self.stateDidChangeHandler();
  });
}

- (void)fetchJSONFromURL:(NSURL *)url completion:(void (^)(NSDictionary *json, NSError *error, NSInteger statusCode))completion {
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  configuration.timeoutIntervalForRequest = 12;
  configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

  NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                      completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error != nil || data == nil) {
        completion(nil, error ?: [NSError errorWithDomain:@"DOCKR.Update" code:-1 userInfo:nil], 0);
        return;
      }

      NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
      NSInteger statusCode = [http isKindOfClass:[NSHTTPURLResponse class]] ? http.statusCode : 0;

      NSError *jsonError = nil;
      NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
      if (jsonError != nil || ![json isKindOfClass:[NSDictionary class]]) {
        completion(nil, jsonError ?: [NSError errorWithDomain:@"DOCKR.Update" code:-2 userInfo:nil], statusCode);
        return;
      }

      completion(json, nil, statusCode);
    });
  }];

  [task resume];
}

- (NSString *)normalizedVersionFromTag:(NSString *)tag {
  NSString *trimmed = [tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed hasPrefix:@"v"] || [trimmed hasPrefix:@"V"]) {
    return [trimmed substringFromIndex:1];
  }
  return trimmed;
}

- (BOOL)isVersion:(NSString *)lhs newerThan:(NSString *)rhs {
  return [lhs compare:rhs options:NSNumericSearch] == NSOrderedDescending;
}

- (NSString *)shellEscape:(NSString *)value {
  if (value == nil || value.length == 0) {
    return @"''";
  }

  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
  return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)showInfoAlertWithTitle:(NSString *)title message:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleInformational;
  alert.messageText = title;
  alert.informativeText = message;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

@end

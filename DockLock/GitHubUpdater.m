#import "GitHubUpdater.h"

#import <AppKit/AppKit.h>

@interface GitHubUpdater ()
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, copy) NSString *owner;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, copy) NSString *branch;
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

- (void)checkForUpdatesInteractive:(BOOL)interactive {
  if (![self hasRepoConfig]) {
    if (interactive) {
      [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub repository is not configured in Info.plist."];
    }
    return;
  }

  [self checkReleaseUpdateInteractive:interactive completion:^(BOOL handled) {
    if (handled) {
      return;
    }

    [self checkMainBranchUpdateInteractive:interactive completion:^(BOOL mainHandled) {
      if (!mainHandled && interactive) {
        [self showInfoAlertWithTitle:@"DOCKR" message:@"You are up to date."];
      }
    }];
  }];
}

- (BOOL)hasRepoConfig {
  return self.owner.length > 0 && self.repo.length > 0;
}

#pragma mark - Release updates (recommended)

- (void)checkReleaseUpdateInteractive:(BOOL)interactive completion:(void (^)(BOOL handled))completion {
  NSString *apiString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/releases/latest", self.owner, self.repo];
  NSURL *url = [NSURL URLWithString:apiString];
  if (url == nil) {
    completion(NO);
    return;
  }

  [self fetchJSONFromURL:url completion:^(NSDictionary *json, NSError *error, NSInteger statusCode) {
    if (error != nil || statusCode < 200 || statusCode >= 300 || ![json isKindOfClass:[NSDictionary class]]) {
      completion(NO);
      return;
    }

    NSString *latestTag = [json[@"tag_name"] isKindOfClass:[NSString class]] ? json[@"tag_name"] : nil;
    NSString *releaseURL = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
    if (latestTag.length == 0) {
      completion(NO);
      return;
    }

    NSString *latestVersion = [self normalizedVersionFromTag:latestTag];
    NSString *currentVersion = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    BOOL hasUpdate = [self isVersion:latestVersion newerThan:currentVersion];

    if (!hasUpdate) {
      completion(NO);
      return;
    }

    if (!interactive) {
      completion(YES);
      return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"DOCKR Stable Update";
    alert.informativeText = [NSString stringWithFormat:@"Version %@ is available (you have %@).", latestVersion, currentVersion];
    [alert addButtonWithTitle:@"Update Now"]; 
    [alert addButtonWithTitle:@"View Release"]; 
    [alert addButtonWithTitle:@"Cancel"]; 

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [self runInstallerInTerminalForScript:@"install-latest-release.sh"];
    } else if (response == NSAlertSecondButtonReturn) {
      NSURL *downloadURL = [NSURL URLWithString:releaseURL ?: [NSString stringWithFormat:@"https://github.com/%@/%@/releases/latest", self.owner, self.repo]];
      if (downloadURL != nil) {
        [[NSWorkspace sharedWorkspace] openURL:downloadURL];
      }
    }

    completion(YES);
  }];
}

#pragma mark - Main branch updates (fallback)

- (void)checkMainBranchUpdateInteractive:(BOOL)interactive completion:(void (^)(BOOL handled))completion {
  NSString *currentCommit = [[self.bundle objectForInfoDictionaryKey:@"BuildGitCommit"] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  BOOL currentKnown = currentCommit.length > 0 && ![currentCommit isEqualToString:@"unknown"];

  NSString *apiString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/%@", self.owner, self.repo, self.branch];
  NSURL *url = [NSURL URLWithString:apiString];
  if (url == nil) {
    completion(NO);
    return;
  }

  [self fetchJSONFromURL:url completion:^(NSDictionary *json, NSError *error, NSInteger statusCode) {
    if (error != nil || statusCode < 200 || statusCode >= 300 || ![json isKindOfClass:[NSDictionary class]]) {
      completion(NO);
      return;
    }

    NSString *latestCommit = [json[@"sha"] isKindOfClass:[NSString class]] ? json[@"sha"] : nil;
    NSString *latestCommitURL = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
    if (latestCommit.length == 0) {
      completion(NO);
      return;
    }

    BOOL hasMainUpdate = !currentKnown || ![latestCommit hasPrefix:currentCommit];
    if (!hasMainUpdate) {
      completion(NO);
      return;
    }

    if (!interactive) {
      completion(YES);
      return;
    }

    NSString *latestShort = [self shortCommit:latestCommit];
    NSString *currentShort = currentKnown ? [self shortCommit:currentCommit] : @"unknown";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"DOCKR Main Update";
    alert.informativeText = [NSString stringWithFormat:@"A newer commit exists on %@.\n\nCurrent: %@\nLatest: %@\n\nTip: Stable release updates are best for avoiding Accessibility re-authorization prompts.", self.branch, currentShort, latestShort];
    [alert addButtonWithTitle:@"Install Main Build"]; 
    [alert addButtonWithTitle:@"View Commit"]; 
    [alert addButtonWithTitle:@"Cancel"]; 

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [self runInstallerInTerminalForScript:@"install-latest-main.sh"];
    } else if (response == NSAlertSecondButtonReturn) {
      NSURL *changes = [NSURL URLWithString:latestCommitURL ?: [NSString stringWithFormat:@"https://github.com/%@/%@/commits/%@", self.owner, self.repo, self.branch]];
      if (changes != nil) {
        [[NSWorkspace sharedWorkspace] openURL:changes];
      }
    }

    completion(YES);
  }];
}

#pragma mark - Shared helpers

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

- (void)runInstallerInTerminalForScript:(NSString *)scriptName {
  NSString *rawScriptURL = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/scripts/%@", self.owner, self.repo, self.branch, scriptName];
  NSString *command = [NSString stringWithFormat:@"curl -fsSL %@ | bash", rawScriptURL];
  NSString *escaped = [self appleScriptEscapedString:command];
  NSString *source = [NSString stringWithFormat:@"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", escaped];

  NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
  NSDictionary *error = nil;
  [script executeAndReturnError:&error];
  if (error != nil) {
    NSURL *fallback = [NSURL URLWithString:rawScriptURL];
    if (fallback != nil) {
      [[NSWorkspace sharedWorkspace] openURL:fallback];
    }
  }
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

- (NSString *)shortCommit:(NSString *)commit {
  if (commit.length <= 7) {
    return commit;
  }
  return [commit substringToIndex:7];
}

- (NSString *)appleScriptEscapedString:(NSString *)value {
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  return escaped;
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

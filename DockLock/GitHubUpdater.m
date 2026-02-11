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
  if (self.owner.length == 0 || self.repo.length == 0) {
    return;
  }

  NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@/releases", self.owner, self.repo];
  NSURL *url = [NSURL URLWithString:urlString];
  if (url != nil) {
    [[NSWorkspace sharedWorkspace] openURL:url];
  }
}

- (void)checkForUpdatesInteractive:(BOOL)interactive {
  if (self.owner.length == 0 || self.repo.length == 0) {
    if (interactive) {
      [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub repository is not configured in Info.plist."];
    }
    return;
  }

  NSString *apiString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/%@", self.owner, self.repo, self.branch];
  NSURL *url = [NSURL URLWithString:apiString];
  if (url == nil) {
    if (interactive) {
      [self showInfoAlertWithTitle:@"Update Check" message:@"Failed to create GitHub API URL."];
    }
    return;
  }

  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  configuration.timeoutIntervalForRequest = 12;
  configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

  NSString *currentCommit = [[self.bundle objectForInfoDictionaryKey:@"BuildGitCommit"] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *currentVersion = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";

  NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                      completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error != nil || data == nil) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"Could not reach GitHub main branch."];
        }
        return;
      }

      NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
      if (![http isKindOfClass:[NSHTTPURLResponse class]] || http.statusCode < 200 || http.statusCode >= 300) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub update check returned an unexpected response."];
        }
        return;
      }

      NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      if (![json isKindOfClass:[NSDictionary class]]) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub commit payload was invalid."];
        }
        return;
      }

      NSString *latestCommit = [json[@"sha"] isKindOfClass:[NSString class]] ? json[@"sha"] : nil;
      NSString *latestCommitURL = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
      if (latestCommit.length == 0) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"No commit SHA found for main branch."];
        }
        return;
      }

      BOOL currentKnown = currentCommit.length > 0 && ![currentCommit isEqualToString:@"unknown"];
      BOOL hasUpdate = YES;
      if (currentKnown) {
        hasUpdate = ![latestCommit hasPrefix:currentCommit];
      }

      if (!interactive && !hasUpdate) {
        return;
      }

      if (!hasUpdate) {
        if (interactive) {
          NSString *shortCommit = [self shortCommit:latestCommit];
          NSString *message = [NSString stringWithFormat:@"You are up to date.\nVersion: %@\nCommit: %@ (%@)", currentVersion, shortCommit, self.branch];
          [self showInfoAlertWithTitle:@"DOCKR" message:message];
        }
        return;
      }

      if (!interactive) {
        return;
      }

      NSString *latestShort = [self shortCommit:latestCommit];
      NSString *currentShort = currentKnown ? [self shortCommit:currentCommit] : @"unknown";
      NSString *changesURL = latestCommitURL;
      if (currentKnown) {
        changesURL = [NSString stringWithFormat:@"https://github.com/%@/%@/compare/%@...%@", self.owner, self.repo, currentCommit, latestCommit];
      }

      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleInformational;
      alert.messageText = @"DOCKR Update Available";
      alert.informativeText = [NSString stringWithFormat:@"A newer commit was pushed to %@.\n\nCurrent: %@\nLatest: %@\n\nChoose \"Update Now\" to run the installer script in Terminal.", self.branch, currentShort, latestShort];
      [alert addButtonWithTitle:@"Update Now"];
      [alert addButtonWithTitle:@"View Changes"];
      [alert addButtonWithTitle:@"Cancel"];

      NSModalResponse responseCode = [alert runModal];
      if (responseCode == NSAlertFirstButtonReturn) {
        [self runInstallerInTerminal];
      } else if (responseCode == NSAlertSecondButtonReturn) {
        NSURL *changes = [NSURL URLWithString:changesURL];
        if (changes != nil) {
          [[NSWorkspace sharedWorkspace] openURL:changes];
        }
      }
    });
  }];

  [task resume];
}

- (void)runInstallerInTerminal {
  NSString *rawScriptURL = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/scripts/install-latest-main.sh", self.owner, self.repo, self.branch];
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

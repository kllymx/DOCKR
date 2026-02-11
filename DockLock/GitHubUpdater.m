#import "GitHubUpdater.h"

#import <AppKit/AppKit.h>

@interface GitHubUpdater ()
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, copy) NSString *owner;
@property (nonatomic, copy) NSString *repo;
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

  self.owner = owner.length > 0 ? owner : @"";
  self.repo = repo.length > 0 ? repo : @"";

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

  NSString *apiString = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/releases/latest", self.owner, self.repo];
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

  NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                      completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error != nil || data == nil) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"Could not reach GitHub releases."];
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
          [self showInfoAlertWithTitle:@"Update Check" message:@"GitHub release payload was invalid."];
        }
        return;
      }

      NSString *latestTag = [json[@"tag_name"] isKindOfClass:[NSString class]] ? json[@"tag_name"] : nil;
      NSString *releaseURL = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
      if (latestTag.length == 0) {
        if (interactive) {
          [self showInfoAlertWithTitle:@"Update Check" message:@"No release tag found."];
        }
        return;
      }

      NSString *latestVersion = [self normalizedVersionFromTag:latestTag];
      NSString *currentVersion = [self.bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";

      BOOL hasUpdate = [self isVersion:latestVersion newerThan:currentVersion];
      if (!hasUpdate) {
        if (interactive) {
          NSString *message = [NSString stringWithFormat:@"You are up to date (%@).", currentVersion];
          [self showInfoAlertWithTitle:@"DockLock" message:message];
        }
        return;
      }

      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleInformational;
      alert.messageText = @"Update Available";
      alert.informativeText = [NSString stringWithFormat:@"DockLock %@ is available (you have %@).", latestVersion, currentVersion];
      [alert addButtonWithTitle:@"Open Release"]; 
      [alert addButtonWithTitle:@"Cancel"]; 

      if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSURL *downloadURL = [NSURL URLWithString:releaseURL ?: [NSString stringWithFormat:@"https://github.com/%@/%@/releases/latest", self.owner, self.repo]];
        if (downloadURL != nil) {
          [[NSWorkspace sharedWorkspace] openURL:downloadURL];
        }
      }
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

- (void)showInfoAlertWithTitle:(NSString *)title message:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleInformational;
  alert.messageText = title;
  alert.informativeText = message;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

@end

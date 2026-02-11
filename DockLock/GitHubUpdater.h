#import <Foundation/Foundation.h>

@interface GitHubUpdater : NSObject

- (instancetype)initWithBundle:(NSBundle *)bundle;
- (void)checkForUpdatesInteractive:(BOOL)interactive;
- (void)openReleasesPage;

@end

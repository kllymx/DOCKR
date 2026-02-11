#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GitHubUpdater : NSObject

@property (nonatomic, copy, nullable) void (^stateDidChangeHandler)(void);

- (instancetype)initWithBundle:(NSBundle *)bundle;
- (void)checkForUpdatesInteractive:(BOOL)interactive;
- (BOOL)hasPendingUpdate;
- (NSString *)pendingUpdateTitle;
- (void)installPendingUpdateInteractive:(BOOL)interactive;
- (void)openReleasesPage;

@end

NS_ASSUME_NONNULL_END

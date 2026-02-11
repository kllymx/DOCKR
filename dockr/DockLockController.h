#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DockLockController : NSObject

@property (nonatomic, copy, nullable) void (^stateDidChangeHandler)(void);

- (NSArray<NSDictionary *> *)availableDisplays;
- (nullable NSString *)selectedDisplayUUID;
- (NSString *)selectedDisplayLabel;
- (NSString *)dockOrientationLabel;
- (BOOL)isEnabled;
- (NSString *)statusLine;

- (void)setEnabled:(BOOL)enabled;
- (void)toggleEnabled;
- (void)selectDisplayUUID:(NSString *)displayUUID;
- (void)relockNowWithReason:(NSString *)reason;

@end

NS_ASSUME_NONNULL_END

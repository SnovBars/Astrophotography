#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCCrashLogger : NSObject
+ (void)setup;
+ (void)logMessage:(NSString *)message;
@end

NS_ASSUME_NONNULL_END
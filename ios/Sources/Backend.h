#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface Backend : NSObject
+ (nullable NSString *)startWithDataDirectory:(NSString *)directory error:(NSError **)error;
+ (void)pause;
+ (void)resume;
@end
NS_ASSUME_NONNULL_END

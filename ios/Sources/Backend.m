#import "Backend.h"
#import <CFDataMobile/CFDataMobile.h>

@implementation Backend
+ (NSString *)startWithDataDirectory:(NSString *)directory error:(NSError **)error {
    return MobileStart(directory, error);
}
+ (void)pause { MobilePause(); }
+ (void)resume { MobileResume(); }
@end

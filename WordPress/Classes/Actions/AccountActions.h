#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@interface AccountActions : NSObject
+ (void)setVisibility:(BOOL)visibility forBlogID:(NSNumber *)blogID;
@end

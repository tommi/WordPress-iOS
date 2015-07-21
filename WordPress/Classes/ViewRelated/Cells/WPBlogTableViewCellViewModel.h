#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
@class Blog;

@interface WPBlogTableViewCellViewModel : NSObject
@property Blog *blog;
@property (readonly) NSString *title;
@property (readonly) NSString *url;
@property (readonly) NSString *icon;
@property (readonly, assign) BOOL visible;
@property (readonly) RACCommand *visibilitySwitchCommand;
@end

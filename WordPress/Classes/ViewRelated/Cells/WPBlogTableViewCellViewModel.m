#import "WPBlogTableViewCellViewModel.h"
#import "Blog.h"
#import "AccountService.h"
#import "ContextManager.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@interface WPBlogTableViewCellViewModel ()
@property (readwrite) RACCommand *visibilitySwitchCommand;
@end

@implementation WPBlogTableViewCellViewModel

- (instancetype)init
{
    if (!(self = [super init])) {
        return nil;
    }

    [self bindModel];
    [self setupCommands];

    return self;
}

- (void)bindModel
{
    RACSignal *newBlogSignal = RACObserve(self, blog);
    RAC(self, title) = [newBlogSignal map:^NSString *(Blog *blog) {
        return blog.blogName;
    }];
    RAC(self, url) = [newBlogSignal map:^NSString *(Blog *blog) {
        return blog.displayURL;
    }];
    RAC(self, icon) = [newBlogSignal map:^NSString *(Blog *blog) {
        return blog.icon;
    }];
    RAC(self, visible) = [newBlogSignal map:^(Blog *blog) {
        return @(blog.visible);
    }];
}

- (void)setupCommands
{
    self.visibilitySwitchCommand = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(UISwitch *sender) {
        BOOL visible = sender.on;
        AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
        [accountService setVisibility:visible forBlogs:@[self.blog]];
        return [RACSignal empty];
    }];
}

@end

#import "WPBlogTableViewCellViewModel.h"
#import "Blog.h"
#import "AccountActions.h"

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
        [AccountActions setVisibility:visible forBlogID:self.blog.dotComID];
        return [RACSignal empty];
    }];
}

@end

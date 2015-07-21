#import "AccountActions.h"
#import "AccountService.h"
#import "AccountServiceRemoteREST.h"
#import "Blog.h"
#import "BlogService.h"
#import "ContextManager.h"
#import "WPAccount.h"

static const NSTimeInterval VisibilityThrottle = 2.0;
static NSMutableDictionary *visibilityBuffer;
static NSTimer *visibilityTimer;

@implementation AccountActions

#pragma mark - Public Methods

+ (void)setVisibility:(BOOL)visibility forBlogID:(NSNumber *)blogID
{
    NSParameterAssert(blogID != nil);
    [self updateLocalVisibility:visibility forBlogID:blogID];
    [[self visibilityBuffer] setObject:@(visibility) forKey:blogID];
    [self maybeStartTimer];
}

#pragma mark - Private Methods

+ (NSMutableDictionary *)visibilityBuffer
{
    if (!visibilityBuffer) {
        DDLogVerbose(@"Creating visibility bufffer");
        visibilityBuffer = [NSMutableDictionary dictionary];
    }
    return visibilityBuffer;
}

+ (void)maybeStartTimer
{
    if (!visibilityTimer) {
        DDLogVerbose(@"Creating visibility timer");
        visibilityTimer = [NSTimer scheduledTimerWithTimeInterval:VisibilityThrottle
                                                           target:self
                                                         selector:@selector(timerFired:)
                                                         userInfo:nil
                                                          repeats:NO];
    }
}

+ (void)timerFired:(NSTimer *)timer
{
    DDLogVerbose(@"Visibility timer fired");
    AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    WPAccount *defaultAccount = [accountService defaultWordPressComAccount];
    DDLogVerbose(@"Setting visibility of blogs %@", [self visibilityBuffer]);
    AccountServiceRemoteREST *remote = [[AccountServiceRemoteREST alloc] initWithApi:defaultAccount.restApi];
    [remote updateBlogsVisibility:[self visibilityBuffer]
                          success:nil
                          failure:^(NSError *error) {
        DDLogError(@"Error setting blog visibility: %@", error);
    }];
    visibilityBuffer = nil;
    visibilityTimer = nil;
}

+ (void)updateLocalVisibility:(BOOL)visibility forBlogID:(NSNumber *)blogID
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
    Blog *blog = [blogService blogByBlogId:blogID];
    if (blog) {
        blog.visible = visibility;
        [[ContextManager sharedInstance] saveContext:context];
    }
}

@end

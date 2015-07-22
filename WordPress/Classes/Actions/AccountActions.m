#import "AccountActions.h"
#import "AccountService.h"
#import "AccountServiceRemoteREST.h"
#import "Blog.h"
#import "BlogService.h"
#import "ContextManager.h"
#import "WPAccount.h"
#import "RACSignal+WPExtras.h"

static const NSTimeInterval VisibilityThrottle = 2.0;
static NSTimer *visibilityTimer;
static AccountActions *instance;

@interface AccountActions ()

@property (nonatomic, strong) RACSubject *updateVisibilitySignal;

@end

@implementation AccountActions

#pragma mark - Public Methods

- (instancetype)init
{
    self = [super init];
    if (self) {
        _updateVisibilitySignal = [RACSubject new];
        [self startObservation];
    }
    return self;
}

+ (void)setVisibility:(BOOL)visibility forBlogID:(NSNumber *)blogID
{
    NSParameterAssert(blogID != nil);
    [[self sharedInstance] updateLocalVisibility:visibility forBlogID:blogID];
    [[self sharedInstance] setObject:@(visibility) forKey:blogID];
}

#pragma mark - Private Methods

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AccountActions alloc] init];
    });
    return instance;
}

- (void)startObservation
{
    [[self.updateVisibilitySignal bufferWithTime:VisibilityThrottle onScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]] subscribeNext:^(RACTuple *results) {
        NSMutableDictionary *aggregatedValues = [@{} mutableCopy];
        for (NSDictionary *value in results) {
            [aggregatedValues addEntriesFromDictionary:value];
        }
        [self updateRemoteBlogsVisibility:aggregatedValues];
    }];
}

- (void)startThrottledAndBufferedObservation
{
    [[self.updateVisibilitySignal bufferAndThrottleWithTime:VisibilityThrottle onScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityHigh]] subscribeNext:^(RACTuple *results) {
        NSMutableDictionary *aggregatedValues = [@{} mutableCopy];
        for (NSDictionary *value in results) {
            [aggregatedValues addEntriesFromDictionary:value];
        }
        [self updateRemoteBlogsVisibility:aggregatedValues];
    }];
}

- (void)updateLocalVisibility:(BOOL)visibility forBlogID:(NSNumber *)blogID
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
    Blog *blog = [blogService blogByBlogId:blogID];
    if (blog) {
        blog.visible = visibility;
        [[ContextManager sharedInstance] saveContext:context];
    }
}

- (void)setObject:(id)anObject forKey:(id <NSCopying>)aKey;
{
    [self.updateVisibilitySignal sendNext:@{aKey:anObject}];
}

- (void)updateRemoteBlogsVisibility:(NSDictionary *)values
{
    AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    WPAccount *defaultAccount = [accountService defaultWordPressComAccount];
    DDLogVerbose(@"Setting visibility of blogs %@", values);
    AccountServiceRemoteREST *remote = [[AccountServiceRemoteREST alloc] initWithApi:defaultAccount.restApi];
    [remote updateBlogsVisibility:values
                          success:nil
                          failure:^(NSError *error) {
                              DDLogError(@"Error setting blog visibility: %@", error);
                          }];
}

@end

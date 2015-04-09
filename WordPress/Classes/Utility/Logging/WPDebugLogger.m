#import "WPDebugLogger.h"

// Pods
#import <CocoaLumberjack/DDLog.h>
#import <CocoaLumberjack/DDASLLogger.h>
#import <CocoaLumberjack/DDFileLogger.h>
#import <CocoaLumberjack/DDTTYLogger.h>
#import <CrashlyticsLumberjack/CrashlyticsLogger.h>
#import <UIDeviceIdentifier/UIDeviceHardware.h>

// CoreData
#import "AccountService.h"
#import "BlogService.h"
#import "ContextManager.h"

// Data Model
#import "Blog.h"
#import "WPAccount.h"

// Extensions & Categories
#import "NSBundle+VersionNumberHelper.h"
#import "UIDevice+Helpers.h"

// Notifications
#import "NotificationsManager.h"

int ddLogLevel = LOG_LEVEL_INFO;

static NSString* const WPDebugLoggerExtraDebugKey = @"extra_debug";

@interface WPDebugLogger ()
@property (nonatomic, strong, readwrite) DDFileLogger *fileLogger;
@end

@implementation WPDebugLogger

#pragma mark - Inititlization

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [self configureLogging];
    }
    
    return self;
}

#pragma mark - Configuration

- (void)configureLogging
{
    // Remove the old Documents/wordpress.log if it exists
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:@"wordpress.log"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([fileManager fileExistsAtPath:filePath]) {
        [fileManager removeItemAtPath:filePath error:nil];
    }
    
    // Sets up the CocoaLumberjack logging; debug output to console and file
#ifdef DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
#endif
    
#ifndef INTERNAL_BUILD
    [DDLog addLogger:[CrashlyticsLogger sharedInstance]];
#endif
    
    [DDLog addLogger:self.fileLogger];
    
    BOOL extraDebug = [[NSUserDefaults standardUserDefaults] boolForKey:WPDebugLoggerExtraDebugKey];
    if (extraDebug) {
        ddLogLevel = LOG_LEVEL_VERBOSE;
    }
}

#pragma mark - Getters

- (DDFileLogger *)fileLogger
{
    if (!_fileLogger) {
        DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
        fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
        
        _fileLogger = fileLogger;
    }
    
    return _fileLogger;
}

#pragma mark - Reading from the log

// get the log content with a maximum byte size
- (NSString *)getLogFilesContentWithMaxSize:(NSInteger)maxSize
{
    NSMutableString *description = [NSMutableString string];
    
    NSArray *sortedLogFileInfos = [[self.fileLogger logFileManager] sortedLogFileInfos];
    NSInteger count = [sortedLogFileInfos count];
    
    // we start from the last one
    for (NSInteger index = 0; index < count; index++) {
        DDLogFileInfo *logFileInfo = [sortedLogFileInfos objectAtIndex:index];
        
        NSData *logData = [[NSFileManager defaultManager] contentsAtPath:[logFileInfo filePath]];
        if ([logData length] > 0) {
            NSString *result = [[NSString alloc] initWithBytes:[logData bytes]
                                                        length:[logData length]
                                                      encoding: NSUTF8StringEncoding];
            
            [description appendString:result];
        }
    }
    
    if ([description length] > maxSize) {
        description = (NSMutableString *)[description substringWithRange:NSMakeRange(0, maxSize)];
    }
    
    return description;
}

#pragma mark - Logging

- (void)logStartupWithOptions:(NSDictionary *)launchOptions
{
    UIDevice *device = [UIDevice currentDevice];
    NSInteger crashCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"crashCount"];
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    NSString *currentLanguage = [languages objectAtIndex:0];
    BOOL extraDebug = [[NSUserDefaults standardUserDefaults] boolForKey:WPDebugLoggerExtraDebugKey];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    NSArray *blogs = [blogService blogsForAllAccounts];
    
    DDLogInfo(@"===========================================================================");
    DDLogInfo(@"Launching WordPress for iOS %@...", [[NSBundle bundleForClass:[self class]] detailedVersionNumber]);
    DDLogInfo(@"Crash count:       %d", crashCount);
#ifdef DEBUG
    DDLogInfo(@"Debug mode:  Debug");
#else
    DDLogInfo(@"Debug mode:  Production");
#endif
    DDLogInfo(@"Extra debug: %@", extraDebug ? @"YES" : @"NO");
    DDLogInfo(@"Device model: %@ (%@)", [UIDeviceHardware platformString], [UIDeviceHardware platform]);
    DDLogInfo(@"OS:        %@ %@", device.systemName, device.systemVersion);
    DDLogInfo(@"Language:  %@", currentLanguage);
    DDLogInfo(@"UDID:      %@", device.wordPressIdentifier);
    DDLogInfo(@"APN token: %@", [NotificationsManager registeredPushNotificationsToken]);
    DDLogInfo(@"Launch options: %@", launchOptions);
    
    if (blogs.count > 0) {
        DDLogInfo(@"All blogs on device:");
        for (Blog *blog in blogs) {
            DDLogInfo(@"Name: %@ URL: %@ XML-RPC: %@ isWpCom: %@ blogId: %@ jetpackAccount: %@", blog.blogName, blog.url, blog.xmlrpc, blog.account.isWpcom ? @"YES" : @"NO", blog.blogID, !!blog.jetpackAccount ? @"PRESENT" : @"NONE");
        }
    } else {
        DDLogInfo(@"No blogs configured on device.");
    }
    
    DDLogInfo(@"===========================================================================");
}


- (void)toggleExtraDebuggingIfNeeded
{
    if ([self noBlogsAndNoWordPressDotComAccount]) {
        // When there are no blogs in the app the settings screen is unavailable.
        // In this case, enable extra_debugging by default to help troubleshoot any issues.
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"orig_extra_debug"] != nil) {
            return; // Already saved. Don't save again or we could loose the original value.
        }
        
        NSString *origExtraDebug = [[NSUserDefaults standardUserDefaults] boolForKey:WPDebugLoggerExtraDebugKey] ? @"YES" : @"NO";
        [[NSUserDefaults standardUserDefaults] setObject:origExtraDebug forKey:@"orig_extra_debug"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WPDebugLoggerExtraDebugKey];
        ddLogLevel = LOG_LEVEL_VERBOSE;
        [NSUserDefaults resetStandardUserDefaults];
    } else {
        NSString *origExtraDebug = [[NSUserDefaults standardUserDefaults] stringForKey:@"orig_extra_debug"];
        if (origExtraDebug == nil) {
            return;
        }
        
        // Restore the original setting and remove orig_extra_debug.
        [[NSUserDefaults standardUserDefaults] setBool:[origExtraDebug boolValue] forKey:WPDebugLoggerExtraDebugKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"orig_extra_debug"];
        [NSUserDefaults resetStandardUserDefaults];
        
        if ([origExtraDebug boolValue]) {
            ddLogLevel = LOG_LEVEL_VERBOSE;
        }
    }
}

- (BOOL)noBlogsAndNoWordPressDotComAccount
{
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:context];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
    WPAccount *defaultAccount = [accountService defaultWordPressComAccount];
    
    NSInteger blogCount = [blogService blogCountSelfHosted];
    return blogCount == 0 && !defaultAccount;
}

@end

#import "SupportViewController.h"

#import <DDFileLogger.h>
#import <Helpshift/Helpshift.h>
#import <UIDeviceIdentifier/UIDeviceHardware.h>

#import "AboutViewController.h"
#import "ActivityLogViewController.h"
#import "Blog.h"
#import "BlogService.h"
#import "ContextManager.h"
#import "HelpshiftUtils.h"
#import "NSBundle+VersionNumberHelper.h"
#import "WordPressAppDelegate.h"
#import "WordPress-Swift.h"
#import "WPAppAnalytics.h"
#import "WPLogger.h"
#import "WPTabBarController.h"
#import "WPTableViewSectionFooterView.h"

static NSString * const UserDefaultsFeedbackEnabled = @"wp_feedback_enabled";
static NSString * const ExtraDebugDefaultsKey = @"extra_debug";
static NSString * const FeedbackCheckUrl = @"https://api.wordpress.org/iphoneapp/feedback-check/1.0/";
static NSString * const ResponseKeyID = @"ID";
static NSString * const ResponseKeyEmail = @"email";
static NSString * const ResponseKeyDisplayName = @"display_name";
static NSString * const CellIdentifierSwitchAccessory = @"SupportViewSwitchAccessoryCell";
static NSString * const CellIdentifierBadgeAccessory = @"SupportViewBadgeAccessoryCell";
static NSString * const CellIdentifier = @"SupportViewStandardCell";

static const NSInteger ActivitySpinnerTag = 101;
static const NSInteger HelpshiftWindowTypeFAQs = 1;
static const NSInteger HelpshiftWindowTypeConversation = 2;

static const CGFloat SupportRowHeight = 44.0;
static const CGFloat UnreadCountLabelCornerRadius = 15.0;

static const CGRect FrameForHelpShiftUnreadCountLabel = {0.0, 0.0, 50.0, 30.0};

typedef NS_ENUM(NSInteger, SettingsViewControllerSections)
{
    SettingsSectionFAQForums,
    SettingsSectionFeedback,
    SettingsSectionActivityLog,
};

@interface SupportViewController ()
@property (nonatomic, assign) BOOL feedbackEnabled;
@end

@implementation SupportViewController

+ (void)checkIfFeedbackShouldBeEnabled
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{UserDefaultsFeedbackEnabled: @YES}];
    NSURL *url = [NSURL URLWithString:FeedbackCheckUrl];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];

    AFHTTPRequestOperation* operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    operation.responseSerializer = [[AFJSONResponseSerializer alloc] init];

    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        DDLogVerbose(@"Feedback response received: %@", responseObject);
        NSNumber *feedbackEnabled = responseObject[@"feedback-enabled"];
        if (feedbackEnabled == nil) {
            feedbackEnabled = @YES;
        }

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:feedbackEnabled.boolValue forKey:UserDefaultsFeedbackEnabled];
        [defaults synchronize];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error received while checking feedback enabled status: %@", error);

        // Lets be optimistic and turn on feedback by default if this call doesn't work
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:UserDefaultsFeedbackEnabled];
        [defaults synchronize];
    }];

    [operation start];
}

+ (void)showFromTabBar
{
    SupportViewController *supportViewController = [[SupportViewController alloc] init];
    UINavigationController *aNavigationController = [[UINavigationController alloc] initWithRootViewController:supportViewController];
    aNavigationController.navigationBar.translucent = NO;

    if (IS_IPAD) {
        aNavigationController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        aNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }

    UIViewController *presenter = [WPTabBarController sharedInstance];
    if (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:aNavigationController animated:YES completion:nil];
}


#pragma mark - Lifecycle Methods

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _feedbackEnabled = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(helpshiftUnreadCountUpdated:)
                                                     name:HelpshiftUnreadCountUpdatedNotification
                                                   object:nil];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Support", @"Title of the support screen.");

    if ([UIDevice isOS8]) { // iOS8 or higher
        [self.tableView setEstimatedRowHeight:SupportRowHeight];
        [self.tableView setRowHeight:UITableViewAutomaticDimension];
    } else {
        [self.tableView setRowHeight:SupportRowHeight];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.feedbackEnabled = [defaults boolForKey:UserDefaultsFeedbackEnabled];

    [WPStyleGuide configureColorsForView:self.view andTableView:self.tableView];

    [self.navigationController setNavigationBarHidden:NO animated:YES];

    if ([self.navigationController.viewControllers count] == 1) {
        NSString *title = NSLocalizedString(@"Close", @"Title of a close button.");
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:title
                                                                                  style:[WPStyleGuide barButtonStyleForBordered]
                                                                                 target:self
                                                                                 action:@selector(dismiss)];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [HelpshiftUtils refreshUnreadNotificationCount];
    [WPAnalytics track:WPAnalyticsStatOpenedSupport];
}


#pragma mark - Spinner Methods

- (void)showLoadingSpinner
{
    UIActivityIndicatorView *loading = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    loading.tag = ActivitySpinnerTag;
    loading.center = self.view.center;
    loading.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:loading];
    [loading startAnimating];
}

- (void)hideLoadingSpinner
{
    [[self.view viewWithTag:ActivitySpinnerTag] removeFromSuperview];
}


#pragma mark - Helpshift Methods

- (void)prepareAndDisplayHelpshiftWindowOfType:(NSInteger)helpshiftType
{
    [self flagHelpshiftWasUsed];

    NSManagedObjectContext *context = [[ContextManager sharedInstance] newDerivedContext];
    AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:context];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
    WPAccount *defaultAccount = [accountService defaultWordPressComAccount];

    NSString *isWPCom = defaultAccount.isWpcom ? @"Yes" : @"No";
    NSMutableDictionary *metaData = [NSMutableDictionary dictionaryWithDictionary:@{ @"isWPCom" : isWPCom }];

    NSArray *allBlogs = [blogService blogsForAllAccounts];
    for (NSInteger i = 0; i < [allBlogs count]; i++) {
        Blog *blog = allBlogs[i];

        NSDictionary *blogData = @{[NSString stringWithFormat:@"blog-%i-Name", i+1]: blog.blogName,
                                   [NSString stringWithFormat:@"blog-%i-ID", i+1]: blog.blogID,
                                   [NSString stringWithFormat:@"blog-%i-URL", i+1]: blog.url};

        [metaData addEntriesFromDictionary:blogData];
    }

    if (!defaultAccount) {
        [self displayHelpshiftWindowOfType:helpshiftType
                              withUsername:nil
                                  andEmail:nil
                               andMetadata:metaData];
        return;
    }

    NSString *defaultAccountUserName = defaultAccount.username;
    [self showLoadingSpinner];

    [metaData addEntriesFromDictionary:@{@"WPCom Username": defaultAccount.username}];

    [defaultAccount.restApi GET:@"me"
                     parameters:nil
                        success:^(AFHTTPRequestOperation *operation, id responseObject) {
                            [self hideLoadingSpinner];

                            NSString *displayName = [responseObject stringForKey:ResponseKeyDisplayName];
                            NSString *emailAddress = [responseObject stringForKey:ResponseKeyEmail];
                            NSString *userID = [responseObject stringForKey:ResponseKeyID];

                            [Helpshift setUserIdentifier:userID];
                            [self displayHelpshiftWindowOfType:helpshiftType
                                                  withUsername:displayName
                                                      andEmail:emailAddress
                                                   andMetadata:metaData];

                        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                            [self hideLoadingSpinner];
                            [self displayHelpshiftWindowOfType:helpshiftType
                                                  withUsername:defaultAccountUserName
                                                      andEmail:nil
                                                   andMetadata:metaData];
                        }];
}

- (void)displayHelpshiftWindowOfType:(NSInteger)helpshiftType
                        withUsername:(NSString*)username
                            andEmail:(NSString*)email
                         andMetadata:(NSDictionary*)metaData
{
    [Helpshift setName:username andEmail:email];

    if (helpshiftType == HelpshiftWindowTypeFAQs) {
        [[Helpshift sharedInstance] showFAQs:self withOptions:@{HSCustomMetadataKey: metaData}];

    } else if (helpshiftType == HelpshiftWindowTypeConversation) {
        [[Helpshift sharedInstance] showConversation:self withOptions:@{HSCustomMetadataKey: metaData}];
    }
}

- (void)flagHelpshiftWasUsed
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:UserDefaultsHelpshiftWasUsed];
    [defaults synchronize];
}

- (UILabel *)newHelpshiftUnreadCountLabelWithCount:(NSInteger)count
{
    UILabel *helpshiftUnreadCountLabel = [[UILabel alloc] initWithFrame:FrameForHelpShiftUnreadCountLabel];
    helpshiftUnreadCountLabel.layer.masksToBounds = YES;
    helpshiftUnreadCountLabel.layer.cornerRadius = UnreadCountLabelCornerRadius;
    helpshiftUnreadCountLabel.textAlignment = NSTextAlignmentCenter;
    helpshiftUnreadCountLabel.backgroundColor = [WPStyleGuide newKidOnTheBlockBlue];
    helpshiftUnreadCountLabel.textColor = [UIColor whiteColor];
    helpshiftUnreadCountLabel.text = [NSString stringWithFormat:@"%ld", count];
    return helpshiftUnreadCountLabel;
}

- (void)helpshiftUnreadCountUpdated:(NSNotification *)notification
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:SettingsSectionFAQForums];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}


#pragma mark - TableView Delegate Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == SettingsSectionFAQForums) {
        return 2;
    }

    if (section == SettingsSectionActivityLog) {
        return 5;
    }

    if (section == SettingsSectionFeedback) {
        return self.feedbackEnabled ? 1 : 0;
    }

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WPTableViewCell *cell = nil;
    if (indexPath.section == SettingsSectionActivityLog && (indexPath.row == 1 || indexPath.row == 2)) {
        // Settings / Extra Debug
        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifierSwitchAccessory];

        if (cell == nil) {
            cell = [[WPTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifierSwitchAccessory];
        }

        UISwitch *switchAccessory = [[UISwitch alloc] initWithFrame:CGRectZero];
        switchAccessory.tag = indexPath.row;
        [switchAccessory addTarget:self action:@selector(handleCellSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchAccessory;
    } else if (indexPath.section == SettingsSectionFAQForums && indexPath.row == 0) {

        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifierBadgeAccessory];

        if (cell == nil) {
            cell = [[WPTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifierBadgeAccessory];
        }
    } else {

        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];

        if (cell == nil) {
            cell = [[WPTableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
        }
    }

    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    [WPStyleGuide configureTableViewCell:cell];

    if (indexPath.section == SettingsSectionFAQForums) {
        if (indexPath.row == 0) {
            cell.textLabel.text = NSLocalizedString(@"WordPress Help Center", @"A label. Tapping it opens the FAQ.");
            [WPStyleGuide configureTableViewActionCell:cell];
        } else if (indexPath.row == 1) {
            if ([HelpshiftUtils isHelpshiftEnabled]) {
                cell.textLabel.text = NSLocalizedString(@"Contact Us", @"A label. Tapping it opens a new screen forthe live-chat feature.");

                if ([HelpshiftUtils unreadNotificationCount] > 0) {
                    NSInteger count = [HelpshiftUtils unreadNotificationCount];
                    UILabel *helpshiftUnreadCountLabel = [self newHelpshiftUnreadCountLabelWithCount:count];
                    cell.accessoryView = helpshiftUnreadCountLabel;
                    cell.accessoryType = UITableViewCellAccessoryNone;
                } else {
                    cell.accessoryView = nil;
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                }
            } else {
                cell.textLabel.text = NSLocalizedString(@"WordPress Forums", @"A label. Tapping it opens a web page displaying the WordPress forums.");
                [WPStyleGuide configureTableViewActionCell:cell];
            }
        }
    } else if (indexPath.section == SettingsSectionFeedback) {
        cell.textLabel.text = NSLocalizedString(@"E-mail Support", @"A label. Tapping it opens a new email addressed to WordPress support.");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [WPStyleGuide configureTableViewActionCell:cell];
    } else if (indexPath.section == SettingsSectionActivityLog) {
        cell.textLabel.textAlignment = NSTextAlignmentLeft;

        if (indexPath.row == 0) {
            // App Version
            cell.textLabel.text = NSLocalizedString(@"Version", @"Preceds the version number of the app.");
            NSString *appVersion = [[NSBundle mainBundle] detailedVersionNumber];
#if DEBUG
            appVersion = [appVersion stringByAppendingString:@" (DEV)"];
#endif
            cell.detailTextLabel.text = appVersion;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Extra Debug", @"A label identifying the Extra Debug feature.");
            UISwitch *aSwitch = (UISwitch *)cell.accessoryView;
            aSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:ExtraDebugDefaultsKey];
        } else if (indexPath.row == 2) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Anonymous Usage Tracking", @"Setting for enabling anonymous usage tracking");
            UISwitch *aSwitch = (UISwitch *)cell.accessoryView;
            aSwitch.on = [[WordPressAppDelegate sharedInstance].analytics isTrackingUsage];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = NSLocalizedString(@"Activity Logs", @"A label. Tapping it displays a list of the app's saved activity logs.");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = NSLocalizedString(@"About", @"A label. Tapping it displays the app's About screen.");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    CGRect frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.view.bounds), 0.0);
    WPTableViewSectionFooterView *header = [[WPTableViewSectionFooterView alloc] initWithFrame:frame];
    header.title = [self titleForFooterInSection:section];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *title = [self titleForFooterInSection:section];
    return [WPTableViewSectionFooterView heightForTitle:title andWidth:CGRectGetWidth(self.view.bounds)];
}

- (NSString *)titleForFooterInSection:(NSInteger)section
{
    if (section == SettingsSectionFAQForums) {
        return NSLocalizedString(@"Visit the Help Center to get answers to common questions, or visit the Forums to ask new ones.", @"");
    } else if (section == SettingsSectionActivityLog) {
        return NSLocalizedString(@"The Extra Debug feature includes additional information in activity logs, and can help us troubleshoot issues with the app.", @"");
    }
    return nil;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SettingsSectionFAQForums) {
        if (indexPath.row == 0) {
            if ([HelpshiftUtils isHelpshiftEnabled]) {
                [self prepareAndDisplayHelpshiftWindowOfType:HelpshiftWindowTypeFAQs];
            } else {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://apps.wordpress.org/support/"]];
            }
        } else if (indexPath.row == 1) {
            if ([HelpshiftUtils isHelpshiftEnabled]) {
                [WPAnalytics track:WPAnalyticsStatSupportOpenedHelpshiftScreen];
                [self prepareAndDisplayHelpshiftWindowOfType:HelpshiftWindowTypeConversation];
            } else {
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://ios.forums.wordpress.org"]];
            }
        }
    } else if (indexPath.section == SettingsSectionFeedback) {
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *mailComposeViewController = [self feedbackMailViewController];
            [self presentViewController:mailComposeViewController animated:YES completion:nil];
        } else {
            [WPError showAlertWithTitle:NSLocalizedString(@"Feedback", @"A title of a prompt, giving feedback on an action taken by the user.")
                                message:NSLocalizedString(@"Your device is not configured to send e-mail.", @"A short error message warning that the user's device is not set up to send email.")];
        }
    } else if (indexPath.section == SettingsSectionActivityLog) {
        if (indexPath.row == 3) {
            ActivityLogViewController *activityLogViewController = [[ActivityLogViewController alloc] init];
            [self.navigationController pushViewController:activityLogViewController animated:YES];

        } else if (indexPath.row == 4) {
            NSString *nibName = NSStringFromClass([AboutViewController class]);
            AboutViewController *aboutViewController = [[AboutViewController alloc] initWithNibName:nibName bundle:nil];
            [self.navigationController pushViewController:aboutViewController animated:YES];

        }
    }
}


#pragma mark - SupportViewController methods

- (void)handleCellSwitchChanged:(id)sender
{
    UISwitch *aSwitch = (UISwitch *)sender;

    if (aSwitch.tag == 1) {
        [[NSUserDefaults standardUserDefaults] setBool:aSwitch.on forKey:ExtraDebugDefaultsKey];
        [NSUserDefaults resetStandardUserDefaults];
    } else {
        [[WordPressAppDelegate sharedInstance].analytics setTrackingUsage:aSwitch.on];
    }
}

- (MFMailComposeViewController *)feedbackMailViewController
{
    NSString *appVersion = [[NSBundle mainBundle] detailedVersionNumber];
    NSString *device = [UIDeviceHardware platformString];
    NSString *locale = [[NSLocale currentLocale] localeIdentifier];
    NSString *iosVersion = [[UIDevice currentDevice] systemVersion];

    NSMutableString *messageBody = [NSMutableString string];
    [messageBody appendFormat:@"\n\n==========\n%@\n\n", NSLocalizedString(@"Please leave your comments above this line.", @"")];
    [messageBody appendFormat:@"Device: %@\n", device];
    [messageBody appendFormat:@"App Version: %@\n", appVersion];
    [messageBody appendFormat:@"Locale: %@\n", locale];
    [messageBody appendFormat:@"OS Version: %@\n", iosVersion];

    WordPressAppDelegate *delegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
    DDFileLogger *fileLogger = delegate.logger.fileLogger;
    NSArray *logFiles = fileLogger.logFileManager.sortedLogFileInfos;

    MFMailComposeViewController *mailComposeViewController = [[MFMailComposeViewController alloc] init];
    mailComposeViewController.mailComposeDelegate = self;

    [mailComposeViewController setMessageBody:messageBody isHTML:NO];
    [mailComposeViewController setSubject:@"WordPress for iOS Help Request"];
    [mailComposeViewController setToRecipients:@[@"mobile-support@automattic.com"]];

    if (logFiles.count > 0) {
        DDLogFileInfo *logFileInfo = (DDLogFileInfo *)logFiles[0];
        NSData *logData = [NSData dataWithContentsOfFile:logFileInfo.filePath];

        [mailComposeViewController addAttachmentData:logData mimeType:@"text/plain" fileName:@"current_log.txt"];
    }

    mailComposeViewController.modalPresentationCapturesStatusBarAppearance = NO;

    return mailComposeViewController;
}

- (void)dismiss
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - MFMailComposeViewControllerDelegate methods

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [self dismiss];
}

@end

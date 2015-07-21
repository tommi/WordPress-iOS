#import "WPBlogTableViewCell.h"
#import "WPBlogTableViewCellViewModel.h"

#import "UIImageView+Gravatar.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@interface WPBlogTableViewCell ()
@property (nonatomic) WPBlogTableViewCellViewModel *viewModel;
@end

@implementation WPBlogTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    // Ignore the style argument, override with subtitle style.
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupCell];
    }
    return self;
}

- (void)setupCell
{
    if (!self.visibilitySwitch) {
        UISwitch *visibilitySwitch = [UISwitch new];

        self.editingAccessoryView = visibilitySwitch;
        self.visibilitySwitch = visibilitySwitch;
    }

    [WPStyleGuide configureTableViewSmallSubtitleCell:self];
    self.viewModel = [WPBlogTableViewCellViewModel new];
    RAC(self.textLabel, text) = [RACSignal
                                 combineLatest:@[ RACObserve(self.viewModel, title), RACObserve(self.viewModel, url)]
                                 reduce:^(NSString *title, NSString *url){
                                     return (title.length > 0) ? title : url;
                                 }];
    RAC(self.textLabel, textColor) = [RACObserve(self.viewModel, visible) map:^UIColor *(NSNumber *visible) {
        return visible.boolValue ? [WPStyleGuide whisperGrey] : [WPStyleGuide readGrey];
    }];
    RAC(self.detailTextLabel, text) = [RACSignal
                                       combineLatest:@[ RACObserve(self.viewModel, title), RACObserve(self.viewModel, url)]
                                       reduce:^(NSString *title, NSString *url){
                                           return (title.length > 0) ? url : @"";
                                       }];
    RAC(self.detailTextLabel, textColor) = [RACObserve(self.viewModel, visible) map:^UIColor *(NSNumber *visible) {
        return visible.boolValue ? [WPStyleGuide whisperGrey] : [WPStyleGuide readGrey];
    }];

    [RACObserve(self.viewModel, icon) subscribeNext:^(NSString *icon) {
        [self.imageView setImageWithSiteIcon:icon];
    }];
    RAC(self.visibilitySwitch, on) = RACObserve(self.viewModel, visible);

    [[self.visibilitySwitch
      rac_signalForControlEvents:UIControlEventValueChanged]
     subscribeNext:^(UISwitch *swtch) {
         [self.viewModel.visibilitySwitchCommand execute:swtch];
     }];
}

@end

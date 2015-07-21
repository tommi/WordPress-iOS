#import "WPTableViewCell.h"

@class WPBlogTableViewCellViewModel;
@interface WPBlogTableViewCell : WPTableViewCell

@property (nonatomic, readonly) WPBlogTableViewCellViewModel *viewModel;
@property (nonatomic, weak) UISwitch *visibilitySwitch;

@end

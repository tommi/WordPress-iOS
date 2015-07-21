#import "BlogModel.h"

@implementation BlogModel

- (instancetype)initWithTitle:(NSString *)title url:(NSString *)url icon:(UIImage *)icon visible:(BOOL)visible
{
    if (!(self = [super init])) {
        return nil;
    }
    _title = title;
    _url = url;
    _icon = icon;
    _visible = visible;
    return self;
}

@end

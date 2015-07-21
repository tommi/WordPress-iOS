#import <Foundation/Foundation.h>

@interface BlogModel : NSObject

- (instancetype)initWithTitle:(NSString *)title url:(NSString *)url icon:(UIImage *)icon visible:(BOOL)visible;

@property (readonly) NSString *title;
@property (readonly) NSString *url;
@property (readonly) UIImage *icon;
@property (readonly, assign) BOOL visible;
@end

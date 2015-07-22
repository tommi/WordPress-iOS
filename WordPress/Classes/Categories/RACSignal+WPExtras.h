#import <Foundation/Foundation.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@interface RACSignal (WPExtras)

- (RACSignal *)bufferAndThrottleWithTime:(NSTimeInterval)interval;
- (RACSignal *)bufferAndThrottleWithTime:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler;

@end

#import "RACSignal+WPExtras.h"

@implementation RACSignal (WPExtras)

/**
 *  This combines the RxCocoa throttle and buffer operations. As the signal continues to receive values
 *  this code will reset the timer specified by `interval` and once the `interval` clears without any
 *  new values coming in it will send the aggregated values as a `RACTuple`
 *
 *  @param interval  the time to throttle and buffer a series of sent signals.
 *
 *  @return returns a signal which sends RACTuples of the buffered values at each interval. When the receiver completes, any currently-buffered values will be sent immediately.
 */
- (RACSignal *)bufferAndThrottleWithTime:(NSTimeInterval)interval
{
    return [self bufferAndThrottleWithTime:interval onScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityHigh]];
}

/**
 *  This combines the RxCocoa throttle and buffer operations. As the signal continues to receive values
 *  this code will reset the timer specified by `interval` and once the `interval` clears without any
 *  new values coming in it will send the aggregated values as a `RACTuple`
 *
 *  @param interval  the time to throttle and buffer a series of sent signals.
 *  @param scheduler the scheduler upon which the returned signal will deliver its values. This must not be nil or [RACScheduler immediateScheduler].
 *
 *  @return returns a signal which sends RACTuples of the buffered values at each interval on `scheduler`. When the receiver completes, any currently-buffered values will be sent immediately.
 */
- (RACSignal *)bufferAndThrottleWithTime:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler
{
	NSParameterAssert(interval >= 0);
	NSParameterAssert(scheduler != RACScheduler.immediateScheduler);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

        __block NSMutableArray *values = [@[] mutableCopy];
		RACSerialDisposable *timerDisposable = [[RACSerialDisposable alloc] init];
        
        void (^resetTimer)() = ^{
            @synchronized(values){
                [timerDisposable.disposable dispose];
            };
        };
        
        void (^flushValues)() = ^{
            @synchronized (values) {
                [timerDisposable.disposable dispose];
                
                if (values.count == 0) {
                    return;
                }
                
                RACTuple *tuple = [RACTuple tupleWithObjectsFromArray:values];
                [values removeAllObjects];
                [subscriber sendNext:tuple];
                
                [values removeAllObjects];
            }
        };

		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			@synchronized (values) {
                resetTimer();
                
				[values addObject:x ?: RACTupleNil.tupleNil];
                
				timerDisposable.disposable = [scheduler afterDelay:interval schedule:^{
                    flushValues();
				}];
			}
		} error:^(NSError *error) {
			[compoundDisposable dispose];
			[subscriber sendError:error];
		} completed:^{
            flushValues();
			[subscriber sendCompleted];
		}];

		[compoundDisposable addDisposable:selfDisposable];
        [compoundDisposable addDisposable:timerDisposable];
		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -bufferAndThrottleWithTime: %f onScheduler: %@", self.name, (double)interval, scheduler];
}

@end

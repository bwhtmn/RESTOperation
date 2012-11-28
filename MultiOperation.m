//
//  MultiOperation.m
//  Musicism
//
//  Created by Brent Whitman on 08-24-12.
//  Copyright (c) 2012 Arteku. All rights reserved.
//

#import "MultiOperation.h"

#import "RESTOperation.h"

@implementation MultiOperation

-(id)initWithFirstOperations:(NSArray*)first SubsequentOperations:(NSArray*)subsequent {
    [super init];
    
    _firstOps = [first retain];
    _subsequentOps = [subsequent retain];
    for (NSOperation* op in _firstOps) {
        [op addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:nil];
        [op addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:nil];
    }
    for (NSOperation* op in _subsequentOps) {
        [op addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:nil];
        [op addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:nil];
    }
    
    _executing = NO;
    _finished = NO;
    
    return self;
}

-(void)dealloc {
    [_firstOps release];
    [_subsequentOps release];
    
    [super dealloc];
}

-(void)start {
    [super start];
    
    for (NSOperation* operation in _firstOps) {
        [operation start];
    }
}

-(void)cancel {
    [super cancel];
    
    for (NSOperation* operation in _firstOps) {
        [operation cancel];
    }
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    _executing = NO;
    for (NSOperation* operation in _firstOps) {
        _executing = _executing || [operation isExecuting];
    }
    return _executing;
}

- (BOOL)isFinished {
    _finished = YES;
    for (NSOperation* operation in _firstOps) {
        _finished = _finished && [operation isFinished];
    }
    return _finished;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"isExecuting"]) {
        if (_executing != [self isExecuting]) {
            [self willChangeValueForKey:@"isExecuting"];
            [self didChangeValueForKey:@"isExecuting"];
        }
    }
    else if ([keyPath isEqualToString:@"isFinished"]) {
        if (_finished != [self isFinished]) {
            [self willChangeValueForKey:@"isFinished"];
            [self didChangeValueForKey:@"isFinished"];
        }
    }
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey {
    BOOL automatic = NO;
    if ([theKey isEqualToString:@"isExecuting"] || [theKey isEqualToString:@"isFinished"]) {
        automatic = NO;
    } else {
        automatic=[super automaticallyNotifiesObserversForKey:theKey];
    }
    return automatic;
}



@end

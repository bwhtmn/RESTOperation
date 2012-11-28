//
//  MultiOperation.h
//  Musicism
//
//  Created by Brent Whitman on 08-24-12.
//  Copyright (c) 2012 Arteku. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MultiOperation : NSOperation {
    NSArray* _firstOps;
    NSArray* _subsequentOps;
    
    BOOL _executing;
    BOOL _finished;
}

-(id)initWithFirstOperations:(NSArray*)first SubsequentOperations:(NSArray*)subsequent;
-(void)dealloc;


@end

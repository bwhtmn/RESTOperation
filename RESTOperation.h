//
//  RESTOperation.h
//  Musicism
//
//  Created by Brent Whitman on 22/01/12.
//  Copyright (c) 2012 Arteku. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ASIHTTPRequestDelegate.h"

@class ASIHTTPRequest;

@interface RESTOperation : NSOperation <ASIHTTPRequestDelegate> {
    NSString* datumName; //only for debugging
    id targetObject;

    SEL createUrlSelector; // returns NSString* 
    SEL postDataSelector; // returns NSData* 
	SEL parseResultsSelector; // returns id (nil == failure), takes parameters NSData* html, NSData* raw

    // DON'T CREATE LOOPS! (or cancel will be infinite)
    NSMutableArray* onSuccess; // array of RESTOperation objects
    NSMutableArray* onFailure; // array of RESTOperation objects

	NSURL* url;
    ASIHTTPRequest* httpRequest;
    NSTimer* timer;
    
    BOOL _executing;
    BOOL _finished;
}

// Selector format:
//
//-(NSString*)createURL;
//-(NSString*)postData;
//-(id)parse:(NSData*)htmlData Parse:(NSData*)rawData;
//

-(id)initWithObject:(id)object createURL:(SEL)create postData:(SEL)post parse:(SEL)parse name:(NSString*)name;
-(void)dealloc;

-(void)addSuccessAction:(RESTOperation*)successAction;
-(void)addFailureAction:(RESTOperation*)failureAction;

-(void)start;
-(void)cancel;

+(void) setRateLimit:(float)rateLimitSeconds forBaseURL:(NSString*)url;

+(NSString*) URLEncodedString_ch:(NSString*)sourceString;
+(NSString*) PercentEncodedString:(NSString*)sourceString;

@end

//
//  RESTOperation.m
//  Musicism
//
//  Created by Brent Whitman on 22/01/12.
//  Copyright (c) 2012 Arteku. All rights reserved.
//

#import "RESTOperation.h"

#import "ASIHTTPRequest.h"
#import "ASIHTTPRequest+OAuth.h"
#import "ASIDownloadCache.h"
#import "JSONKit.h"
#import "Reachability.h"


#ifdef TESTING
#define RESTLog NSLog
#else
static void RESTLog(NSString* str, ...) {
}
#endif


static NSMutableDictionary* rateLimits = nil;
static NSMutableDictionary* lastRequestTimes = nil;


@interface RESTOperation (PrivateMethods)
// method declarations

- (void) setExecutingState:(BOOL)newState;
- (void) setFinishedState:(BOOL)newState;

@end


@implementation RESTOperation


-(id)initWithObject:(id)object createURL:(SEL)create postData:(SEL)post parse:(SEL)parse name:(NSString*)name {
    self = [super init];
    
    _executing = NO;
    _finished = NO;
    
    targetObject = object;
    createUrlSelector = create;
    postDataSelector = post;
    parseResultsSelector = parse;
    datumName = [name retain];
    
    onSuccess = nil;
    onFailure = nil;
    url = nil;
    httpRequest = nil;
    timer = nil;
        
    return self;
}


- (void)dealloc {
    [datumName release];
    [url release];
    [timer release];
    [httpRequest release];
    
    [super dealloc];
}


-(void)addSuccessAction:(RESTOperation*)successAction {
    if (onSuccess == nil) {
        onSuccess = [[NSMutableArray alloc] initWithCapacity:1];
    }
    [onSuccess addObject:successAction];
    [successAction addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:nil];
    [successAction addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:nil];
}


-(void)addFailureAction:(RESTOperation*)failureAction {
    if (onFailure == nil) {
        onFailure = [[NSMutableArray alloc] initWithCapacity:1];
    }
    [onFailure addObject:failureAction];
    [failureAction addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:nil];
    [failureAction addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:nil];
}

static NSString* OAUTH_CONSUMER_KEY = @"etV0M8El01YgcT0eo0PkCw";
static NSString* OAUTH_CONSUMER_SECRET = @"bHgPHWt4VxUA8kWrNH67UfyDU31G1KVJEqnBB6cTg";
static NSString* OAUTH_ACCESS_TOKEN = @"480051177-h14dXYK8djxVr4fcPj9B6tJFeKPj5g3iPmzZILkV";
static NSString* OAUTH_ACCESS_TOKEN_SECRET = @"aYufR0JFa4SgZYYaNFcNe8gTJL7kVubKP0fhq96A6x0";
static NSString* OAUTH_HTTP_HEADER_FIELD = @"Authorization";


#pragma mark - NSOperation overridden methods

-(void)start {
    // Check for early cancellation
    if ([self isCancelled]) {
        [self setExecutingState:NO];
        [self setFinishedState:YES];
        return;
    }
    
    [self setExecutingState:YES];

    // Get URL from selector
    NSString* urlToFetch = [targetObject performSelector:createUrlSelector];
	NSString* encodedURL = [RESTOperation URLEncodedString_ch:urlToFetch];
	url = [NSURL URLWithString:encodedURL];
	
	httpRequest = [ASIHTTPRequest requestWithURL:url];
    httpRequest.defaultResponseEncoding = NSUTF8StringEncoding;
	httpRequest.delegate = self;
    httpRequest.cacheStoragePolicy = ASICachePermanentlyCacheStoragePolicy;
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    httpRequest.shouldContinueWhenAppEntersBackground = YES;
#endif

    // Add post data if there is any (also changes from a GET to a POST automatically)
    if (postDataSelector != nil) {
        [httpRequest appendPostData:[targetObject performSelector:postDataSelector]];
        [httpRequest addRequestHeader:@"Content-Type" value:@"application/x-www-form-urlencoded"];
    }
    
    // For api.twitter.com urls, authorize using oAuth
    NSString* host = [url host];    
    if ([host isEqualToString:@"api.twitter.com"] ) {
        [httpRequest signRequestWithClientIdentifier:OAUTH_CONSUMER_KEY secret:OAUTH_CONSUMER_SECRET
                                     tokenIdentifier:OAUTH_ACCESS_TOKEN secret:OAUTH_ACCESS_TOKEN_SECRET
                                         usingMethod:ASIOAuthHMAC_SHA1SignatureMethod];
    }
    
    RESTLog(@"START\t%@ : %@", datumName, encodedURL);
    
    NSTimeInterval delay = 0.0;
    if (rateLimits) {
        NSNumber* hostRateLimit = [rateLimits valueForKey:host];
        if (hostRateLimit && lastRequestTimes) {
            @synchronized(lastRequestTimes) {
                NSDate* lastRequest = [lastRequestTimes valueForKey:host];
                if (lastRequest) {
                    NSDate* executionTime = [NSDate dateWithTimeInterval:[hostRateLimit floatValue] sinceDate:lastRequest];
                    delay = [executionTime timeIntervalSinceNow];
                    if (delay < 0.0) {
                        delay = 0.0;
                    }
                }
                RESTLog(@"delay = %f", delay);
                // Set new request time
                [lastRequestTimes setValue:[NSDate dateWithTimeIntervalSinceNow:delay] forKey:host];
            }
        }
    }
    
    if (delay > 0.0) {
        NSRunLoop* mainLoop = [NSRunLoop mainRunLoop];
        timer = [NSTimer timerWithTimeInterval:delay target:httpRequest selector:@selector(startAsynchronous) userInfo:nil repeats:NO];
        [mainLoop addTimer:timer forMode:NSRunLoopCommonModes];
    }
    else {
        [httpRequest startAsynchronous];
    }
}

-(void)cancel {
    [super cancel];

    if (httpRequest) {
        [httpRequest clearDelegatesAndCancel];
        httpRequest = nil;
        RESTLog(@"CANCEL\t%@", datumName);
    }

    // Recursive cancelling of post-actions
    for (RESTOperation* successAction in onSuccess) {
        [successAction cancel];
    }
    for (RESTOperation* failureAction in onFailure) {
        [failureAction cancel];
    }
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    BOOL anyExecuting = _executing;

    for (RESTOperation* successAction in onSuccess) {
        anyExecuting = anyExecuting || [successAction isExecuting];
    }
    for (RESTOperation* failureAction in onFailure) {
        anyExecuting = anyExecuting || [failureAction isExecuting];
    }
    
    return anyExecuting;
}

- (BOOL)isFinished {
    BOOL allSuccessFinished = YES;
    for (RESTOperation* successAction in onSuccess) {
        allSuccessFinished = allSuccessFinished && [successAction isFinished];
    }
    
    BOOL allFailureFinished = YES;
    for (RESTOperation* failureAction in onFailure) {
        allFailureFinished = allFailureFinished && [failureAction isFinished];
    }

    return _finished && (allSuccessFinished || allFailureFinished);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"isExecuting"]) {
        [self willChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isExecuting"];
    }
    else if ([keyPath isEqualToString:@"isFinished"]) {
        [self willChangeValueForKey:@"isFinished"];
        [self didChangeValueForKey:@"isFinished"];
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

- (void) setExecutingState:(BOOL)newState {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = newState;
    [self didChangeValueForKey:@"isExecuting"];
}

- (void) setFinishedState:(BOOL)newState {
    [self willChangeValueForKey:@"isFinished"];
    _finished = newState;
    [self didChangeValueForKey:@"isFinished"];
}


#pragma mark - Request Result methods

-(void)requestFinished:(ASIHTTPRequest*)request {
    httpRequest = nil;
    
	NSString* response = [request responseString];
	NSData* htmlData = [response dataUsingEncoding:NSUTF8StringEncoding];

    NSData* rawData = [request responseData];

    // parse the resulting data using the selector
    id success = [targetObject performSelector:parseResultsSelector withObject:htmlData withObject:rawData];
    
    if (success != nil) {
        RESTLog(@" SUCCESS\t%@", datumName);
        for (RESTOperation* successAction in onSuccess) {
            [successAction start];
        }
    }
    else {
        RESTLog(@" FAIL\t\t%@", datumName);
        //RESTLog(response);
        for (RESTOperation* failureAction in onFailure) {
            [failureAction start];
        }
    }
    
    [self setExecutingState:NO];
    [self setFinishedState:YES];
}

-(void)requestFailed:(ASIHTTPRequest*)request {
    static NetworkStatus prevStatus = -1;
    
    httpRequest = nil;
    
    RESTLog(@" ERROR\t\t%@", datumName);
	NSError *error = [request error];
	RESTLog(@"Error loading %@", [request url]);
	RESTLog(@"  Description: %@", [error localizedDescription]);
	RESTLog(@"  Failure Reason: %@", [error localizedFailureReason]);

    Reachability* curReach = [Reachability reachabilityForInternetConnection];
    NetworkStatus curStatus = [curReach currentReachabilityStatus];
    if (curStatus == kNotReachable && prevStatus != curStatus) {
        // TODO: show alert
        RESTLog(@"Not Reachable!");
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"This app can't connect to the internet right now"
                                                        message:@"Check that Wi-Fi and/or cellular data are turned on in Settings."
                                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
    prevStatus = curStatus;

    for (RESTOperation* failureAction in onFailure) {
        [failureAction start];
    }
    
    [self setExecutingState:NO];
    [self setFinishedState:YES];
}

+(void) setRateLimit:(float)rateLimitSeconds forBaseURL:(NSString*)url {
    if (rateLimits == nil) {
        rateLimits = [[NSMutableDictionary alloc] init];
    }
    if (lastRequestTimes == nil) {
        lastRequestTimes = [[NSMutableDictionary alloc] init];
    }
    
    [rateLimits setValue:[NSNumber numberWithFloat:rateLimitSeconds] forKey:url];
}


#pragma mark - Encoding Helper functions

+(NSString*) URLEncodedString_ch:(NSString*)sourceString {
    NSString* spacesToPluses = [sourceString stringByReplacingOccurrencesOfString:@" " withString:@"+"];
    
	CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, 
                                                                    (CFStringRef)spacesToPluses, 
                                                                    CFSTR("%"), NULL, kCFStringEncodingUTF8);
	NSString * output = NSMakeCollectable((NSString*)urlString);
	[output autorelease];
	
    return output;
}

+(NSString*) PercentEncodedString:(NSString*)sourceString {
	CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, 
                                                                    (CFStringRef)sourceString, 
                                                                    NULL, CFSTR("%!*'();:@&=+$,/?#[]"), kCFStringEncodingUTF8);
	NSString * output = NSMakeCollectable((NSString*)urlString);
	[output autorelease];
	
    return output;
}




@end

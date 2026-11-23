// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
#import "WebProbe.h"
#import <dlfcn.h>

// What the probe calls on the private classes (declared here: tvOS's SDK has no headers for them)
@protocol ProbeWKConfiguration <NSObject>
@property (nonatomic) BOOL allowsInlineMediaPlayback;
@end

@protocol ProbeWKWebView <NSObject>
- (instancetype)initWithFrame:(CGRect)frame configuration:(id)configuration;
- (nullable id)loadHTMLString:(NSString *)string baseURL:(nullable NSURL *)baseURL;
- (nullable id)loadRequest:(NSURLRequest *)request;
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^_Nullable)(id _Nullable, NSError *_Nullable))handler;
- (void)stopLoading;
@property (nullable, nonatomic, copy) NSString *customUserAgent;
@end

@protocol ProbeUIWebView <NSObject>
- (instancetype)initWithFrame:(CGRect)frame;
- (void)loadHTMLString:(NSString *)string baseURL:(nullable NSURL *)baseURL;
- (void)loadRequest:(NSURLRequest *)request;
- (nullable NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
- (void)stopLoading;
@end

@implementation WebProbe {
    UIView *_view;
}

+ (NSString *)loadWebKit {
    NSArray<NSString *> *paths = @[
        @"/System/Library/Frameworks/WebKit.framework/WebKit",
        @"/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
        @"/System/Library/Frameworks/WebKitLegacy.framework/WebKitLegacy",
        @"/System/Library/PrivateFrameworks/WebKitLegacy.framework/WebKitLegacy",
        @"/System/Library/PrivateFrameworks/WebCore.framework/WebCore",
    ];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    for (NSString *path in paths) {
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        NSString *name = path.lastPathComponent;
        if ([path containsString:@"PrivateFrameworks"]) name = [@"private " stringByAppendingString:name];
        if (handle) {
            [said addObject:[name stringByAppendingString:@": loaded"]];
        } else {
            const char *err = dlerror();
            [said addObject:[NSString stringWithFormat:@"%@: no (%s)", name, err ? err : "?"]];
        }
    }
    return [said componentsJoinedByString:@"\n"];
}

+ (BOOL)hasClass:(NSString *)name {
    return NSClassFromString(name) != nil;
}

- (instancetype)initWithKind:(NSString *)kind window:(UIWindow *)window userAgent:(NSString *)userAgent error:(NSString **)error {
    if (!(self = [super init])) return nil;
    _kind = [kind copy];
    CGRect frame = window.bounds;
    @try {
        if ([kind isEqualToString:@"WKWebView"]) {
            Class configClass = NSClassFromString(@"WKWebViewConfiguration");
            Class viewClass = NSClassFromString(@"WKWebView");
            if (!configClass || !viewClass) {
                if (error) *error = @"WKWebView isn't on this Apple TV";
                return nil;
            }
            id<ProbeWKConfiguration> config = [[configClass alloc] init];
            if ([config respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) config.allowsInlineMediaPlayback = YES;
            id<ProbeWKWebView> web = [(id<ProbeWKWebView>)[viewClass alloc] initWithFrame:frame configuration:config];
            if (!web) {
                if (error) *error = @"WKWebView wouldn't start";
                return nil;
            }
            if ([web respondsToSelector:@selector(setCustomUserAgent:)]) web.customUserAgent = userAgent;
            _view = (UIView *)web;
        } else {
            Class viewClass = NSClassFromString(@"UIWebView");
            if (!viewClass) {
                if (error) *error = @"UIWebView isn't on this Apple TV";
                return nil;
            }
            [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"UserAgent": userAgent }];
            id<ProbeUIWebView> web = [(id<ProbeUIWebView>)[viewClass alloc] initWithFrame:frame];
            if (!web) {
                if (error) *error = @"UIWebView wouldn't start";
                return nil;
            }
            _view = (UIView *)web;
        }
    } @catch (NSException *exception) {
        if (error) *error = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
        return nil;
    }
    // In the window (a page that isn't can be paused), but out of sight, as in the iPhone app
    _view.alpha = 0.01;
    _view.userInteractionEnabled = NO;
    [window insertSubview:_view atIndex:0];
    return self;
}

- (void)loadHTML:(NSString *)html baseURL:(NSURL *)baseURL {
    if ([_kind isEqualToString:@"WKWebView"]) [(id<ProbeWKWebView>)_view loadHTMLString:html baseURL:baseURL];
    else [(id<ProbeUIWebView>)_view loadHTMLString:html baseURL:baseURL];
}

- (void)loadURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    if ([_kind isEqualToString:@"WKWebView"]) [(id<ProbeWKWebView>)_view loadRequest:request];
    else [(id<ProbeUIWebView>)_view loadRequest:request];
}

- (void)evaluate:(NSString *)script completion:(void (^)(NSString *, NSString *))completion {
    @try {
        if ([_kind isEqualToString:@"WKWebView"]) {
            [(id<ProbeWKWebView>)_view evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
                if (error) completion(nil, error.userInfo[@"WKJavaScriptExceptionMessage"] ?: error.localizedDescription);
                else completion(result == nil || result == [NSNull null] ? @"" : [NSString stringWithFormat:@"%@", result], nil);
            }];
        } else {
            NSString *result = [(id<ProbeUIWebView>)_view stringByEvaluatingJavaScriptFromString:script];
            completion(result ?: @"", nil);
        }
    } @catch (NSException *exception) {
        completion(nil, [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
}

- (void)tearDown {
    @try {
        if ([_view respondsToSelector:@selector(stopLoading)]) [(id<ProbeUIWebView>)_view stopLoading];
    } @catch (NSException *exception) {}
    [_view removeFromSuperview];
    _view = nil;
}

@end

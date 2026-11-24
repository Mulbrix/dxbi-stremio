// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
#import "DxWebView.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// What's used of WebKit's classes, declared here (tvOS's SDK has no WebKit headers)
@protocol DxWKConfiguration <NSObject>
@property (nonatomic) BOOL allowsInlineMediaPlayback;
@property (nonatomic) NSUInteger mediaTypesRequiringUserActionForPlayback;
@property (nonatomic) BOOL allowsPictureInPictureMediaPlayback;
@property (nonatomic) BOOL allowsAirPlayForMediaPlayback;
@property (nonatomic, strong) id websiteDataStore;
@property (nonatomic, strong) id userContentController;
@end

@protocol DxWKWebsiteDataStoreClass <NSObject>
+ (id)defaultDataStore;
@end

@protocol DxWKUserContentController <NSObject>
- (void)addScriptMessageHandler:(id)handler name:(NSString *)name;
- (void)addUserScript:(id)script;
@end

@protocol DxWKUserScript <NSObject>
- (instancetype)initWithSource:(NSString *)source injectionTime:(NSInteger)injectionTime forMainFrameOnly:(BOOL)forMainFrameOnly;
@end

@protocol DxWKWebView <NSObject>
- (instancetype)initWithFrame:(CGRect)frame configuration:(id)configuration;
- (nullable id)loadRequest:(NSURLRequest *)request;
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^_Nullable)(id _Nullable, NSError *_Nullable))handler;
@property (nullable, nonatomic, copy) NSString *customUserAgent;
@property (nullable, nonatomic, weak) id navigationDelegate;
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, getter=isInspectable) BOOL inspectable;
@end

@protocol DxWKScriptMessage <NSObject>
@property (nonatomic, readonly) id body;
@property (nonatomic, readonly) id frameInfo;
@end

@protocol DxWKFrameInfo <NSObject>
@property (nonatomic, readonly, getter=isMainFrame) BOOL mainFrame;
@property (nonatomic, readonly) id securityOrigin;
@end

@protocol DxWKSecurityOrigin <NSObject>
@property (nonatomic, readonly) NSString *host;
@end

@protocol DxWKNavigationAction <NSObject>
@property (nonatomic, readonly) NSURLRequest *request;
@property (nullable, nonatomic, readonly) id targetFrame;
@end

// WebKit's enum values (WKNavigationActionPolicy, WKUserScriptInjectionTime)
static const NSInteger DxWKNavigationActionPolicyCancel = 0;
static const NSInteger DxWKNavigationActionPolicyAllow = 1;
static const NSInteger DxWKUserScriptInjectionTimeAtDocumentStart = 0;

@interface DxWebView ()
- (void)received:(id)message;
- (NSInteger)decide:(id)action;
- (void)terminated;
@end

/** Hears from WebKit for the web view (WebKit keeps it; it only points back weakly) */
@interface DxWebHandler : NSObject
@property (nonatomic, weak) DxWebView *owner;
@end

@implementation DxWebHandler
- (void)userContentController:(id)controller didReceiveScriptMessage:(id)message {
    [self.owner received:message];
}
- (void)webView:(id)webView decidePolicyForNavigationAction:(id)action decisionHandler:(void (^)(NSInteger))decisionHandler {
    DxWebView *owner = self.owner;
    decisionHandler(owner ? [owner decide:action] : DxWKNavigationActionPolicyAllow);
}
- (void)webViewWebContentProcessDidTerminate:(id)webView {
    [self.owner terminated];
}
@end

@implementation DxWebView {
    id<DxWKWebView> _web;
    DxWebHandler *_handler;
}

static NSString *problem;
static BOOL looked;

+ (NSString *)unavailableReason {
    if (looked) return problem;
    looked = YES;
    if (!NSClassFromString(@"WKWebView")) {
        for (NSString *path in @[@"/System/Library/Frameworks/WebKit.framework/WebKit", @"/System/Library/PrivateFrameworks/WebKit.framework/WebKit"]) {
            if (dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) break;
        }
    }
    for (NSString *name in @[@"WKWebView", @"WKWebViewConfiguration", @"WKUserScript", @"WKWebsiteDataStore"]) {
        if (!NSClassFromString(name)) {
            const char *err = dlerror();
            problem = [NSString stringWithFormat:@"This Apple TV has no %@ (%s)", name, err ? err : "not found"];
            return problem;
        }
    }
    // (so WebKit sees the handler as its own kind)
    for (NSString *name in @[@"WKScriptMessageHandler", @"WKNavigationDelegate"]) {
        Protocol *p = objc_getProtocol(name.UTF8String);
        if (p) class_addProtocol([DxWebHandler class], p);
    }
    return nil;
}

- (instancetype)initWithFrame:(CGRect)frame userScript:(NSString *)script userAgent:(NSString *)userAgent messageName:(NSString *)name {
    if ([DxWebView unavailableReason]) return nil;
    if (!(self = [super init])) return nil;
    @try {
        id<DxWKConfiguration> config = [[NSClassFromString(@"WKWebViewConfiguration") alloc] init];
        if ([config respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) config.allowsInlineMediaPlayback = YES;
        // Nothing in the page plays by itself (its own player, sounds): the app's player does the playing
        if ([config respondsToSelector:@selector(setMediaTypesRequiringUserActionForPlayback:)]) config.mediaTypesRequiringUserActionForPlayback = NSUIntegerMax;
        if ([config respondsToSelector:@selector(setAllowsPictureInPictureMediaPlayback:)]) config.allowsPictureInPictureMediaPlayback = NO;
        if ([config respondsToSelector:@selector(setAllowsAirPlayForMediaPlayback:)]) config.allowsAirPlayForMediaPlayback = NO;
        Class store = NSClassFromString(@"WKWebsiteDataStore");
        if ([store respondsToSelector:@selector(defaultDataStore)]) config.websiteDataStore = [(Class<DxWKWebsiteDataStoreClass>)store defaultDataStore];

        _handler = [DxWebHandler new];
        _handler.owner = self;
        id<DxWKUserContentController> controller = config.userContentController;
        [controller addScriptMessageHandler:_handler name:name];
        id<DxWKUserScript> start = [(id<DxWKUserScript>)[NSClassFromString(@"WKUserScript") alloc] initWithSource:script injectionTime:DxWKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [controller addUserScript:start];

        _web = [(id<DxWKWebView>)[NSClassFromString(@"WKWebView") alloc] initWithFrame:frame configuration:config];
        if (!_web) return nil;
        _web.navigationDelegate = _handler;
        _web.customUserAgent = userAgent;
        if ([_web respondsToSelector:@selector(scrollView)]) _web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#if DEBUG
        if ([_web respondsToSelector:@selector(setInspectable:)]) _web.inspectable = YES;
#endif
        UIView *view = (UIView *)_web;
        view.opaque = NO;
        view.backgroundColor = UIColor.blackColor;
        // Out of sight and out of reach: the remote's focus never goes to the page
        view.userInteractionEnabled = NO;
    } @catch (NSException *exception) {
        NSLog(@"[dx.bi] WebKit wouldn't start: %@ %@", exception.name, exception.reason);
        return nil;
    }
    return self;
}

- (UIView *)view {
    return (UIView *)_web;
}

- (void)loadURL:(NSURL *)url {
    [_web loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)evaluate:(NSString *)script completion:(void (^)(id, NSString *))completion {
    [_web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (!completion) return;
        if (error) completion(nil, error.userInfo[@"WKJavaScriptExceptionMessage"] ?: error.localizedDescription);
        else completion(result, nil);
    }];
}

- (void)received:(id<DxWKScriptMessage>)message {
    if (!self.onMessage) return;
    BOOL main = NO;
    NSString *host = nil;
    id<DxWKFrameInfo> frame = message.frameInfo;
    if ([frame respondsToSelector:@selector(isMainFrame)]) main = frame.isMainFrame;
    if ([frame respondsToSelector:@selector(securityOrigin)]) {
        id<DxWKSecurityOrigin> origin = frame.securityOrigin;
        if ([origin respondsToSelector:@selector(host)]) host = origin.host;
    }
    self.onMessage(message.body ?: [NSNull null], main, host);
}

- (NSInteger)decide:(id<DxWKNavigationAction>)action {
    if (!self.onNavigate) return DxWKNavigationActionPolicyAllow;
    id<DxWKFrameInfo> target = action.targetFrame;
    // (no frame: a new window, treated as the main one)
    BOOL main = target ? target.isMainFrame : YES;
    return self.onNavigate(action.request.URL, main) == DxNavigationAllow ? DxWKNavigationActionPolicyAllow : DxWKNavigationActionPolicyCancel;
}

- (void)terminated {
    if (self.onTerminate) self.onTerminate();
}

@end

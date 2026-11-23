// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DxNavigation) {
    DxNavigationAllow,
    DxNavigationCancel,
};

/**
 * A WKWebView on Apple TV. tvOS has WebKit, but not for apps: its SDK has no headers and nothing to
 * link against. So WebKit is loaded when the app starts and its classes are found by name (what
 * tvos/Probe checked works on a real Apple TV), and this wraps the little of WKWebView that
 * Page.swift uses: a script at the start of each page, messages from it, running JavaScript in it,
 * which pages it may open, and knowing when its engine stopped.
 */
@interface DxWebView : NSObject

/** nil when WebKit is there; else why it isn't */
+ (nullable NSString *)unavailableReason;

- (nullable instancetype)initWithFrame:(CGRect)frame userScript:(NSString *)script userAgent:(NSString *)userAgent messageName:(NSString *)name;

/** The web view (it has to be in the window for its page to keep running) */
@property (nonatomic, readonly) UIView *view;

/** `window.webkit.messageHandlers.<name>.postMessage(body)`: the body, whether it came from the main frame, and its host */
@property (nonatomic, copy, nullable) void (^onMessage)(id body, BOOL mainFrame, NSString *_Nullable host);
/** Whether the page may go to [url] (mainFrame: false for an embedded frame) */
@property (nonatomic, copy, nullable) DxNavigation (^onNavigate)(NSURL *_Nullable url, BOOL mainFrame);
/** The page's engine stopped (it crashed, or tvOS took its memory back) */
@property (nonatomic, copy, nullable) void (^onTerminate)(void);

- (void)loadURL:(NSURL *)url NS_SWIFT_NAME(load(_:));
- (void)evaluate:(NSString *)script completion:(nullable void (^)(id _Nullable result, NSString *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

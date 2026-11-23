// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A web view on tvOS, which has no public one: WKWebView or UIWebView, found at run time in the
 * system's private WebKit. The probe uses it to see whether Stremio's web app (and its core) can run
 * on an Apple TV, as it does out of sight in the iPhone app.
 */
@interface WebProbe : NSObject

/** Loads WebKit.framework (it isn't linked: tvOS's SDK has no WebKit). What dlopen said */
+ (NSString *)loadWebKit;
+ (BOOL)hasClass:(NSString *)name;

/** "WKWebView" or "UIWebView" */
@property (nonatomic, readonly) NSString *kind;

- (nullable instancetype)initWithKind:(NSString *)kind window:(UIWindow *)window userAgent:(NSString *)userAgent error:(NSString *_Nullable *_Nullable)error;
- (void)loadHTML:(NSString *)html baseURL:(nullable NSURL *)baseURL;
- (void)loadURL:(NSURL *)url;
/** Runs [script] in the page; the answer as a string (nil and an error if it couldn't) */
- (void)evaluate:(NSString *)script completion:(void (^)(NSString *_Nullable result, NSString *_Nullable error))completion;
- (void)tearDown;

@end

NS_ASSUME_NONNULL_END

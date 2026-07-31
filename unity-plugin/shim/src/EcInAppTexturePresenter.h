// In-app message texture presenter.
//
// See Unity-sdk-phase2-plan.md Section C (revised 2026-07-31) for the design.
//
// Data flow:
//   Kotlin `UnityMacosInAppPresenter.present(webView, ...)` is called by the
//   SDK when a message needs to be displayed. It invokes the Obj-C class
//   method `+[EcInAppTexturePresenter attachWebView:size:]` on the main
//   thread. The presenter adopts the WKWebView (moves it into a hidden
//   offscreen NSView), starts a display link, and begins snapshotting into
//   a shim-owned IOSurface at the configured cadence. On dismiss, the shim
//   calls `+[EcInAppTexturePresenter detachWebView]` to tear down the link
//   and release the surface.
//
//   The C# runtime calls `ec_inapp_texture_acquire()` after receiving the
//   `EcPresenterFrameCallback` (or on every Update). It gets the current
//   IOSurface, wraps it into a Metal texture, and blits into Unity's
//   external texture.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CVDisplayLink.h>
#include <stdatomic.h>

// Public surface used by the ec_inapp_* entry points in
// EngagementCloudSDKUnity.mm.
@interface EcInAppTexturePresenter : NSObject

+ (instancetype)shared;

// Kotlin side calls this on the main thread when a message begins presenting.
- (void)attachWebView:(WKWebView*)webView width:(int32_t)width height:(int32_t)height;

// Kotlin side calls this on the main thread when the message is dismissed.
- (void)detachWebView;

// Called from ec_inapp_texture_acquire. Returns the current surface (or NULL
// if no message is being presented). Ownership stays with the presenter.
- (IOSurfaceRef _Nullable)currentSurface;

// Called from ec_inapp_input_send. Forwards a synthesized NSEvent to the
// attached webview on the main thread.
- (void)sendInputKind:(int32_t)kind x:(double)x y:(double)y buttons:(int32_t)buttons;

// Called from ec_inapp_setPresenterFrameCallback. Optional.
- (void)setFrameCallback:(void (^_Nullable)(uint64_t frameIndex))callback;

// Called from ec_inapp_texture_setTargetFps (currently unused — default 30).
- (void)setTargetFps:(int32_t)fps;

@end

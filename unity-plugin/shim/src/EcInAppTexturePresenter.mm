#import "EcInAppTexturePresenter.h"

// ---------------------------------------------------------------------------
// Constants

static const NSInteger kDefaultViewportWidth = 1280;
static const NSInteger kDefaultViewportHeight = 720;
static const int32_t   kDefaultTargetFps = 30;

// ---------------------------------------------------------------------------
// Presenter internals

@interface EcInAppTexturePresenter () {
    dispatch_queue_t          _serialQueue;
    // Main-thread state (WebView lifecycle):
    NSView*                   _hostView;          // hidden offscreen container
    WKWebView*                _webView;           // adopted from Kotlin side

    // Presenter state (guarded by _serialQueue OR main thread while _webView is nil):
    IOSurfaceRef              _surface;           // nullable
    int32_t                   _surfaceWidth;
    int32_t                   _surfaceHeight;
    CGColorSpaceRef           _colorSpace;
    _Atomic(uint64_t)         _frameIndex;
    void (^_frameCallback)(uint64_t);

    // Snapshot timer — runs on main queue (WKWebView APIs are main-thread).
    dispatch_source_t         _snapshotTimer;
    int32_t                   _targetFps;
    BOOL                      _snapshotInFlight;
}
@end

@implementation EcInAppTexturePresenter

+ (instancetype)shared {
    static EcInAppTexturePresenter* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[EcInAppTexturePresenter alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _serialQueue = dispatch_queue_create("com.sap.ec.unity.presenter", DISPATCH_QUEUE_SERIAL);
        _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        _targetFps = kDefaultTargetFps;
        atomic_init(&_frameIndex, 0);
    }
    return self;
}

- (void)dealloc {
    if (_colorSpace) { CGColorSpaceRelease(_colorSpace); _colorSpace = NULL; }
    if (_surface)    { CFRelease(_surface); _surface = NULL; }
}

// ---------------------------------------------------------------------------
// IOSurface allocation

- (void)ensureSurfaceForWidth:(int32_t)width height:(int32_t)height {
    if (_surface && _surfaceWidth == width && _surfaceHeight == height) return;
    if (_surface) { CFRelease(_surface); _surface = NULL; }

    size_t bytesPerElement = 4; // BGRA8
    size_t bytesPerRow     = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow,
                                                    (size_t)width * bytesPerElement);
    NSDictionary* props = @{
        (id)kIOSurfaceWidth:           @(width),
        (id)kIOSurfaceHeight:          @(height),
        (id)kIOSurfaceBytesPerElement: @(bytesPerElement),
        (id)kIOSurfaceBytesPerRow:     @(bytesPerRow),
        (id)kIOSurfacePixelFormat:     @((uint32_t)'BGRA'),
        (id)kIOSurfaceAllocSize:       @(bytesPerRow * (size_t)height),
    };
    _surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    _surfaceWidth  = width;
    _surfaceHeight = height;
}

// ---------------------------------------------------------------------------
// Snapshot loop. Fires on the main queue (WKWebView requires main thread).
// Draws into a CGBitmapContext backed by the IOSurface's base address.

- (void)startSnapshotTimer {
    if (_snapshotTimer) return;
    int32_t fps = _targetFps > 0 ? _targetFps : kDefaultTargetFps;
    uint64_t intervalNs = (uint64_t)(1e9 / (double)fps);

    _snapshotTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                            dispatch_get_main_queue());
    dispatch_source_set_timer(_snapshotTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNs),
                              intervalNs,
                              intervalNs / 10);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_snapshotTimer, ^{
        [weakSelf tickSnapshot];
    });
    dispatch_resume(_snapshotTimer);
}

- (void)stopSnapshotTimer {
    if (!_snapshotTimer) return;
    dispatch_source_cancel(_snapshotTimer);
    _snapshotTimer = nil;
    _snapshotInFlight = NO;
}

- (void)tickSnapshot {
    // Main thread.
    if (!_webView) return;
    if (_snapshotInFlight) return;  // drop rather than queue
    _snapshotInFlight = YES;

    WKSnapshotConfiguration* cfg = [[WKSnapshotConfiguration alloc] init];
    cfg.rect = _webView.bounds;
    cfg.afterScreenUpdates = NO;  // capture as-is; don't wait for pending layout

    __weak typeof(self) weakSelf = self;
    [_webView takeSnapshotWithConfiguration:cfg
                          completionHandler:^(NSImage* _Nullable image, NSError* _Nullable error) {
        typeof(self) strong = weakSelf;
        if (!strong) return;
        strong->_snapshotInFlight = NO;
        if (error || !image) {
            // Snapshot failures are common during layout thrash; just skip.
            return;
        }
        // Hop to the serial queue to blit into the IOSurface.
        dispatch_async(strong->_serialQueue, ^{
            [strong blitImageIntoSurface:image];
        });
    }];
}

- (void)blitImageIntoSurface:(NSImage*)image {
    // Serial queue.
    if (!_surface) return;
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) return;

    IOSurfaceLock(_surface, 0, NULL);
    void* base = IOSurfaceGetBaseAddress(_surface);
    size_t bytesPerRow = IOSurfaceGetBytesPerRow(_surface);

    CGContextRef ctx = CGBitmapContextCreate(
        base,
        (size_t)_surfaceWidth, (size_t)_surfaceHeight,
        8, bytesPerRow,
        _colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst  // BGRA
    );
    if (ctx) {
        CGContextClearRect(ctx, CGRectMake(0, 0, _surfaceWidth, _surfaceHeight));
        // NSImage/CGImage origin is top-left; CGBitmapContext with a non-flipped
        // affine matches that when we draw at (0,0) with the surface's height.
        // But CGContext coordinates are bottom-left by default, so flip Y so the
        // web view's top-left ends up at the surface's top-left (Unity texture
        // convention).
        CGContextTranslateCTM(ctx, 0, _surfaceHeight);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, _surfaceWidth, _surfaceHeight), cgImage);
        CGContextRelease(ctx);
    }

    IOSurfaceUnlock(_surface, 0, NULL);

    uint64_t idx = atomic_fetch_add(&_frameIndex, 1) + 1;
    if (_frameCallback) _frameCallback(idx);
}

// ---------------------------------------------------------------------------
// Public API

- (void)attachWebView:(WKWebView*)webView width:(int32_t)width height:(int32_t)height {
    // Must run on main thread — WKWebView is main-thread-only.
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf attachWebView:webView width:width height:height];
        });
        return;
    }

    if (_webView) {
        [self detachWebView];
    }

    int32_t w = width  > 0 ? width  : (int32_t)kDefaultViewportWidth;
    int32_t h = height > 0 ? height : (int32_t)kDefaultViewportHeight;

    if (!_hostView) {
        _hostView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
        _hostView.wantsLayer = YES;
        // NEVER added to a window — WKWebView still lays out and paints when
        // its view is in a layer-hosting hierarchy, even without a window.
    } else {
        _hostView.frame = NSMakeRect(0, 0, w, h);
    }

    _webView = webView;
    _webView.frame = _hostView.bounds;
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_hostView addSubview:_webView];

    dispatch_sync(_serialQueue, ^{
        [self ensureSurfaceForWidth:w height:h];
    });

    [self startSnapshotTimer];
}

- (void)detachWebView {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf detachWebView];
        });
        return;
    }
    [self stopSnapshotTimer];
    [_webView removeFromSuperview];
    _webView = nil;
    // Keep the IOSurface allocated so the C# side's texture handle stays
    // valid across dismiss/reshow cycles. Zero the pixels so Unity sees
    // transparency after dismiss.
    dispatch_async(_serialQueue, ^{
        if (!self->_surface) return;
        IOSurfaceLock(self->_surface, 0, NULL);
        void* base = IOSurfaceGetBaseAddress(self->_surface);
        size_t total = IOSurfaceGetBytesPerRow(self->_surface) * (size_t)self->_surfaceHeight;
        memset(base, 0, total);
        IOSurfaceUnlock(self->_surface, 0, NULL);
        uint64_t idx = atomic_fetch_add(&self->_frameIndex, 1) + 1;
        if (self->_frameCallback) self->_frameCallback(idx);
    });
}

- (IOSurfaceRef _Nullable)currentSurface {
    return _surface;  // atomic pointer read; the surface itself is either alive
                      // (allocated by ensureSurfaceForWidth) or NULL.
}

- (void)setFrameCallback:(void (^)(uint64_t))callback {
    _frameCallback = [callback copy];
}

- (void)setTargetFps:(int32_t)fps {
    _targetFps = fps > 0 ? fps : kDefaultTargetFps;
    if (_snapshotTimer) {
        [self stopSnapshotTimer];
        [self startSnapshotTimer];
    }
}

// ---------------------------------------------------------------------------
// Input synthesis

- (void)sendInputKind:(int32_t)kind x:(double)x y:(double)y buttons:(int32_t)buttons {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf sendInputKind:kind x:x y:y buttons:buttons];
        });
        return;
    }
    if (!_webView) return;

    NSEventType type;
    switch (kind) {
        case 0: type = NSEventTypeMouseMoved; break;
        case 1: type = (buttons & 0x2) ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown; break;
        case 2: type = (buttons & 0x2) ? NSEventTypeRightMouseUp   : NSEventTypeLeftMouseUp;   break;
        default: return;
    }

    // Convert Unity's top-left origin to AppKit's bottom-left origin. Unity
    // passes x/y in webview pixel space (see UnityInAppTextureView).
    NSPoint location = NSMakePoint(x, (CGFloat)_surfaceHeight - y);

    // Synthetic NSEvent — needs a valid windowNumber for hit-testing to work
    // even off-window. We use 0 (no window) which WebKit accepts for hit
    // testing against a specific view we already know about.
    NSEvent* event = [NSEvent mouseEventWithType:type
                                        location:location
                                   modifierFlags:0
                                       timestamp:[[NSProcessInfo processInfo] systemUptime]
                                    windowNumber:0
                                         context:nil
                                     eventNumber:0
                                      clickCount:1
                                        pressure:1.0];
    if (!event) return;

    switch (type) {
        case NSEventTypeMouseMoved:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged: [_webView mouseMoved:event]; break;
        case NSEventTypeLeftMouseDown:     [_webView mouseDown:event];  break;
        case NSEventTypeLeftMouseUp:       [_webView mouseUp:event];    break;
        case NSEventTypeRightMouseDown:    [_webView rightMouseDown:event]; break;
        case NSEventTypeRightMouseUp:      [_webView rightMouseUp:event];   break;
        default: break;
    }
}

@end

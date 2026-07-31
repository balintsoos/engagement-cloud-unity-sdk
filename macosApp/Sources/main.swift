import AppKit
import Darwin
import EngagementCloudSDK
import WebKit

// ----------------------------------------------------------------------------
// Constants — match app/src/main/kotlin/com/sap/engagementcloudsdktestapp/sdk/Constants.kt
// in the Android e2e test-app so the same campaigns fire against the same code + contact.
// ----------------------------------------------------------------------------

/// Application code used by the Android e2e test-app (Constants.APPLICATION_CODE).
/// Every configured campaign (Push P1–P6, In-App IA1–IA7, mysy2/3/4, Inline IIA1–IIA4) targets
/// this code. Keep in sync with `engagement-cloud-sdk-test-app` `Constants.APPLICATION_CODE`.
private let APPLICATION_CODE = "EMSE3-B4341"

/// Contact email used by the Android e2e test-app (Constants.CONTACT_EMAIL). The IA/mysy
/// campaigns target this contact.
private let CONTACT_EMAIL = "test1@test.com"

/// Custom-event names that trigger in-app overlays. Copied verbatim from
/// `engagement-cloud-sdk-test-app` — do not rename, the backend automations key off these.
///
/// Push-triggering events (P1–P6) are intentionally omitted: Phase-1 macOS defers push
/// (decision #5), so firing them from macOS would only fill logs with backend-rejected
/// attempts. See `Unity-sdk-phase1-plan.md`.
private enum CampaignTrigger {
    // In-app overlay campaigns (IA1, IA4, IA5, IA6, IA7) — mirror IA*_LABEL constants in
    // `app/src/androidTest/kotlin/com/sap/engagementcloudsdktestapp/InAppE2ETest.kt`.
    static let IA1_customEventInApp = "mysy2"           // IA1: overlay w/ MAYBE LATER + Open MySy3
    static let IA4_viewEvent        = "test_inapp_view_event"   // IA4: view-event overlay
    static let IA5_clickEvent       = "test_inapp_click_event"  // IA5: click-event overlay
    static let IA6_pauseTest        = "test_inapp_pause"        // IA6: should NOT show while paused
    static let IA7_resumeTest       = "test_inapp_resume"       // IA7: shows after resume

    // Events-tab custom triggers — mirror `EventsTab.kt`.
    static let mysy2 = "mysy2"   // same overlay as IA1
    static let mysy3 = "mysy3"   // overlay w/ Open SAP + AppEvent → hello_mobile
    static let mysy4 = "mysy4"   // no-campaign test — sample must not crash if backend returns none

    // Robustness triggers used by InAppE2ETest but not directly by us (backgrounding, rotation
    // and screen-off apply to iOS/Android only) — kept here for reference/parity.
    static let inAppScreenOff  = "test_inapp_screen_off"
    static let inAppRotation   = "test_inapp_rotation"
    static let inAppBackground = "test_inapp_background"
}

/// viewId the sample loads into its inline WKWebView slot. Matches an inline campaign
/// authored under `EMSE3-B4341` with viewId `ia`.
private let INLINE_VIEW_ID = "ia"

// Line-buffered stderr so log entries survive a SIGTERM at the end of a headless smoke run.
setvbuf(stderr, nil, _IOLBF, 0)

// ----------------------------------------------------------------------------
// AppDelegate
// ----------------------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var logView: NSTextView!
    private var inlineContainer: NSView!         // slot where the inline WKWebView is mounted
    private var inlineStatusLabel: NSTextField!  // one-liner status next to the slot
    private var currentInlineWebView: WKWebView? // the WKWebView returned by inApp.fetchInline
    private let engagementCloud = EngagementCloud.shared
    private let logDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.regular)
        buildUI()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        engagementCloud.registerEventListener { [weak self] event in
            self?.logEvent(event)
        }
        log("event listener registered (contact=\(CONTACT_EMAIL), appCode=\(APPLICATION_CODE))")

        Task {
            await self.dumpState(header: "boot state")
            // If the SDK is already enabled (persisted from a previous run), auto-load the inline
            // slot so the demo is one-click from launch. If not enabled, the user has to click
            // Enable first, and the enable flow will call loadInline() itself.
            if (try? await self.engagementCloud.setup.isEnabled()) == true {
                await self.loadInline()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: UI

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 780, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Engagement Cloud — macOS sample (debug, appCode=\(APPLICATION_CODE))"

        // Setup row
        let enableBtn = NSButton(title: "Enable SDK",       target: self, action: #selector(onEnable))
        let disableBtn = NSButton(title: "Disable SDK",     target: self, action: #selector(onDisable))
        let linkBtn   = NSButton(title: "Link \(CONTACT_EMAIL)", target: self, action: #selector(onLink))
        let setupRow = NSStackView(views: [enableBtn, disableBtn, linkBtn])
        setupRow.orientation = .horizontal; setupRow.spacing = 8

        // In-app campaign triggers (matches Android e2e test-app buttons).
        // Each button fires a custom event and expects the corresponding campaign to be
        // authored in the Engagement Cloud dashboard against application code EMSE3-B4341.
        let ia1Btn   = NSButton(title: "IA1  ▶ mysy2 (overlay + 2 btn)",       target: self, action: #selector(onIA1))
        let mysy3Btn = NSButton(title: "mysy3 ▶ Open SAP + AppEvent hello_mobile", target: self, action: #selector(onMysy3))
        let mysy4Btn = NSButton(title: "mysy4 ▶ no-campaign smoke",             target: self, action: #selector(onMysy4))
        let ia4Btn   = NSButton(title: "IA4  ▶ test_inapp_view_event",          target: self, action: #selector(onIA4))
        let ia5Btn   = NSButton(title: "IA5  ▶ test_inapp_click_event",         target: self, action: #selector(onIA5))
        let ia6Btn   = NSButton(title: "IA6  ▶ test_inapp_pause (paused: no ov.)", target: self, action: #selector(onIA6))
        let ia7Btn   = NSButton(title: "IA7  ▶ test_inapp_resume",              target: self, action: #selector(onIA7))
        let campaignRow1 = NSStackView(views: [ia1Btn, mysy3Btn, mysy4Btn])
        campaignRow1.orientation = .horizontal; campaignRow1.spacing = 8
        let campaignRow2 = NSStackView(views: [ia4Btn, ia5Btn, ia6Btn, ia7Btn])
        campaignRow2.orientation = .horizontal; campaignRow2.spacing = 8

        // Inline in-app slot — always loads viewId INLINE_VIEW_ID ("ia").
        // The container is a fixed-height NSView; the inline WKWebView produced by
        // `engagementCloud.inApp.fetchInline("ia")` fills it, and clicks inside the message
        // go through the SDK's JS bridge (openExternalLink, triggerMEEvent, close, etc.).
        inlineStatusLabel = NSTextField(labelWithString: "Inline slot: idle (viewId=\"\(INLINE_VIEW_ID)\")")
        inlineStatusLabel.font = .systemFont(ofSize: 11)
        inlineStatusLabel.textColor = .secondaryLabelColor
        let reloadInlineBtn = NSButton(title: "reload inline", target: self, action: #selector(onReloadInline))
        let clearInlineBtn  = NSButton(title: "clear inline",  target: self, action: #selector(onClearInline))
        let inlineHeader = NSStackView(views: [inlineStatusLabel, reloadInlineBtn, clearInlineBtn])
        inlineHeader.orientation = .horizontal; inlineHeader.spacing = 8

        inlineContainer = NSView()
        inlineContainer.wantsLayer = true
        inlineContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        inlineContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        inlineContainer.layer?.borderWidth = 1
        inlineContainer.layer?.cornerRadius = 4
        inlineContainer.translatesAutoresizingMaskIntoConstraints = false

        // In-app control + custom event
        let pauseBtn  = NSButton(title: "inApp.pause",  target: self, action: #selector(onPause))
        let resumeBtn = NSButton(title: "inApp.resume", target: self, action: #selector(onResume))
        let customBtn = NSButton(title: "track custom: macos-sample", target: self, action: #selector(onTrackCustom))
        let controlRow = NSStackView(views: [pauseBtn, resumeBtn, customBtn])
        controlRow.orientation = .horizontal; controlRow.spacing = 8

        // Meta
        let dumpBtn  = NSButton(title: "dump state", target: self, action: #selector(onDump))
        let clearBtn = NSButton(title: "clear log",  target: self, action: #selector(onClearLog))
        let metaRow = NSStackView(views: [dumpBtn, clearBtn])
        metaRow.orientation = .horizontal; metaRow.spacing = 8

        statusLabel = NSTextField(labelWithString: "Ready.")
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Scrollable log
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.autohidesScrollers = false
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logView = NSTextView()
        logView.isEditable = false
        logView.isRichText = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 6, height: 6)
        logView.autoresizingMask = [.width]
        logView.isVerticallyResizable = true
        logView.textColor = .labelColor
        logScroll.documentView = logView

        // Section headers keep the UI scannable in a live demo.
        func header(_ title: String) -> NSTextField {
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }

        let stack = NSStackView(views: [
            statusLabel,
            header("Setup"),          setupRow,
            header("In-app triggers (fire via custom event → backend campaign)"),
            campaignRow1, campaignRow2,
            header("Inline in-app slot (viewId = \"\(INLINE_VIEW_ID)\", auto-loaded on Enable)"),
            inlineHeader,
            inlineContainer,
            header("In-app control / free-form event"),
            controlRow,
            header("Debug"),
            metaRow,
            logScroll
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: window.contentView!.bounds)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            logScroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            logScroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            inlineContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            inlineContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            inlineContainer.heightAnchor.constraint(equalToConstant: 180)
        ])
        window.contentView = container
    }

    // MARK: Logging

    private func log(_ message: String) {
        let stamp = logDateFormatter.string(from: Date())
        let entry = "[\(stamp)] \(message)\n"
        DispatchQueue.main.async {
            self.logView.textStorage?.append(NSAttributedString(
                string: entry,
                attributes: [.foregroundColor: NSColor.labelColor,
                             .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            ))
            self.logView.scrollToEndOfDocument(nil)
        }
        FileHandle.standardError.write(entry.data(using: .utf8) ?? Data())
    }

    private func status(_ message: String) {
        DispatchQueue.main.async { self.statusLabel.stringValue = message }
        log("status: \(message)")
    }

    private func logEvent(_ event: Any) {
        if let appEvent = event as? AppEvent {
            let payload = appEvent.payload.map { "\($0)" } ?? "nil"
            log("EVENT AppEvent name=\(appEvent.name) payload=\(payload)")
        } else if let badge = event as? BadgeCountEvent {
            log("EVENT BadgeCountEvent method=\(badge.method) count=\(badge.badgeCount)")
        } else {
            log("EVENT \(String(describing: event))")
        }
    }

    // MARK: State dump

    private func dumpState(header: String) async {
        log("---- state dump [\(header)] ----")

        do {
            let ver = try await engagementCloud.config.getSdkVersion()
            log("  config.sdkVersion         = \(ver)")
        } catch { log("  config.sdkVersion         ERR \(error.localizedDescription)") }

        do {
            let code = try await engagementCloud.config.getApplicationCode()
            log("  config.applicationCode    = \(code ?? "<nil>")")
        } catch { log("  config.applicationCode    ERR \(error.localizedDescription)") }

        do {
            let cid = try await engagementCloud.config.getClientId()
            log("  config.clientId           = \(cid)")
        } catch { log("  config.clientId           ERR \(error.localizedDescription)") }

        do {
            let lang = try await engagementCloud.config.getLanguageCode()
            log("  config.languageCode       = \(lang)")
        } catch { log("  config.languageCode       ERR \(error.localizedDescription)") }

        do {
            let appVer = try await engagementCloud.config.getApplicationVersion()
            log("  config.applicationVersion = \(appVer)")
        } catch { log("  config.applicationVersion ERR \(error.localizedDescription)") }

        do {
            let state = try await engagementCloud.config.getCurrentSdkState()
            log("  config.currentSdkState    = \(state)")
        } catch { log("  config.currentSdkState    ERR \(error.localizedDescription)") }

        do {
            let enabled = try await engagementCloud.setup.isEnabled()
            log("  setup.isEnabled           = \(enabled)")
        } catch { log("  setup.isEnabled           ERR \(error.localizedDescription)") }

        log("  inApp.isPaused            = \(engagementCloud.inApp.isPaused)")
        log("---- end state dump [\(header)] ----")
    }

    // MARK: Setup actions

    @objc private func onEnable() {
        status("Enabling SDK (appCode=\(APPLICATION_CODE))…")
        Task {
            do {
                try await engagementCloud.setup.enable(
                    config: EngagementCloudConfig(applicationCode: APPLICATION_CODE),
                    onContactLinkingFailed: { onSuccess, _ in
                        Task {
                            _ = onSuccess(LinkContactDataContactFieldValueData(contactFieldValue: CONTACT_EMAIL))
                        }
                    }
                )
                status("SDK enabled.")
            } catch {
                status("Enable failed: \(error.localizedDescription)")
            }
            await dumpState(header: "after enable")
            // Kick the inline slot after every successful (or repeat) enable — same convenience
            // as boot state.
            await loadInline()
        }
    }

    @objc private func onDisable() {
        status("Disabling SDK…")
        Task {
            do {
                try await engagementCloud.setup.disable()
                status("SDK disabled.")
            } catch {
                status("Disable failed: \(error.localizedDescription)")
            }
            await dumpState(header: "after disable")
        }
    }

    @objc private func onLink() {
        status("Linking contact \(CONTACT_EMAIL)…")
        Task {
            do {
                try await engagementCloud.contact.link(contactFieldValue: CONTACT_EMAIL)
                status("Linked contact '\(CONTACT_EMAIL)'.")
            } catch {
                status("Link failed: \(error.localizedDescription)")
            }
            await dumpState(header: "after link")
        }
    }

    // MARK: Campaign triggers (custom events matching Android e2e test-app)

    /// Fire a custom event by name. Every campaign trigger in this file goes through here so the
    /// success/failure log line always names the event that fired, which is the piece a live
    /// demo actually needs.
    private func trackCampaign(_ eventName: String, label: String) {
        status("\(label) — track '\(eventName)'…")
        Task {
            do {
                try await engagementCloud.event.track(
                    event: CustomEvent(name: eventName, attributes: nil)
                )
                log("track '\(eventName)' → OK (waiting for overlay if a campaign is configured)")
                status("\(label) — tracked '\(eventName)'.")
            } catch {
                status("\(label) — track '\(eventName)' FAILED: \(error.localizedDescription)")
            }
        }
    }

    @objc private func onIA1()   { trackCampaign(CampaignTrigger.IA1_customEventInApp, label: "IA1") }
    @objc private func onMysy3() { trackCampaign(CampaignTrigger.mysy3,               label: "mysy3") }
    @objc private func onMysy4() { trackCampaign(CampaignTrigger.mysy4,               label: "mysy4") }
    @objc private func onIA4()   { trackCampaign(CampaignTrigger.IA4_viewEvent,       label: "IA4") }
    @objc private func onIA5()   { trackCampaign(CampaignTrigger.IA5_clickEvent,      label: "IA5") }
    @objc private func onIA6()   { trackCampaign(CampaignTrigger.IA6_pauseTest,       label: "IA6") }
    @objc private func onIA7()   { trackCampaign(CampaignTrigger.IA7_resumeTest,      label: "IA7") }

    @objc private func onTrackCustom() {
        trackCampaign("macos-sample", label: "custom")
    }

    // MARK: In-app control

    @objc private func onPause() {
        status("Pausing in-app…")
        Task {
            do {
                try await engagementCloud.inApp.pause()
                status("inApp paused (isPaused=\(engagementCloud.inApp.isPaused))")
            } catch {
                status("Pause failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func onResume() {
        status("Resuming in-app…")
        Task {
            do {
                try await engagementCloud.inApp.resume()
                status("inApp resumed (isPaused=\(engagementCloud.inApp.isPaused))")
            } catch {
                status("Resume failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Debug

    @objc private func onDump() {
        Task { await dumpState(header: "manual") }
    }

    @objc private func onClearLog() {
        DispatchQueue.main.async { self.logView.string = "" }
        log("(log cleared)")
    }

    // MARK: Inline in-app slot

    /// Fetch the inline in-app for [INLINE_VIEW_ID] and mount the returned `WKWebView` in the
    /// slot. Idempotent — removes any previously-mounted inline view first. If the backend has
    /// no message for the viewId (HTTP 204), the SDK returns nil and we log the miss.
    private func loadInline() async {
        log("inline: fetching viewId=\"\(INLINE_VIEW_ID)\"…")
        await MainActor.run { self.inlineStatusLabel.stringValue = "Inline slot: fetching \"\(INLINE_VIEW_ID)\"…" }

        let webView: WKWebView?
        do {
            webView = try await engagementCloud.inApp.fetchInline(viewId: INLINE_VIEW_ID)
        } catch {
            log("inline: fetchInline threw \(error.localizedDescription)")
            await MainActor.run { self.inlineStatusLabel.stringValue = "Inline slot: error — \(error.localizedDescription)" }
            return
        }

        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.removeCurrentInline()
            guard let wv = webView else {
                self.inlineStatusLabel.stringValue = "Inline slot: no message for \"\(INLINE_VIEW_ID)\" (backend returned 204 or empty)"
                self.log("inline: no message for \"\(INLINE_VIEW_ID)\" (backend returned 204 or empty)")
                return
            }
            wv.translatesAutoresizingMaskIntoConstraints = false
            self.inlineContainer.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: self.inlineContainer.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: self.inlineContainer.trailingAnchor),
                wv.topAnchor.constraint(equalTo: self.inlineContainer.topAnchor),
                wv.bottomAnchor.constraint(equalTo: self.inlineContainer.bottomAnchor)
            ])
            self.currentInlineWebView = wv
            self.inlineStatusLabel.stringValue = "Inline slot: loaded \"\(INLINE_VIEW_ID)\" (WKWebView mounted)"
            self.log("inline: mounted WKWebView for \"\(INLINE_VIEW_ID)\"")
        }
    }

    /// Remove the previously-mounted inline WKWebView, if any. Must run on the main thread.
    private func removeCurrentInline() {
        guard let old = currentInlineWebView else { return }
        old.removeFromSuperview()
        currentInlineWebView = nil
    }

    @objc private func onReloadInline() {
        Task { await loadInline() }
    }

    @objc private func onClearInline() {
        DispatchQueue.main.async { [weak self] in
            self?.removeCurrentInline()
            self?.inlineStatusLabel.stringValue = "Inline slot: cleared"
            self?.log("inline: cleared")
        }
    }
}

// Explicit AppKit boot — @main on NSApplicationDelegate does not always wire NSApp.delegate,
// so we do it by hand so the delegate methods actually fire.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

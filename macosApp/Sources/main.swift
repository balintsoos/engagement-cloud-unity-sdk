import AppKit
import EngagementCloudSDK

// Minimal AppKit host that exercises the EngagementCloud macOS SDK surface end-to-end so we
// can visually confirm §5's WKWebView + NSPanel in-app presenter actually works.
//
// The application code below is a placeholder ("EMSE3-B4341", matching the iosApp sample).
// Replace with a real code from your Engagement Cloud environment when validating real traffic.

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private let engagementCloud = EngagementCloud.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 460, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Engagement Cloud — macOS sample"

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "Ready.")
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.preferredMaxLayoutWidth = 400

        let enableBtn = NSButton(title: "1. setup.enable", target: self, action: #selector(onEnable))
        let trackBtn  = NSButton(title: "2. event.track(\"macos-sample\")", target: self, action: #selector(onTrack))
        let linkBtn   = NSButton(title: "3. contact.link(\"test@example.com\")", target: self, action: #selector(onLink))
        let inAppBtn  = NSButton(title: "4. show test in-app (WKWebView overlay)", target: self, action: #selector(onShowInApp))

        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(enableBtn)
        stack.addArrangedSubview(trackBtn)
        stack.addArrangedSubview(linkBtn)
        stack.addArrangedSubview(inAppBtn)

        let container = NSView(frame: window.contentView!.bounds)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
    }

    private func status(_ message: String) {
        DispatchQueue.main.async { self.statusLabel.stringValue = message }
        NSLog("macosApp: %@", message)
    }

    @objc private func onEnable() {
        status("Enabling SDK…")
        Task {
            do {
                try await engagementCloud.setup.enable(
                    config: EngagementCloudConfig(applicationCode: "EMSE3-B4341"),
                    onContactLinkingFailed: { onSuccess, _ in
                        Task {
                            _ = onSuccess(LinkContactDataContactFieldValueData(contactFieldValue: "test@example.com"))
                        }
                    }
                )
                status("SDK enabled.")
            } catch {
                status("Enable failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func onTrack() {
        status("Tracking event…")
        Task {
            do {
                try await engagementCloud.event.track(
                    event: CustomEvent(name: "macos-sample", attributes: nil)
                )
                status("Tracked event 'macos-sample'.")
            } catch {
                status("Track failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func onLink() {
        status("Linking contact…")
        Task {
            do {
                try await engagementCloud.contact.link(contactFieldValue: "test@example.com")
                status("Linked contact 'test@example.com'.")
            } catch {
                status("Link failed: \(error.localizedDescription)")
            }
        }
    }

    // Real in-app messages arrive over the network after the campaign is triggered from the
    // Engagement Cloud dashboard. This button is intentionally a stub for now: the WKWebView
    // + NSPanel path itself is verified once a real in-app arrives.
    @objc private func onShowInApp() {
        status("Trigger an in-app message from your EC campaign dashboard while this app is running.")
    }
}

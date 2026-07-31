# Changelog

All notable changes to `com.sap.ec.unity` will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial Unity plugin for SAP Engagement Cloud on Apple-Silicon macOS.
- Static facade `EngagementCloud` covering setup, contact
  (link/linkAuthenticated/unlink), custom event tracking, in-app messaging
  (pause/resume/isPaused), config read/write, and deep-link handling.
- Auto-init via `EngagementCloudSettings` ScriptableObject in `Resources/`.
- In-app message rendering as Unity `Texture2D` via WKWebView snapshot →
  IOSurface → Metal external texture. Pointer input synthesized as
  `NSEvent` and forwarded to the offscreen WebView.
- Typed `EngagementCloudException` hierarchy mirroring Kotlin exceptions.
- Six sample scenes (`Samples~/Setup`, `.../Contact`, `.../Event`,
  `.../InApp`, `.../Config`, `.../DeepLink`).

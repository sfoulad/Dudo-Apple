# Dudo for Apple platforms

The native Apple client for **Dudo**, an AI-native business-management platform for
startups and SMEs. One multiplatform SwiftUI target ships iPhone, iPad, and a **true
native macOS** app.

> **Status: pre-alpha.** This repository currently contains a build-pipeline shell — an
> app that launches, shows its version and build number, and nothing else. There is no
> product functionality yet, and by design there is none until Dudo Core publishes the
> contracts this client will consume.

## Requirements

| | |
|---|---|
| Xcode | 26.6 (Swift 6.3.3, iOS 26.5 / macOS 26.5 SDKs) |
| Minimum iOS / iPadOS | 18.0 |
| Minimum macOS | 15.0 |
| Swift language mode | 6 |
| Mac Catalyst | **Not supported and never will be.** macOS is a native AppKit-backed SwiftUI destination. |

## Layout

```
Dudo.xcodeproj/           single multiplatform app target "Dudo"
Dudo/
  DudoApp.swift           app entry point and scene definition
  ContentView.swift       placeholder shell
  Dudo.entitlements       macOS-only entitlements (App Sandbox, outbound network)
  Assets.xcassets/        app icon and accent colour
```

The `Dudo` folder is a file-system-synchronized group, so adding a Swift file to it adds
it to the target — there is no membership to maintain by hand in the project file.

## Building

```sh
# iPhone / iPad
xcodebuild -project Dudo.xcodeproj -scheme Dudo \
  -destination 'generic/platform=iOS Simulator' build

# macOS (native)
xcodebuild -project Dudo.xcodeproj -scheme Dudo \
  -destination 'platform=macOS' build
```

`Dudo` is a shared scheme, so `xcodebuild -list` sees it from a clean checkout.

To confirm a macOS build is genuinely native rather than Catalyst:

```sh
vtool -show-build-version <path>/Dudo.app/Contents/MacOS/Dudo   # expect: platform MACOS
```

## Shared versus platform-specific

The codebase is shared by default. Divergence is deliberate and limited to the places
where Apple's platform conventions genuinely differ — window and scene management, the
macOS menu bar, keyboard and pointer interaction, navigation structure, and file
handling. Today the only divergence is in `DudoApp.swift`, where macOS gets a default
window size and a menu-bar command group, and in `ContentView.swift`, where iOS supplies
a system background colour.

## Architectural boundaries

This client is deliberately thin. It **renders and collects**; it does not decide.

- **No business rules.** Pricing, tax, entitlement, approval thresholds, workflow state
  transitions, permission decisions, and tenant resolution all live in Dudo Core.
- **No direct data access.** No SQL, no ORM, no datastore client, no connection strings.
  Everything reaches this app through versioned contracts published by Core.
- **No invented contracts.** If a needed contract does not exist, it is requested from
  Core, not stubbed here.
- **Authorization is server-side.** Hiding a control in the UI is presentation, never
  security. Every request is assumed to be authorized on the server.
- **The same contracts as the web client.** Apple and web consume one approved contract
  set; this client never diverges locally.

## Security

This repository is **public**. Signing identities, certificates, provisioning profiles,
API keys, App Store Connect keys, `.env` files, and customer data must never be committed
— see `.gitignore`, and treat it as a backstop rather than a guarantee. A credential
pushed to a public repository is compromised the moment it lands and survives deletion in
git history; report an exposure immediately rather than quietly rewriting history.

Development and test data is synthetic. Never real customer data.

## Versioning and releases

`MARKETING_VERSION` is the user-visible version; `CURRENT_PROJECT_VERSION` is the build
number and **increments on every test release** — it is never reused or reset. Releases
go to internal TestFlight first. Archived, validated, uploaded, and processing are
distinct states, and none of them means a build is testable; a build is testable only
once App Store Connect has finished processing it and it is available to the internal
tester.

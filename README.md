# Pocket Dolphin · DSH

<p align="center">
  <strong>A native iPhone and iPad client for the DSH host you already run.</strong><br>
  Free, open source, and deliberately small in scope.
</p>

<p align="center">
  <a href="https://impai.me/apps/dsh-remote/">Website</a> ·
  <a href="https://apps.apple.com/app/id6802863224">App Store</a> ·
  <a href="https://impai.me/apps/dsh-remote/privacy.html">Privacy</a> ·
  <a href="#run-it">Run it</a> ·
  <a href="#development">Development</a>
</p>

> **Independent project.** Pocket Dolphin · DSH is an unofficial client for DeepSeek Harness. It is not affiliated with, endorsed by, or sponsored by DeepSeek.

## What it is

Pocket Dolphin · DSH brings a self-hosted DSH session to iPhone and iPad. Pair the app with a host you control, browse its workspaces and sessions, and read or continue a conversation without putting another service in the middle.

The app is for people who already operate a DSH host. It does not provide a hosted model, account system, relay, or cloud sync service.

## What it does

- Pair with a DSH host by one-time QR code, pairing link, or a manual address.
- Keep multiple hosts and their workspaces separate.
- Browse and continue sessions with streaming replies, reasoning, tools, approvals, questions, goals, and subagents.
- Render Markdown, code blocks, tables, and tool output in a native SwiftUI interface.
- Work on both iPhone and iPad, including a full workspace sidebar on iPad.
- Store host credentials in the iOS Keychain and retain local UI preferences on-device.

## Privacy by design

Pocket Dolphin · DSH connects directly to the address you pair or configure. Prompts, responses, session metadata, and credentials are sent only to that selected host as part of the requested interaction.

There are no accounts, ads, analytics SDKs, telemetry, or cross-app tracking. The app does not operate a relay and does not send session data through `impai.me`.

Read the full [privacy policy](https://impai.me/apps/dsh-remote/privacy.html).

## Connection model

```text
iPhone / iPad ── direct HTTPS, LAN, or Tailnet connection ──► your DSH host
                                                               │
                                                               └── models and tools configured by you
```

For remote access, use a trusted network path. The optional [`dsh-network`](https://www.npmjs.com/package/dsh-network) Host plugin keeps the DSH service on loopback and presents a short-lived pairing QR code through an authenticated gateway; it is preferred over exposing a development port directly to a LAN or the public internet.

## Configure the Host with `dsh-network`

[`dsh-network` on npm](https://www.npmjs.com/package/dsh-network) is an independent DSH Host plugin for secure LAN, Tailnet, and existing public HTTPS routes. It keeps DSH on `127.0.0.1:3080` and serves the authenticated client gateway on `3081`.

Install it in the DSH web profile and start DSH:

```sh
dsh plugin --profile web add dsh-network@next
dsh web
```

Then choose the route to encode in a one-time pairing QR code:

```sh
dsh plugin --profile web exec dsh-network setup

# or choose explicitly
npx dsh-network setup lan
npx dsh-network setup tailscale
npx dsh-network setup custom --url https://dsh.example.com
```

For LAN use, the pairing URL can be HTTP within the trusted local network. For Tailnet, `dsh-network` configures Tailscale Serve. For a public host, bring your own HTTPS reverse proxy and generate a pairing QR with its final HTTPS address. Do not expose the DSH development port `3080` to the public internet.

## Run it

Requirements:

- macOS with Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- iOS 17 or newer for the app target
- An accessible DSH host

Generate the Xcode project and run it on a simulator or device:

```sh
cd dsh-ios
xcodegen generate
open DshApp.xcodeproj
```

You can also build from the command line:

```sh
xcodebuild \
  -project DshApp.xcodeproj \
  -scheme DshApp \
  -destination 'generic/platform=iOS Simulator' \
  build
```

### Pair a host

1. Start or select the DSH host you trust.
2. In Pocket Dolphin · DSH, scan its one-time pairing QR code, paste its pairing link, or enter its base URL manually.
3. Select the host and open a workspace or session.

When a host supports [`dsh-network`](https://www.npmjs.com/package/dsh-network), scan the QR code printed by its setup command. The access token is short-lived; refresh credentials are stored in Keychain.

## Development

The repository contains both the native app and a lightweight Swift client library.

```text
App/                 SwiftUI app, state, pairing, networking, and views
Sources/DshClient/   RPC and event-stream client shared with the CLI spike
Tests/               Unit tests for transcript, workspace, host, and auth behavior
assets/store/        App Store screenshots, review sheet, site source, and exports
fastlane/            TestFlight and App Store metadata automation
project.yml          XcodeGen project definition
```

The app and the DSH web client are peer clients of the same host protocol:

- RPC: `POST /api/{method}`
- Event streams: `ws://host/api/events.mux` and `ws://host/api/events.host`

For a small protocol smoke test:

```sh
swift run dsh-spike http://127.0.0.1:3080
```

## App Store materials

The repository keeps the source pages, generated App Store screenshots, product page, and privacy page under [`assets/store`](assets/store). Review the asset bundle locally with:

```sh
open assets/store/review.html
open assets/store/site/index.html
```

The published product page is available at [impai.me/apps/dsh-remote](https://impai.me/apps/dsh-remote/).

## Contributing

Issues and focused pull requests are welcome. Please keep changes compatible with a user-controlled host, avoid adding tracking or a relay, and do not introduce DeepSeek trademarks or official visual assets without authorization.

## License

MIT. See [LICENSE](LICENSE).

# Evaluetron Worker

Private, unlicensed Flutter client that turns a user-controlled phone or Linux computer into an
Evaluetron fleet node. It is intentionally not published to pub.dev (`publish_to: none`) and this
repository intentionally has no open-source license.

The first delivery target is an Android Arm64 sideload on the Galaxy S22. The same adaptive UI and
domain code target Linux Arm64 on a Raspberry Pi with mouse and keyboard. iOS, macOS, and Windows
project shells exist so store and desktop work can proceed without splitting the product.

## What the MVP does

- Scans a Fleet enrollment QR on Android/iOS, or accepts the same URI by paste/manual entry.
- Exchanges the short-lived `eve_` enrollment once inside the app—never through Termux or a shell.
- Stores only the returned `evn_` node credential through platform secure storage.
- Registers the paired node and heartbeats during an explicit, visible Start/Stop session.
- Serves a bounded private job endpoint and accepts only replay-protected, authenticated dispatches
  from the paired brain.
- Shows node identity, roles, connection state, distribution policy, and verified runtime capability.
- Uses bottom navigation on phones and a navigation rail for keyboard/mouse desktop layouts.

It does **not** execute inference yet. Registration advertises an empty generator list and
`runtimeReady: false`; the UI says the model adapter is not installed. A runtime adapter must not
advertise a generator until a local health probe proves that it can execute it.

## Managed private network

The app has a separate Managed Network surface and Android VPN privilege boundary. Version 2 pairing
is explicitly network-first: generate a Nebula key on-device, enroll its public key over the public
HTTPS Brain origin, securely store the issued profile, obtain VPN consent, verify the tunnel, then
consume the application token over the private fleet address.

The pinned Nebula packet engine is not linked yet, so this build truthfully reports **Tunnel engine
not installed**, never establishes a TUN interface, and does not consume a version 2 application
token. Its approved future route is the single private Brain host—never a default route or DNS
capture. See [docs/NEBULA.md](docs/NEBULA.md) for protocol, source audit, and MIT obligations.

## Enrollment contract

Fleet emits one of:

```text
evaluetron-worker://enroll?v=1&brain=<absolute-percent-encoded-fleet-base>&token=<eve_-token>

evaluetron-worker://enroll?v=2&brain=<public-https-origin>&fleet=<private-fleet-origin>&token=<eve_-token>&networkToken=<one-time-network-token>
```

The URI is scanned or pasted inside the app, not registered as a general-purpose operating-system
deep link. Parsing rejects unknown versions, non-HTTP(S) brain addresses, embedded credentials,
fragments, malformed tokens, and public cleartext HTTP.

HTTPS uses normal platform certificate verification; there is no certificate bypass. Cleartext HTTP
is accepted only for literal loopback, RFC1918, or link-local addresses and the dialog requires an
additional user acknowledgement. Android must permit cleartext at the manifest layer because its
network-security configuration cannot express dynamic private IP ranges; the app-layer parser is the
enforced range boundary. iOS permits local networking only, not arbitrary ATS loads.

The one-time token is held only in the pairing flow and Authorization header. It is not persisted or
logged. The durable registration is stored with `flutter_secure_storage` (Android Keystore-backed
encrypted storage, Apple Keychain, and the platform secure backend on desktop).

## Distribution modes

One codebase does not mean one capability policy:

- **Full node:** sideloaded Android and Linux builds may use bundled or operator-installed,
  signature-verified native runtime/model adapters. Sessions remain explicit and stoppable.
- **Store-safe:** Play/App Store builds permit only user-visible foreground work, approved static
  executable code, and models handled as data assets. They do not download executable plug-ins or
  claim persistent background execution that the platform does not provide.

The Android store track will need a declared foreground-service type, persistent notification,
user-initiated start, immediate stop action, and current target SDK review before submission. The
Apple track will keep inference foreground/user-driven and cannot act as a general background
service or download executable model runtimes.

Policy references:

- [Google Play foreground service requirements](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Android foreground service guidance](https://developer.android.com/develop/background-work/services/fgs)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Flutter supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms)

## Development

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

For Raspberry Pi, use a supported Debian/Ubuntu Arm64 environment with Flutter's Linux desktop
prerequisites and a working Secret Service/libsecret implementation for credential storage.

## Architecture

Feature boundaries are deliberately small:

- `features/pairing/domain`: strict pure enrollment parsing and registration value objects.
- `features/pairing/data`: bounded HTTP exchange and secure credential-store abstraction.
- `features/network`: managed enrollment, secret storage, one-host route policy, native tunnel
  boundary, consent, and status.
- `features/worker/domain`: full-node versus store-safe capability policy.
- `features/worker/data`: fleet registration/heartbeat client.
- `features/worker/presentation`: lifecycle controller and adaptive Material UI.

Network clients use bounded response sizes, 15-second deadlines, no redirects, and default TLS
verification. Brain-to-worker jobs use the shared `hmac-sha256-v1` protocol: method, path, timestamp,
nonce, and exact body hash are authenticated with a key derived from the node credential. Requests
outside the clock window, duplicate nonces, modified bodies, oversized inputs, and concurrent work
beyond local capacity are rejected. The controller owns the foreground session and stops both the
job listener and heartbeat on Stop/dispose. No credential is passed into widgets or displayed.

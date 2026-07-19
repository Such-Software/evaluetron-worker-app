# Managed Nebula integration

## Current status

The Worker app contains a compile-ready managed-network boundary, not a working Nebula tunnel.

Implemented:

- Typed compatibility with `POST /enroll/nebula`: one-time bearer token plus
  `{"publicKey":"..."}`, returning version, CA certificate, host certificate, opaque config, mesh
  metadata, endpoint, and brain IP.
- A network-first version 2 Worker URI. It retains the public HTTPS network enrollment origin,
  private fleet origin, `eve_` application enrollment, and network enrollment token only in memory.
- Required sequencing: native key generation, public network enrollment, secure network-secret
  storage, explicit VPN consent, verified tunnel start, and only then private fleet enrollment.
- Secure-storage abstraction for the host private key, certificate material, and opaque
  Brain-issued configuration. One-time enrollment tokens are never part of durable models.
- A route policy that derives exactly one host route (`/32` or `/128`) from the managed Brain CIDR.
  It rejects public addresses, malformed CIDRs, and default routes.
- Android `VpnService` declaration, method-channel inspection, and system VPN-consent result
  handling.
- User-visible states, errors, Start/Stop controls, and a clear statement that no tunnel is active.

Not implemented:

- Nebula X25519/P256 key generation.
- A pinned gomobile Nebula framework or packet engine.
- Certificate/key verification through Nebula's parser.
- TUN establishment or packet forwarding.
- iOS Network Extension entitlement and packet-tunnel provider.
- Linux process supervision for the pinned Arm64 Nebula binary.

The Android service intentionally never calls `VpnService.Builder.establish()`. A TUN device without
an attached packet engine would capture and discard matching traffic. Flutter and native code both
reject tunnel start until an audited engine reports itself linked.

## Enrollment and trust boundaries

Version 2 pairing is:

1. Parse one QR payload in memory.
2. Ask the native Nebula engine to create the host keypair. The private key never leaves the device.
3. Send only the public key to the public HTTPS Brain enrollment endpoint.
4. Validate the bounded response and private `managed.brainIp`; retain the raw config as opaque
   provenance rather than interpreting Linux file paths in Flutter.
5. Store the private key, CA, certificate, opaque config, and metadata in platform secure storage.
6. Explain the route and ask the user for operating-system VPN consent.
7. Start the native engine and require a positive running state.
8. Exchange the separate `eve_` token against the private fleet address.

Version 1 LAN pairing remains supported and goes directly to application enrollment. It permits
cleartext HTTP only to literal loopback, RFC1918, unique-local, or link-local addresses.

No network token, private key, application enrollment token, or node credential is logged or shown.
No CA signing key is ever accepted by the app.

## Route policy

Evaluetron Worker is not a consumer VPN and must not become an exit node.

- Add only the host address from `managed.brainIp` as `/32` or `/128`.
- Do not add `0.0.0.0/0`, `::/0`, the whole Nebula certificate subnet, or Brain-provided
  `unsafe_routes`.
- Do not install DNS resolvers.
- Do not enable IP forwarding.
- Exclude the app's own outer UDP socket from the VPN before establishing the interface to prevent
  a routing loop.
- Preserve normal application-layer TLS validation.

Any future expansion beyond the one-host route requires an explicit product/security review and a
new versioned policy.

## Upstream source audit

Audited 2026-07-19:

- [Nebula core](https://github.com/slackhq/nebula), including its supported-platform overview,
  certificate model, lighthouses, and MIT license.
- [DefinedNet Mobile Nebula](https://github.com/DefinedNet/mobile_nebula) at
  `9f7ac7dedb5be38d4bddc96ca5266173b2704434`.
- Mobile Android architecture: a discoverable `VpnService` protected by the system-only
  `android.permission.BIND_VPN_SERVICE` permission, with unsupported always-on mode explicitly
  disabled; route/address construction through `VpnService.Builder`;
  gomobile-generated bindings that receive the detached TUN file descriptor; secure private-key
  files backed by Android Keystore; and explicit stop/rebind lifecycle handling.

No Mobile Nebula application code was copied. At the audited commit, that repository did not expose
a root license file. Its application-specific Kotlin, Swift, Dart, and Go wrapper code therefore
must not be vendored or adapted until reusable-license terms are confirmed. The separately imported
`github.com/slackhq/nebula` core is MIT licensed.

## MIT obligations

Nebula core's MIT license allows private/commercial use, modification, distribution, sublicensing,
and sale. Distribution of a binary or substantial source portion must preserve Nebula's copyright
and permission notice. The project must also retain the warranty disclaimer.

Before linking the engine:

1. Pin an exact reviewed Nebula tag/commit and gomobile toolchain.
2. Generate reproducible Android AAR and Apple XCFramework artifacts in private CI.
3. Record checksums, source revision, Go module graph, and SBOM.
4. Include the Nebula MIT text in shipped third-party notices and store/legal surfaces.
5. Run Nebula certificate/key/config verification before secure persistence.
6. Add native integration tests proving stop/revoke, no default route, outer-socket protection,
   network changes, and permission denial.

`THIRD_PARTY_NOTICES.md` reserves the correct notice now. It does not license Evaluetron Worker,
which remains private and unlicensed.

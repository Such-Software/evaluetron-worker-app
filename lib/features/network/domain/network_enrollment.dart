import 'managed_network.dart';

class NetworkEnrollmentDraft {
  const NetworkEnrollmentDraft({
    required this.brainBaseUrl,
    required this.oneTimeToken,
  });

  final Uri brainBaseUrl;

  /// Ephemeral bearer value. It must never enter durable state or diagnostics.
  final String oneTimeToken;
}

abstract interface class NebulaEngineBoundary {
  Future<NebulaEngineSupport> inspect();
  Future<NebulaKeyPair> generateKeyPair();
  Future<VpnConsent> requestVpnConsent();
  Future<void> start(ManagedNetworkSecret secret);
  Future<void> stop();
}

class NebulaEngineSupport {
  const NebulaEngineSupport({
    required this.platformSupported,
    required this.engineLinked,
    required this.vpnPermissionGranted,
    required this.running,
    this.detail,
  });

  final bool platformSupported;
  final bool engineLinked;
  final bool vpnPermissionGranted;
  final bool running;
  final String? detail;
}

enum VpnConsent { granted, denied, cancelled, unsupported }

abstract interface class ManagedNetworkEnrollmentClient {
  Future<ManagedNetworkProfile> enroll({
    required Uri brainBaseUrl,
    required String oneTimeToken,
    required String publicKeyPem,
  });
}

abstract interface class ManagedNetworkSecretStore {
  Future<ManagedNetworkSecret?> read();
  Future<void> write(ManagedNetworkSecret secret);
  Future<void> clear();
}

class ManagedNetworkEnrollmentService {
  const ManagedNetworkEnrollmentService({
    required this.engine,
    required this.client,
    required this.store,
  });

  final NebulaEngineBoundary engine;
  final ManagedNetworkEnrollmentClient client;
  final ManagedNetworkSecretStore store;

  Future<ManagedNetworkProfile> enroll(NetworkEnrollmentDraft draft) async {
    final support = await engine.inspect();
    if (!support.platformSupported || !support.engineLinked) {
      throw const NetworkEnrollmentException(
        'The audited Nebula engine is not available in this build.',
      );
    }
    final keyPair = await engine.generateKeyPair();
    final profile = await client.enroll(
      brainBaseUrl: draft.brainBaseUrl,
      oneTimeToken: draft.oneTimeToken,
      publicKeyPem: keyPair.publicKeyPem,
    );
    // Force route validation before persisting key material.
    profile.routePolicy;
    await store.write(
      ManagedNetworkSecret(
        profile: profile,
        privateKeyPem: keyPair.privateKeyPem,
      ),
    );
    return profile;
  }

  Future<ManagedNetworkProfile> enrollAndConnect(
    NetworkEnrollmentDraft draft,
  ) async {
    final profile = await enroll(draft);
    final consent = await engine.requestVpnConsent();
    if (consent != VpnConsent.granted) {
      throw NetworkEnrollmentException(
        consent == VpnConsent.denied
            ? 'VPN permission was denied.'
            : 'VPN permission is required before private fleet pairing.',
      );
    }
    final secret = await store.read();
    if (secret == null) {
      throw const NetworkEnrollmentException(
        'Managed network keys were not available after enrollment.',
      );
    }
    await engine.start(secret);
    final support = await engine.inspect();
    if (!support.running) {
      throw const NetworkEnrollmentException(
        'Managed network did not become active.',
      );
    }
    return profile;
  }
}

class NetworkEnrollmentException implements Exception {
  const NetworkEnrollmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

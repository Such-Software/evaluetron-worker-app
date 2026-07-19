import 'dart:convert';

import 'package:evaluetron_worker_app/features/network/data/managed_network_store.dart';
import 'package:evaluetron_worker_app/features/network/domain/managed_network.dart';
import 'package:evaluetron_worker_app/features/network/domain/network_enrollment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManagedRoutePolicy', () {
    test('limits the tunnel to one private brain host route', () {
      expect(ManagedRoutePolicy.forBrain('192.168.100.1/24').routes, [
        '192.168.100.1/32',
      ]);
      expect(ManagedRoutePolicy.forBrain('fd00::10/64').routes, [
        'fd00::10/128',
      ]);
    });

    test('rejects public addresses and route-shaped input', () {
      for (final input in [
        '8.8.8.8',
        '0.0.0.0',
        '192.168.1.1/33',
        '192.168.1.1/not-a-prefix',
      ]) {
        expect(
          () => ManagedRoutePolicy.forBrain(input),
          throwsFormatException,
          reason: input,
        );
      }
    });
  });

  test(
    'enrollment stores the private key but never the one-time token',
    () async {
      final calls = <String>[];
      final engine = _FakeEngine(calls);
      final store = MemoryManagedNetworkSecretStore();
      final client = _FakeClient(calls);
      final service = ManagedNetworkEnrollmentService(
        engine: engine,
        client: client,
        store: store,
      );

      final result = await service.enrollAndConnect(
        NetworkEnrollmentDraft(
          brainBaseUrl: Uri.parse('https://brain.example'),
          oneTimeToken: 'network_token_that_must_never_be_stored_1234',
        ),
      );

      expect(result.metadata.brainIp, '192.168.100.1/24');
      expect(store.value?.privateKeyPem, contains('PRIVATE KEY'));
      expect(
        jsonEncode(store.value?.toJson()),
        isNot(contains('network_token_that_must_never_be_stored_1234')),
      );
      expect(calls, [
        'inspect',
        'keygen',
        'enroll',
        'consent',
        'start',
        'inspect',
      ]);
    },
  );
}

ManagedNetworkProfile testManagedProfile() {
  return ManagedNetworkProfile.fromJson({
    'version': '1.10.3',
    'caPem':
        '-----BEGIN NEBULA CERTIFICATE-----\nca\n-----END NEBULA CERTIFICATE-----',
    'certificatePem':
        '-----BEGIN NEBULA CERTIFICATE-----\nhost\n-----END NEBULA CERTIFICATE-----',
    'opaqueConfig': 'pki:\n  ca: /managed/ca.crt\n',
    'metadata': {
      'meshName': 'evaluetron',
      'endpoint': 'vpn.example:4242',
      'brainIp': '192.168.100.1/24',
    },
  });
}

class _FakeEngine implements NebulaEngineBoundary {
  _FakeEngine(this.calls);

  final List<String> calls;
  bool running = false;

  @override
  Future<NebulaKeyPair> generateKeyPair() async {
    calls.add('keygen');
    return const NebulaKeyPair(
      publicKeyPem:
          '-----BEGIN NEBULA X25519 PUBLIC KEY-----\npublic\n-----END NEBULA X25519 PUBLIC KEY-----',
      privateKeyPem:
          '-----BEGIN NEBULA X25519 PRIVATE KEY-----\nprivate\n-----END NEBULA X25519 PRIVATE KEY-----',
    );
  }

  @override
  Future<NebulaEngineSupport> inspect() async {
    calls.add('inspect');
    return NebulaEngineSupport(
      platformSupported: true,
      engineLinked: true,
      vpnPermissionGranted: true,
      running: running,
    );
  }

  @override
  Future<VpnConsent> requestVpnConsent() async {
    calls.add('consent');
    return VpnConsent.granted;
  }

  @override
  Future<void> start(ManagedNetworkSecret secret) async {
    calls.add('start');
    running = true;
  }

  @override
  Future<void> stop() async {
    running = false;
  }
}

class _FakeClient implements ManagedNetworkEnrollmentClient {
  _FakeClient(this.calls);

  final List<String> calls;

  @override
  Future<ManagedNetworkProfile> enroll({
    required Uri brainBaseUrl,
    required String oneTimeToken,
    required String publicKeyPem,
  }) async {
    calls.add('enroll');
    expect(brainBaseUrl, Uri.parse('https://brain.example'));
    expect(oneTimeToken, startsWith('network_'));
    expect(publicKeyPem, contains('PUBLIC KEY'));
    return testManagedProfile();
  }
}

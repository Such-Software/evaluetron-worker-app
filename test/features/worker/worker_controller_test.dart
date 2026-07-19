import 'package:evaluetron_worker_app/features/network/data/managed_network_store.dart';
import 'package:evaluetron_worker_app/features/network/domain/managed_network.dart';
import 'package:evaluetron_worker_app/features/network/domain/network_enrollment.dart';
import 'package:evaluetron_worker_app/features/pairing/data/enrollment_client.dart';
import 'package:evaluetron_worker_app/features/pairing/data/secure_node_credential_store.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/fleet_client.dart';
import 'package:evaluetron_worker_app/features/worker/data/worker_job_server.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/presentation/worker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registration = NodeRegistration(
    brainBaseUrl: Uri.parse('https://fleet.example'),
    nodeId: 'node-1',
    credentialId: 'credential-1',
    nodeName: 'phone-s22',
    nodeToken: 'evn_secret',
    roles: const ['worker'],
  );

  test(
    'loads securely stored registration and controls explicit sessions',
    () async {
      final fleet = _FakeFleetClient();
      final controller = WorkerController(
        credentials: MemoryNodeCredentialStore(registration),
        enrollmentClient: _FakeEnrollmentClient(registration),
        fleetClient: fleet,
        jobServer: _FakeWorkerServer(),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.registration?.nodeName, 'phone-s22');
      expect(controller.sessionStatus, WorkerSessionStatus.stopped);

      await controller.start();
      expect(controller.sessionStatus, WorkerSessionStatus.running);
      expect(fleet.registered, 1);
      expect(controller.message, contains('advertises no generators'));

      await controller.stop();
      expect(controller.sessionStatus, WorkerSessionStatus.stopped);
    },
  );

  test('stores only the returned node registration after pairing', () async {
    final store = MemoryNodeCredentialStore();
    final controller = WorkerController(
      credentials: store,
      enrollmentClient: _FakeEnrollmentClient(registration),
      fleetClient: _FakeFleetClient(),
      jobServer: _FakeWorkerServer(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final paired = await controller.pair(
      EnrollmentDraft.fromFields(
        brain: 'https://fleet.example',
        token: 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
      ),
    );

    expect(paired, isTrue);
    expect(store.value, same(registration));
    expect(store.value?.nodeToken, startsWith('evn_'));
  });

  test(
    'v2 never consumes app enrollment before the network is active',
    () async {
      final appEnrollment = _CountingEnrollmentClient(registration);
      final controller = WorkerController(
        credentials: MemoryNodeCredentialStore(),
        enrollmentClient: appEnrollment,
        fleetClient: _FakeFleetClient(),
        jobServer: _FakeWorkerServer(),
        networkEnrollmentService: ManagedNetworkEnrollmentService(
          engine: _UnavailableNebulaEngine(),
          client: _NeverNetworkClient(),
          store: MemoryManagedNetworkSecretStore(),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final draft = EnrollmentDraft.parseUri(
        Uri(
          scheme: 'evaluetron-worker',
          host: 'enroll',
          queryParameters: {
            'v': '2',
            'brain': 'https://brain.example',
            'fleet': 'http://192.168.100.1:8082',
            'token': 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
            'networkToken': 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN123456',
          },
        ).toString(),
      );

      expect(await controller.pair(draft), isFalse);
      expect(appEnrollment.calls, 0);
      expect(controller.message, contains('Nebula engine is not available'));
    },
  );
}

class _FakeEnrollmentClient implements EnrollmentClient {
  _FakeEnrollmentClient(this.registration);

  final NodeRegistration registration;

  @override
  Future<NodeRegistration> enroll(EnrollmentDraft draft) async => registration;
}

class _CountingEnrollmentClient extends _FakeEnrollmentClient {
  _CountingEnrollmentClient(super.registration);

  int calls = 0;

  @override
  Future<NodeRegistration> enroll(EnrollmentDraft draft) async {
    calls++;
    return super.enroll(draft);
  }
}

class _FakeFleetClient implements FleetClient {
  int registered = 0;

  @override
  Future<void> heartbeat(NodeRegistration registration) async {}

  @override
  Future<void> register(
    NodeRegistration registration,
    WorkerAdvertisement advertisement,
  ) async {
    registered++;
  }
}

class _FakeWorkerServer implements WorkerServer {
  @override
  Uri? endpoint;

  @override
  RuntimeDescriptor get runtime => RuntimeDescriptor.unavailable;

  @override
  Future<void> start(NodeRegistration registration) async {
    endpoint = Uri.parse('http://127.0.0.1:8090');
  }

  @override
  Future<void> stop() async {
    endpoint = null;
  }
}

class _UnavailableNebulaEngine implements NebulaEngineBoundary {
  @override
  Future<NebulaKeyPair> generateKeyPair() {
    throw StateError('must not generate');
  }

  @override
  Future<NebulaEngineSupport> inspect() async {
    return const NebulaEngineSupport(
      platformSupported: true,
      engineLinked: false,
      vpnPermissionGranted: false,
      running: false,
    );
  }

  @override
  Future<VpnConsent> requestVpnConsent() {
    throw StateError('must not request consent');
  }

  @override
  Future<void> start(ManagedNetworkSecret secret) {
    throw StateError('must not start');
  }

  @override
  Future<void> stop() async {}
}

class _NeverNetworkClient implements ManagedNetworkEnrollmentClient {
  @override
  Future<ManagedNetworkProfile> enroll({
    required Uri brainBaseUrl,
    required String oneTimeToken,
    required String publicKeyPem,
  }) {
    throw StateError('must not enroll');
  }
}

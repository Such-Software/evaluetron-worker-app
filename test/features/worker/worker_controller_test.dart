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
}

class _FakeEnrollmentClient implements EnrollmentClient {
  _FakeEnrollmentClient(this.registration);

  final NodeRegistration registration;

  @override
  Future<NodeRegistration> enroll(EnrollmentDraft draft) async => registration;
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

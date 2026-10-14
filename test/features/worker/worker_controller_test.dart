import 'dart:async';
import 'dart:io';

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

  // The interval never elapses in a test, so beats are driven explicitly.
  WorkerController sessionController(
    _FakeFleetClient fleet,
    _FakeWorkerServer jobServer,
  ) {
    return WorkerController(
      credentials: MemoryNodeCredentialStore(registration),
      enrollmentClient: _FakeEnrollmentClient(registration),
      fleetClient: fleet,
      jobServer: jobServer,
      heartbeatInterval: const Duration(hours: 1),
    );
  }

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

    expect(paired.paired, isTrue);
    expect(paired.error, isNull);
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

      final result = await controller.pair(
        _managedDraft(fleet: 'http://192.168.100.1:8082'),
      );
      expect(result.paired, isFalse);
      expect(result.error, contains('Nebula engine is not available'));
      expect(appEnrollment.calls, 0);
      expect(controller.message, contains('Nebula engine is not available'));
    },
  );

  test('v2 refuses a QR whose fleet host the brain never issued', () async {
    final appEnrollment = _CountingEnrollmentClient(registration);
    final controller = WorkerController(
      credentials: MemoryNodeCredentialStore(),
      enrollmentClient: appEnrollment,
      fleetClient: _FakeFleetClient(),
      jobServer: _FakeWorkerServer(),
      networkEnrollmentService: ManagedNetworkEnrollmentService(
        engine: _ReadyNebulaEngine(),
        client: _IssuingNetworkClient(),
        store: MemoryManagedNetworkSecretStore(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final result = await controller.pair(
      _managedDraft(fleet: 'http://192.168.100.9:8082'),
    );

    expect(result.paired, isFalse);
    expect(result.error, contains('the brain did not issue'));
    expect(appEnrollment.calls, 0);
  });

  test('v2 consumes the token once the fleet host is proven', () async {
    final appEnrollment = _CountingEnrollmentClient(registration);
    final controller = WorkerController(
      credentials: MemoryNodeCredentialStore(),
      enrollmentClient: appEnrollment,
      fleetClient: _FakeFleetClient(),
      jobServer: _FakeWorkerServer(),
      networkEnrollmentService: ManagedNetworkEnrollmentService(
        engine: _ReadyNebulaEngine(),
        client: _IssuingNetworkClient(),
        store: MemoryManagedNetworkSecretStore(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final result = await controller.pair(
      _managedDraft(fleet: 'http://192.168.100.1:8082'),
    );

    expect(result.paired, isTrue);
    expect(appEnrollment.calls, 1);
  });

  test('proves the runtime before telling the brain what this node serves', () async {
    // Probed at registration rather than once at start-up, because registration
    // runs again after every reconnect and every brain restart. A model server
    // that stopped, or a model deleted while the session was open, is therefore
    // withdrawn at the next beat instead of taking jobs it can no longer serve.
    final fleet = _FakeFleetClient();
    final jobServer = _FakeWorkerServer()
      ..probed = RuntimeDescriptor.serving(
        models: {
          'llm': ['qwen3:8b'],
        },
        methods: {
          'llm': ['ollama'],
        },
      );
    final controller = sessionController(fleet, jobServer);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.start();

    expect(jobServer.probes, 1);
    expect(fleet.advertised.single.models['llm'], ['qwen3:8b']);
  });

  test(
    'withdraws a runtime that has gone away, at the next registration',
    () async {
      final fleet = _FakeFleetClient()
        ..heartbeatFailure = const FleetException(
          'not registered',
          failure: FleetFailure.unregistered,
        );
      final jobServer = _FakeWorkerServer()
        ..probed = RuntimeDescriptor.serving(
          models: {
            'llm': ['qwen3:8b'],
          },
          methods: {
            'llm': ['ollama'],
          },
        );
      final controller = sessionController(fleet, jobServer);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.start();
      expect(fleet.advertised.single.ready, isTrue);

      // One beat to discover the brain has forgotten this node, a second to
      // re-register — which is the moment the withdrawn runtime is reported.
      await controller.beat();
      expect(controller.sessionStatus, WorkerSessionStatus.reconnecting);
      // The runtime disappears before the reconnect registration.
      jobServer.probed = RuntimeDescriptor.unavailable;
      fleet.heartbeatFailure = null;
      await controller.beat();

      expect(fleet.registered, 2);
      expect(fleet.advertised.last.ready, isFalse);
      expect(fleet.advertised.last.generators, isEmpty);
    },
  );

  test(
    'withdraws a lost model on a healthy heartbeat and republishes recovery',
    () async {
      final fleet = _FakeFleetClient();
      final jobServer = _FakeWorkerServer()
        ..probed = RuntimeDescriptor.serving(
          models: {
            'llm': ['first'],
          },
          methods: {},
        );
      final controller = sessionController(fleet, jobServer);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.start();
      await controller.beat();
      expect(fleet.advertised.last.ready, isTrue);

      jobServer.probed = RuntimeDescriptor.unavailable;
      await controller.beat();
      expect(controller.sessionStatus, WorkerSessionStatus.running);
      expect(fleet.advertised.last.ready, isFalse);

      jobServer.probed = RuntimeDescriptor.serving(
        models: {
          'llm': ['second'],
        },
        methods: {},
      );
      await controller.beat();
      expect(fleet.advertised.last.models['llm'], contains('second'));
      expect(controller.sessionStatus, WorkerSessionStatus.running);
    },
  );

  test('still registers a node whose runtime never answered', () async {
    // A node that serves no generators is still worth registering: it is
    // reachable, it may be carrying sensors, and the brain simply routes
    // generation elsewhere.
    final fleet = _FakeFleetClient();
    final controller = sessionController(fleet, _FakeWorkerServer());
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.start();

    expect(fleet.registered, 1);
    expect(fleet.advertised.single.ready, isFalse);
    expect(controller.sessionStatus, WorkerSessionStatus.running);
  });

  test('re-registers after the brain forgets this worker', () async {
    final fleet = _FakeFleetClient()
      ..heartbeatFailure = const FleetException(
        'not registered',
        failure: FleetFailure.unregistered,
      );
    final jobServer = _FakeWorkerServer();
    final controller = sessionController(fleet, jobServer);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start();
    expect(fleet.registered, 1);

    await controller.beat();
    expect(controller.sessionStatus, WorkerSessionStatus.reconnecting);
    expect(controller.message, contains('brain restarted'));
    expect(jobServer.endpoint, isNotNull);

    fleet.heartbeatFailure = null;
    await controller.beat();
    expect(fleet.registered, 2);
    expect(controller.sessionStatus, WorkerSessionStatus.running);
  });

  test('keeps the session open while the brain is unreachable', () async {
    const unreachable = FleetException(
      'The brain did not answer this device.',
      failure: FleetFailure.unavailable,
    );
    final fleet = _FakeFleetClient()..heartbeatFailure = unreachable;
    final jobServer = _FakeWorkerServer();
    final controller = sessionController(fleet, jobServer);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start();

    fleet.registerFailure = unreachable;
    await controller.beat();
    await controller.beat();

    expect(controller.sessionStatus, WorkerSessionStatus.reconnecting);
    expect(controller.message, contains('Retrying'));
    expect(jobServer.endpoint, isNotNull);
    expect(jobServer.stops, 0);
    expect(fleet.registered, 2);

    fleet.registerFailure = null;
    fleet.heartbeatFailure = null;
    await controller.beat();
    expect(controller.sessionStatus, WorkerSessionStatus.running);
    expect(fleet.registered, 3);
  });

  test('a stop during a beat leaves the session stopped', () async {
    final fleet = _FakeFleetClient()..heartbeatGate = Completer<void>();
    final jobServer = _FakeWorkerServer();
    final controller = sessionController(fleet, jobServer);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start();

    final pending = controller.beat();
    await controller.stop();
    fleet.heartbeatGate!.complete();
    await pending;

    expect(controller.sessionStatus, WorkerSessionStatus.stopped);
    expect(jobServer.endpoint, isNull);
  });

  test('ends the session only when re-registration is refused', () async {
    final fleet = _FakeFleetClient()
      ..heartbeatFailure = const FleetException(
        'unauthorized',
        failure: FleetFailure.unauthorized,
      );
    final jobServer = _FakeWorkerServer();
    final controller = sessionController(fleet, jobServer);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start();

    await controller.beat();
    expect(controller.sessionStatus, WorkerSessionStatus.reconnecting);
    expect(jobServer.stops, 0);

    fleet.registerFailure = const FleetException(
      'unauthorized',
      failure: FleetFailure.unauthorized,
    );
    await controller.beat();

    expect(controller.sessionStatus, WorkerSessionStatus.error);
    expect(controller.message, contains('Pair this device again'));
    expect(jobServer.endpoint, isNull);
    expect(jobServer.stops, 1);
  });

  test('reports a local listener failure without discarding pairing', () async {
    final controller = WorkerController(
      credentials: MemoryNodeCredentialStore(registration),
      enrollmentClient: _FakeEnrollmentClient(registration),
      fleetClient: _FakeFleetClient(),
      jobServer: _FailingWorkerServer(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.start();

    expect(controller.registration, same(registration));
    expect(controller.sessionStatus, WorkerSessionStatus.error);
    expect(controller.message, contains('Could not open the Worker listener'));
  });
}

EnrollmentDraft _managedDraft({required String fleet}) {
  return EnrollmentDraft.parseUri(
    Uri(
      scheme: 'evaluetron-worker',
      host: 'enroll',
      queryParameters: {
        'v': '2',
        'brain': 'https://brain.example',
        'fleet': fleet,
        'token': 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
        'networkToken': 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN123456',
      },
    ).toString(),
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
  final advertised = <RuntimeDescriptor>[];
  FleetException? registerFailure;
  FleetException? heartbeatFailure;
  Completer<void>? heartbeatGate;

  @override
  Future<void> heartbeat(NodeRegistration registration) async {
    final gate = heartbeatGate;
    if (gate != null) await gate.future;
    final failure = heartbeatFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> register(
    NodeRegistration registration,
    WorkerAdvertisement advertisement,
  ) async {
    registered++;
    advertised.add(advertisement.runtime);
    final failure = registerFailure;
    if (failure != null) throw failure;
  }
}

class _FakeWorkerServer implements WorkerServer {
  int stops = 0;
  int probes = 0;
  RuntimeDescriptor probed = RuntimeDescriptor.unavailable;

  @override
  Uri? endpoint;

  @override
  RuntimeDescriptor get runtime => probed;

  @override
  Future<RuntimeDescriptor> probeRuntime() async {
    probes++;
    return probed;
  }

  @override
  Future<void> start(NodeRegistration registration) async {
    endpoint = Uri.parse('http://127.0.0.1:8090');
  }

  @override
  Future<void> stop() async {
    stops++;
    endpoint = null;
  }
}

class _FailingWorkerServer extends _FakeWorkerServer {
  @override
  Future<void> start(NodeRegistration registration) {
    throw const SocketException('address already in use');
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

class _ReadyNebulaEngine implements NebulaEngineBoundary {
  bool running = false;

  @override
  Future<NebulaKeyPair> generateKeyPair() async {
    return const NebulaKeyPair(
      publicKeyPem:
          '-----BEGIN NEBULA X25519 PUBLIC KEY-----\npublic\n-----END NEBULA X25519 PUBLIC KEY-----',
      privateKeyPem:
          '-----BEGIN NEBULA X25519 PRIVATE KEY-----\nprivate\n-----END NEBULA X25519 PRIVATE KEY-----',
    );
  }

  @override
  Future<NebulaEngineSupport> inspect() async {
    return NebulaEngineSupport(
      platformSupported: true,
      engineLinked: true,
      vpnPermissionGranted: true,
      running: running,
    );
  }

  @override
  Future<VpnConsent> requestVpnConsent() async => VpnConsent.granted;

  @override
  Future<void> start(ManagedNetworkSecret secret) async {
    running = true;
  }

  @override
  Future<void> stop() async {
    running = false;
  }
}

/// Issues the profile a brain at 192.168.100.1 would sign.
class _IssuingNetworkClient implements ManagedNetworkEnrollmentClient {
  @override
  Future<ManagedNetworkProfile> enroll({
    required Uri brainBaseUrl,
    required String oneTimeToken,
    required String publicKeyPem,
  }) async {
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
      'service': {'group': 'worker', 'serviceUrl': 'http://192.168.100.1:8082'},
    });
  }
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

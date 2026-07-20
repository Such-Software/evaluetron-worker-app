import 'package:evaluetron_worker_app/app/worker_app.dart';
import 'package:evaluetron_worker_app/features/network/data/managed_network_store.dart';
import 'package:evaluetron_worker_app/features/network/domain/managed_network.dart';
import 'package:evaluetron_worker_app/features/network/domain/network_enrollment.dart';
import 'package:evaluetron_worker_app/features/network/presentation/managed_network_controller.dart';
import 'package:evaluetron_worker_app/features/pairing/data/enrollment_client.dart';
import 'package:evaluetron_worker_app/features/pairing/data/secure_node_credential_store.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/fleet_client.dart';
import 'package:evaluetron_worker_app/features/worker/data/worker_job_server.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/presentation/worker_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unpaired phone layout opens app-native enrollment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(MemoryNodeCredentialStore());
    await tester.pumpWidget(
      WorkerApp(
        controller: controller,
        networkController: _networkController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pair this device'), findsOneWidget);
    expect(find.text('Scan a Fleet QR to get started.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-pairing')));
    await tester.pumpAndSettle();
    expect(find.text('Pair this node'), findsOneWidget);
    expect(find.byKey(const Key('enrollment-link-field')), findsOneWidget);
    expect(find.textContaining('complete within the app'), findsOneWidget);
    expect(
      find.textContaining('Camera scanning is available on Android and iOS'),
      findsOneWidget,
    );
    final scan = tester.widget<FilledButton>(
      find.byKey(const Key('scan-enrollment')),
    );
    expect(scan.onPressed, isNull);
  });

  testWidgets(
    'wide layout uses navigation rail and shows verified runtime state',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registration = NodeRegistration(
        brainBaseUrl: Uri.parse('https://fleet.example'),
        nodeId: 'node-1',
        credentialId: 'credential-1',
        nodeName: 'phone-s22',
        nodeToken: 'evn_secret',
        roles: const ['worker'],
      );
      final controller = _controller(
        MemoryNodeCredentialStore(registration),
        registration,
      );
      await tester.pumpWidget(
        WorkerApp(
          controller: controller,
          networkController: _networkController(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('phone-s22'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Runtime status'), findsNothing);
      expect(find.byKey(const Key('start-session')), findsOneWidget);
      expect(find.byKey(const Key('stop-session')), findsNothing);

      await tester.tap(find.text('Network'));
      await tester.pumpAndSettle();
      expect(find.text('Tunnel engine not installed'), findsOneWidget);
      expect(find.text('Not available in this build.'), findsOneWidget);
      expect(find.text('No default route.'), findsNothing);
      expect(find.byKey(const Key('network-refresh')), findsOneWidget);
      expect(find.byKey(const Key('network-start')), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('No default route.'), findsOneWidget);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Capabilities'), findsOneWidget);
      expect(find.text('Node details'), findsOneWidget);
      expect(find.text('None enabled'), findsOneWidget);
      expect(
        find.textContaining('No model runtime is installed'),
        findsNothing,
      );
    },
  );
}

ManagedNetworkController _networkController() {
  return ManagedNetworkController(
    engine: _FakeNebulaEngine(),
    store: MemoryManagedNetworkSecretStore(),
  );
}

WorkerController _controller(
  NodeCredentialStore store, [
  NodeRegistration? registration,
]) {
  return WorkerController(
    credentials: store,
    enrollmentClient: _FakeEnrollmentClient(registration),
    fleetClient: _FakeFleetClient(),
    jobServer: _FakeWorkerServer(),
  );
}

class _FakeEnrollmentClient implements EnrollmentClient {
  _FakeEnrollmentClient(this.registration);

  final NodeRegistration? registration;

  @override
  Future<NodeRegistration> enroll(EnrollmentDraft draft) async {
    return registration ??
        NodeRegistration(
          brainBaseUrl: draft.brainBaseUrl,
          nodeId: 'node',
          credentialId: 'credential',
          nodeName: 'new-node',
          nodeToken: 'evn_secret',
          roles: const ['worker'],
        );
  }
}

class _FakeFleetClient implements FleetClient {
  @override
  Future<void> heartbeat(NodeRegistration registration) async {}

  @override
  Future<void> register(
    NodeRegistration registration,
    WorkerAdvertisement advertisement,
  ) async {}
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

class _FakeNebulaEngine implements NebulaEngineBoundary {
  @override
  Future<NebulaKeyPair> generateKeyPair() {
    throw UnimplementedError();
  }

  @override
  Future<NebulaEngineSupport> inspect() async {
    return const NebulaEngineSupport(
      platformSupported: true,
      engineLinked: false,
      vpnPermissionGranted: false,
      running: false,
      detail: 'Test engine unavailable.',
    );
  }

  @override
  Future<VpnConsent> requestVpnConsent() async => VpnConsent.unsupported;

  @override
  Future<void> start(ManagedNetworkSecret secret) async {}

  @override
  Future<void> stop() async {}
}

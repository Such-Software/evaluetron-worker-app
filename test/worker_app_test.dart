import 'package:evaluetron_worker_app/app/worker_app.dart';
import 'package:evaluetron_worker_app/features/pairing/data/enrollment_client.dart';
import 'package:evaluetron_worker_app/features/pairing/data/secure_node_credential_store.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/fleet_client.dart';
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
    await tester.pumpWidget(WorkerApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Make this device a node'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-pairing')));
    await tester.pumpAndSettle();
    expect(find.text('Pair this node'), findsOneWidget);
    expect(find.byKey(const Key('enrollment-link-field')), findsOneWidget);
    expect(find.textContaining('no shell or Termux steps'), findsOneWidget);
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
    'wide layout uses navigation rail and shows honest runtime state',
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
      await tester.pumpWidget(WorkerApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('phone-s22'), findsOneWidget);
      expect(find.text('Not installed'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.byKey(const Key('start-session')), findsOneWidget);
      expect(find.byKey(const Key('stop-session')), findsOneWidget);
    },
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
  Future<void> register(NodeRegistration registration) async {}
}

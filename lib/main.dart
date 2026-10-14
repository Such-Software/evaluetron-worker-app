import 'package:flutter/material.dart';

import 'app/worker_app.dart';
import 'features/network/data/managed_network_store.dart';
import 'features/network/data/network_enrollment_client.dart';
import 'features/network/data/platform_nebula_engine.dart';
import 'features/network/domain/network_enrollment.dart';
import 'features/network/presentation/managed_network_controller.dart';
import 'features/pairing/data/enrollment_client.dart';
import 'features/pairing/data/secure_node_credential_store.dart';
import 'features/worker/data/fleet_client.dart';
import 'features/worker/data/runtime_settings_store.dart';
import 'features/worker/data/worker_job_server.dart';
import 'features/worker/presentation/runtime_controller.dart';
import 'features/worker/presentation/worker_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final credentials = PlatformSecureNodeCredentialStore();
  final networkEngine = PlatformNebulaEngine();
  final networkStore = PlatformManagedNetworkSecretStore();

  // The runtime is resolved before the first frame so the Worker screen opens
  // showing what this node can actually do, rather than claiming nothing and
  // correcting itself a moment later. A device with no runtime configured — the
  // common case, and every sensor-only node — gets [UnavailableRuntimeAdapter],
  // which is the honest answer rather than a placeholder.
  final runtimeController = RuntimeController(
    store: SecureRuntimeSettingsStore(),
  );
  await runtimeController.initialize();

  runApp(
    WorkerApp(
      controller: WorkerController(
        credentials: credentials,
        enrollmentClient: HttpEnrollmentClient(),
        fleetClient: HttpFleetClient(),
        jobServer: HttpWorkerJobServer(adapter: runtimeController.adapter),
        networkEnrollmentService: ManagedNetworkEnrollmentService(
          engine: networkEngine,
          client: HttpManagedNetworkEnrollmentClient(),
          store: networkStore,
        ),
      ),
      networkController: ManagedNetworkController(
        engine: networkEngine,
        store: networkStore,
      ),
      runtimeController: runtimeController,
    ),
  );
}

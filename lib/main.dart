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
import 'features/worker/data/worker_job_server.dart';
import 'features/worker/domain/runtime_adapter.dart';
import 'features/worker/presentation/worker_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentials = PlatformSecureNodeCredentialStore();
  final networkEngine = PlatformNebulaEngine();
  final networkStore = PlatformManagedNetworkSecretStore();
  runApp(
    WorkerApp(
      controller: WorkerController(
        credentials: credentials,
        enrollmentClient: HttpEnrollmentClient(),
        fleetClient: HttpFleetClient(),
        jobServer: HttpWorkerJobServer(
          adapter: const UnavailableRuntimeAdapter(),
        ),
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
    ),
  );
}

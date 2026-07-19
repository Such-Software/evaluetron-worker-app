import 'package:flutter/material.dart';

import 'app/worker_app.dart';
import 'features/pairing/data/enrollment_client.dart';
import 'features/pairing/data/secure_node_credential_store.dart';
import 'features/worker/data/fleet_client.dart';
import 'features/worker/data/worker_job_server.dart';
import 'features/worker/domain/runtime_adapter.dart';
import 'features/worker/presentation/worker_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final credentials = PlatformSecureNodeCredentialStore();
  runApp(
    WorkerApp(
      controller: WorkerController(
        credentials: credentials,
        enrollmentClient: HttpEnrollmentClient(),
        fleetClient: HttpFleetClient(),
        jobServer: HttpWorkerJobServer(
          adapter: const UnavailableRuntimeAdapter(),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import 'app/worker_app.dart';
import 'features/pairing/data/enrollment_client.dart';
import 'features/pairing/data/secure_node_credential_store.dart';
import 'features/worker/data/fleet_client.dart';
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
      ),
    ),
  );
}

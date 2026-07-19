import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../pairing/data/enrollment_client.dart';
import '../../pairing/data/secure_node_credential_store.dart';
import '../../pairing/domain/enrollment.dart';
import '../../pairing/domain/node_registration.dart';
import '../data/fleet_client.dart';
import '../data/worker_job_server.dart';
import '../domain/capability_policy.dart';

enum WorkerSessionStatus { stopped, starting, running, error }

class WorkerController extends ChangeNotifier {
  WorkerController({
    required NodeCredentialStore credentials,
    required EnrollmentClient enrollmentClient,
    required FleetClient fleetClient,
    required WorkerServer jobServer,
  }) : _credentials = credentials,
       _enrollmentClient = enrollmentClient,
       _fleetClient = fleetClient,
       _jobServer = jobServer;

  final NodeCredentialStore _credentials;
  final EnrollmentClient _enrollmentClient;
  final FleetClient _fleetClient;
  final WorkerServer _jobServer;

  NodeRegistration? registration;
  WorkerSessionStatus sessionStatus = WorkerSessionStatus.stopped;
  DistributionTrack track = DistributionTrack.fullNode;
  String? message;
  bool loading = true;
  Timer? _heartbeat;

  CapabilityPolicy get policy => track == DistributionTrack.fullNode
      ? CapabilityPolicy.fullNode
      : CapabilityPolicy.storeSafe;

  Future<void> initialize() async {
    try {
      registration = await _credentials.read();
    } on Object {
      message = 'Secure credential storage is unavailable on this device.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> pair(EnrollmentDraft draft) async {
    loading = true;
    message = null;
    notifyListeners();
    try {
      final enrolled = await _enrollmentClient.enroll(draft);
      await _credentials.write(enrolled);
      registration = enrolled;
      message = 'Paired as ${enrolled.nodeName}.';
      return true;
    } on EnrollmentException catch (error) {
      message = error.message;
      return false;
    } on Object {
      message = 'Could not save the node credential securely.';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> forgetNode() async {
    await stop();
    await _credentials.clear();
    registration = null;
    message = 'This device no longer holds a node credential.';
    notifyListeners();
  }

  void setTrack(DistributionTrack value) {
    track = value;
    notifyListeners();
  }

  Future<void> start() async {
    final current = registration;
    if (current == null || sessionStatus == WorkerSessionStatus.running) return;
    sessionStatus = WorkerSessionStatus.starting;
    message = null;
    notifyListeners();
    try {
      await _jobServer.start(current);
      final endpoint = _jobServer.endpoint;
      if (endpoint == null) {
        throw const FleetException('Worker job server did not start.');
      }
      await _fleetClient.register(
        current,
        WorkerAdvertisement(endpoint: endpoint, runtime: _jobServer.runtime),
      );
      sessionStatus = WorkerSessionStatus.running;
      message = _jobServer.runtime.ready
          ? 'Connected and ready to accept authenticated jobs.'
          : 'Connected. No model runtime is installed, so this node advertises no generators.';
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        _sendHeartbeat(current);
      });
    } on FleetException catch (error) {
      await _jobServer.stop();
      sessionStatus = WorkerSessionStatus.error;
      message = error.message;
    } on Object {
      await _jobServer.stop();
      sessionStatus = WorkerSessionStatus.error;
      message = 'Could not start the worker session.';
    }
    notifyListeners();
  }

  Future<void> _sendHeartbeat(NodeRegistration current) async {
    try {
      await _fleetClient.heartbeat(current);
    } on Object {
      sessionStatus = WorkerSessionStatus.error;
      message =
          'Heartbeat failed. Stop and restart when the brain is reachable.';
      _heartbeat?.cancel();
      _heartbeat = null;
      await _jobServer.stop();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _jobServer.stop();
    sessionStatus = WorkerSessionStatus.stopped;
    message = 'Worker session stopped on this device.';
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    unawaited(_jobServer.stop());
    super.dispose();
  }
}

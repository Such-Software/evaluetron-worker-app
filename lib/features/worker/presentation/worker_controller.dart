import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../network/domain/network_enrollment.dart';
import '../../pairing/data/enrollment_client.dart';
import '../../pairing/data/secure_node_credential_store.dart';
import '../../pairing/domain/enrollment.dart';
import '../../pairing/domain/node_registration.dart';
import '../../pairing/domain/pairing_result.dart';
import '../data/fleet_client.dart';
import '../data/worker_job_server.dart';
import '../domain/capability_policy.dart';

enum WorkerSessionStatus { stopped, starting, running, reconnecting, error }

class WorkerController extends ChangeNotifier {
  WorkerController({
    required NodeCredentialStore credentials,
    required EnrollmentClient enrollmentClient,
    required FleetClient fleetClient,
    required WorkerServer jobServer,
    ManagedNetworkEnrollmentService? networkEnrollmentService,
    Duration heartbeatInterval = const Duration(seconds: 20),
  }) : _credentials = credentials,
       _enrollmentClient = enrollmentClient,
       _fleetClient = fleetClient,
       _jobServer = jobServer,
       _networkEnrollmentService = networkEnrollmentService,
       _heartbeatInterval = heartbeatInterval;

  /// Retries double the beat interval up to this ceiling, so an unreachable
  /// brain costs a phone little while the session stays open.
  static const _maxRetryDelay = Duration(minutes: 5);
  static const _maxBackoffSteps = 4;

  final NodeCredentialStore _credentials;
  final EnrollmentClient _enrollmentClient;
  final FleetClient _fleetClient;
  final WorkerServer _jobServer;
  final ManagedNetworkEnrollmentService? _networkEnrollmentService;
  final Duration _heartbeatInterval;

  NodeRegistration? registration;
  WorkerSessionStatus sessionStatus = WorkerSessionStatus.stopped;
  DistributionTrack track = DistributionTrack.fullNode;
  String? message;
  bool loading = true;
  Timer? _heartbeat;
  bool _registered = false;
  int _retries = 0;

  CapabilityPolicy get policy => track == DistributionTrack.fullNode
      ? CapabilityPolicy.fullNode
      : CapabilityPolicy.storeSafe;

  /// A session the user has not stopped, whether or not the brain answers.
  bool get _sessionLive =>
      sessionStatus == WorkerSessionStatus.starting ||
      sessionStatus == WorkerSessionStatus.running ||
      sessionStatus == WorkerSessionStatus.reconnecting;

  String get _connectedMessage => _jobServer.runtime.ready
      ? 'Connected and ready to accept authenticated jobs.'
      : 'Connected. No model runtime is installed, so this node advertises no generators.';

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

  Future<PairingResult> pair(EnrollmentDraft draft) async {
    loading = true;
    message = null;
    notifyListeners();
    try {
      final networkDraft = draft.networkEnrollment;
      if (networkDraft != null) {
        final service = _networkEnrollmentService;
        if (service == null) {
          throw const NetworkEnrollmentException(
            'Managed network support is unavailable in this build.',
          );
        }
        final profile = await service.enrollAndConnect(networkDraft);
        if (!profile.authorizesFleetOrigin(draft.brainBaseUrl)) {
          throw const NetworkEnrollmentException(
            'This QR sends the enrollment token to an address the brain did not issue. Create a new Phone QR in Fleet.',
          );
        }
      }
      final enrolled = await _enrollmentClient.enroll(draft);
      await _credentials.write(enrolled);
      registration = enrolled;
      message = 'Paired as ${enrolled.nodeName}.';
      return const PairingResult.success();
    } on EnrollmentException catch (error) {
      message = error.message;
      return PairingResult.failure(error.message);
    } on NetworkEnrollmentException catch (error) {
      message = error.message;
      return PairingResult.failure(error.message);
    } on Object {
      message = 'Could not save the node credential securely.';
      return PairingResult.failure(message);
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
    if (current == null || _sessionLive) return;
    sessionStatus = WorkerSessionStatus.starting;
    message = null;
    notifyListeners();
    try {
      await _jobServer.start(current);
      await _register(current);
      _registered = true;
      _retries = 0;
      sessionStatus = WorkerSessionStatus.running;
      message = _connectedMessage;
      _scheduleBeat();
    } on FleetException catch (error) {
      await _jobServer.stop();
      sessionStatus = WorkerSessionStatus.error;
      message = error.message;
    } on SocketException {
      await _jobServer.stop();
      sessionStatus = WorkerSessionStatus.error;
      message =
          'Could not open the Worker listener on this device. Close another local Worker or restart the app.';
    } on Object {
      await _jobServer.stop();
      sessionStatus = WorkerSessionStatus.error;
      message = 'Could not start the worker session.';
    }
    notifyListeners();
  }

  /// Runs one register-or-heartbeat cycle.
  ///
  /// The brain keeps its worker registry in process, so it answers 404 to a
  /// heartbeat after every restart and expects a fresh registration; a phone
  /// also loses its link routinely. Both keep the session and retry, and only
  /// a credential the brain refuses outright ends it.
  @visibleForTesting
  Future<void> beat() async {
    final current = registration;
    if (current == null || !_sessionLive) return;
    final registered = _registered;
    final failure = await _sendBeat(current, registered: registered);
    // The user may have stopped the session while the call was in flight.
    if (!_sessionLive) return;
    if (failure == null) {
      _registered = true;
      _retries = 0;
      _update(WorkerSessionStatus.running, _connectedMessage);
    } else if (!registered && failure == FleetFailure.unauthorized) {
      await _endSession(
        WorkerSessionStatus.error,
        'The brain refused this node credential. Pair this device again.',
      );
      return;
    } else {
      final forgotten = registered && failure == FleetFailure.unregistered;
      _retry(
        forgotten
            ? 'The brain restarted. Re-registering this node.'
            : 'Lost contact with the brain. Retrying without ending the session.',
        immediate: forgotten,
      );
    }
    _scheduleBeat();
  }

  /// Null when the brain accepted the beat.
  Future<FleetFailure?> _sendBeat(
    NodeRegistration current, {
    required bool registered,
  }) async {
    try {
      if (registered) {
        await _fleetClient.heartbeat(current);
      } else {
        await _register(current);
      }
      return null;
    } on FleetException catch (error) {
      return error.failure;
    } on Object {
      return FleetFailure.unavailable;
    }
  }

  Future<void> stop() {
    return _endSession(
      WorkerSessionStatus.stopped,
      'Worker session stopped on this device.',
    );
  }

  Future<void> _register(NodeRegistration current) async {
    final endpoint = _jobServer.endpoint;
    if (endpoint == null) {
      throw const FleetException('Worker job server did not start.');
    }
    await _fleetClient.register(
      current,
      WorkerAdvertisement(endpoint: endpoint, runtime: _jobServer.runtime),
    );
  }

  void _retry(String text, {bool immediate = false}) {
    _registered = false;
    _retries = immediate ? 0 : _retries + 1;
    _update(WorkerSessionStatus.reconnecting, text);
  }

  void _scheduleBeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    if (!_sessionLive) return;
    final steps = _retries > _maxBackoffSteps ? _maxBackoffSteps : _retries;
    final delay = _heartbeatInterval * (1 << steps);
    _heartbeat = Timer(
      delay > _maxRetryDelay ? _maxRetryDelay : delay,
      () => unawaited(beat()),
    );
  }

  void _update(WorkerSessionStatus status, String text) {
    if (sessionStatus == status && message == text) return;
    sessionStatus = status;
    message = text;
    notifyListeners();
  }

  Future<void> _endSession(WorkerSessionStatus status, String text) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _registered = false;
    _retries = 0;
    // Settled before the listener closes, so a beat awaiting the brain sees a
    // dead session the moment it resumes.
    sessionStatus = status;
    message = text;
    await _jobServer.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _heartbeat = null;
    sessionStatus = WorkerSessionStatus.stopped;
    unawaited(_jobServer.stop());
    super.dispose();
  }
}

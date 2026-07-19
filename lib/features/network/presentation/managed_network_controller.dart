import 'package:flutter/foundation.dart';

import '../domain/managed_network.dart';
import '../domain/network_enrollment.dart';

enum ManagedNetworkStatus {
  loading,
  engineUnavailable,
  notEnrolled,
  consentRequired,
  ready,
  running,
  error,
}

class ManagedNetworkController extends ChangeNotifier {
  ManagedNetworkController({
    required NebulaEngineBoundary engine,
    required ManagedNetworkSecretStore store,
  }) : _engine = engine,
       _store = store;

  final NebulaEngineBoundary _engine;
  final ManagedNetworkSecretStore _store;

  ManagedNetworkStatus status = ManagedNetworkStatus.loading;
  ManagedNetworkProfile? profile;
  NebulaEngineSupport? support;
  String? message;

  Future<void> initialize() async {
    status = ManagedNetworkStatus.loading;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _engine.inspect(),
        _store.read(),
      ]);
      support = results[0]! as NebulaEngineSupport;
      final secret = results[1] as ManagedNetworkSecret?;
      profile = secret?.profile;
      _deriveStatus();
    } on Object {
      status = ManagedNetworkStatus.error;
      message = 'Could not inspect managed network state.';
    }
    notifyListeners();
  }

  void _deriveStatus() {
    final current = support;
    if (current == null ||
        !current.platformSupported ||
        !current.engineLinked) {
      status = ManagedNetworkStatus.engineUnavailable;
      message =
          current?.detail ??
          'The managed tunnel engine is unavailable on this platform.';
    } else if (profile == null) {
      status = ManagedNetworkStatus.notEnrolled;
      message = 'This device has no managed network profile.';
    } else if (!current.vpnPermissionGranted) {
      status = ManagedNetworkStatus.consentRequired;
      message =
          'Android requires your approval before this app can create a VPN interface.';
    } else if (current.running) {
      status = ManagedNetworkStatus.running;
      message = 'Managed network tunnel is active.';
    } else {
      status = ManagedNetworkStatus.ready;
      message = 'Managed network profile is ready but the tunnel is stopped.';
    }
  }

  Future<void> requestConsent() async {
    if (support?.engineLinked != true || profile == null) {
      message =
          'VPN consent will be requested only after a validated profile and audited engine are available.';
      notifyListeners();
      return;
    }
    try {
      final consent = await _engine.requestVpnConsent();
      message = switch (consent) {
        VpnConsent.granted => 'VPN permission granted.',
        VpnConsent.denied => 'VPN permission was denied.',
        VpnConsent.cancelled => 'VPN permission request was cancelled.',
        VpnConsent.unsupported => 'VPN permission is unsupported here.',
      };
      support = await _engine.inspect();
      _deriveStatus();
    } on Object {
      status = ManagedNetworkStatus.error;
      message = 'Could not complete the VPN permission request.';
    }
    notifyListeners();
  }

  Future<void> start() async {
    final secret = await _store.read();
    if (secret == null || support?.engineLinked != true) {
      status = ManagedNetworkStatus.engineUnavailable;
      message =
          'Tunnel start is blocked until an audited Nebula engine and profile are present.';
      notifyListeners();
      return;
    }
    try {
      await _engine.start(secret);
      support = await _engine.inspect();
      _deriveStatus();
    } on NetworkEnrollmentException catch (error) {
      status = ManagedNetworkStatus.error;
      message = error.message;
    } on Object {
      status = ManagedNetworkStatus.error;
      message = 'Managed tunnel could not start.';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    try {
      await _engine.stop();
      support = await _engine.inspect();
      _deriveStatus();
    } on Object {
      status = ManagedNetworkStatus.error;
      message = 'Managed tunnel could not stop cleanly.';
    }
    notifyListeners();
  }

  Future<void> forgetProfile() async {
    await stop();
    await _store.clear();
    profile = null;
    _deriveStatus();
    message =
        'Managed network keys and profile were removed from secure storage.';
    notifyListeners();
  }
}

import 'package:flutter/services.dart';

import '../domain/managed_network.dart';
import '../domain/network_enrollment.dart';

class PlatformNebulaEngine implements NebulaEngineBoundary {
  PlatformNebulaEngine({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.suchsoftware.evaluetron.worker/network');

  final MethodChannel _channel;

  @override
  Future<NebulaEngineSupport> inspect() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('inspect');
      return NebulaEngineSupport(
        platformSupported: result?['platformSupported'] == true,
        engineLinked: result?['engineLinked'] == true,
        vpnPermissionGranted: result?['vpnPermissionGranted'] == true,
        running: result?['running'] == true,
        detail: result?['detail'] as String?,
      );
    } on MissingPluginException {
      return const NebulaEngineSupport(
        platformSupported: false,
        engineLinked: false,
        vpnPermissionGranted: false,
        running: false,
        detail: 'Managed tunnel integration is unavailable on this platform.',
      );
    }
  }

  @override
  Future<NebulaKeyPair> generateKeyPair() {
    throw const NetworkEnrollmentException(
      'Nebula key generation is unavailable until the audited engine is linked.',
    );
  }

  @override
  Future<VpnConsent> requestVpnConsent() async {
    final value = await _channel.invokeMethod<String>('requestVpnConsent');
    return switch (value) {
      'granted' => VpnConsent.granted,
      'denied' => VpnConsent.denied,
      'cancelled' => VpnConsent.cancelled,
      _ => VpnConsent.unsupported,
    };
  }

  @override
  Future<void> start(ManagedNetworkSecret secret) async {
    // No secret crosses the channel before a pinned Nebula engine and profile
    // validator are linked. The native side independently rejects this call.
    throw const NetworkEnrollmentException(
      'The Nebula tunnel engine is not linked in this build.',
    );
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

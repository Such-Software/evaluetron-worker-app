import 'package:flutter/services.dart';

import '../domain/camera_capability.dart';

/// Reads the handset's own optics over a method channel.
///
/// Every node measures itself rather than being described by a table somewhere,
/// because the two figures that matter, concurrency support and switch latency,
/// vary by vendor and product tier with no rule of thumb worth having. A node
/// that reports its own lenses stays correct when the hardware is swapped.
class PlatformCameraProbe implements CameraProbeBoundary {
  PlatformCameraProbe({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.suchsoftware.evaluetron.worker/camera');

  final MethodChannel _channel;

  @override
  Future<CameraCapability> inspect() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('inspect');
      if (result == null) return CameraCapability.unavailable;
      return CameraCapability.fromJson(result);
    } on MissingPluginException {
      return CameraCapability.unavailable;
    } on PlatformException catch (error) {
      return CameraCapability(
        available: false,
        lenses: const [],
        concurrentSupported: false,
        concurrentSets: const [],
        hardwareLevel: 'unknown',
        switchTiming: CameraSwitchTiming.none,
        detail: error.message ?? 'Camera inspection failed.',
      );
    }
  }

  @override
  Future<CameraSwitchTiming> measureSwitch({
    required String firstId,
    required String secondId,
    int rounds = 5,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'measureSwitch',
        <String, Object?>{
          'firstId': firstId,
          'secondId': secondId,
          'rounds': rounds,
        },
      );
      if (result == null) return CameraSwitchTiming.none;
      return CameraSwitchTiming.fromJson(result);
    } on MissingPluginException {
      return CameraSwitchTiming.none;
    } on PlatformException {
      // A refused permission or a camera already in use is an expected outcome
      // here, not a fault: the node simply has no measurement to advertise yet.
      return CameraSwitchTiming.none;
    }
  }
}

import 'package:evaluetron_worker_app/features/worker/data/platform_camera_probe.dart';
import 'package:evaluetron_worker_app/features/worker/domain/camera_capability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recorded from a moto g stylus 2025 over adb, so the expected angles below
/// are what a real handset reports rather than invented figures.
const _moto = <String, Object?>{
  'available': true,
  'concurrentSupported': true,
  'hardwareLevel': 'full',
  'concurrentSets': [
    ['0', '1'],
  ],
  'lenses': [
    {
      'id': '0',
      'facing': 'back',
      'focalLengthMm': 5.56,
      'sensorWidthMm': 8.224,
      'sensorHeightMm': 6.176,
    },
    {
      'id': '1',
      'facing': 'front',
      'focalLengthMm': 2.87,
      'sensorWidthMm': 4.5696,
      'sensorHeightMm': 3.4272,
    },
    {
      'id': '2',
      'facing': 'back',
      'focalLengthMm': 2.13,
      'sensorWidthMm': 4.6592,
      'sensorHeightMm': 3.4944,
    },
  ],
};

/// Recorded from an SM-A176U, which declares no concurrent support at all.
const _a17 = <String, Object?>{
  'available': true,
  'concurrentSupported': false,
  'hardwareLevel': 'limited',
  'concurrentSets': <List<String>>[],
  'lenses': [
    {
      'id': '0',
      'facing': 'back',
      'focalLengthMm': 4.0,
      'sensorWidthMm': 5.2224,
      'sensorHeightMm': 3.9168,
    },
    {
      'id': '1',
      'facing': 'front',
      'focalLengthMm': 3.59,
      'sensorWidthMm': 4.6234,
      'sensorHeightMm': 3.4675,
    },
    {
      'id': '2',
      'facing': 'back',
      'focalLengthMm': 1.4,
      'sensorWidthMm': 2.912,
      'sensorHeightMm': 2.1862,
    },
  ],
};

void main() {
  group('lens geometry', () {
    test('derives angle of view from focal length and sensor width', () {
      final capability = CameraCapability.fromJson(_moto);
      final back = capability.lenses.firstWhere((lens) => lens.id == '0');
      final front = capability.lenses.firstWhere((lens) => lens.id == '1');
      final ultrawide = capability.lenses.firstWhere((lens) => lens.id == '2');

      expect(back.horizontalFovDegrees, closeTo(73.0, 0.5));
      expect(front.horizontalFovDegrees, closeTo(77.1, 0.5));
      expect(ultrawide.horizontalFovDegrees, closeTo(95.1, 0.5));
    });

    test(
      'the front lens is wider than the main one, and far less sensitive',
      () {
        final capability = CameraCapability.fromJson(_moto);
        final back = capability.lenses.firstWhere((lens) => lens.id == '0');
        final front = capability.lenses.firstWhere((lens) => lens.id == '1');

        expect(
          front.horizontalFovDegrees,
          greaterThan(back.horizontalFovDegrees),
        );
        expect(front.sensorAreaMm2, lessThan(back.sensorAreaMm2 / 3));
      },
    );

    test(
      'treats a lens the HAL would not describe as unknown, not as blind',
      () {
        const undescribed = CameraLens(
          id: '9',
          facing: CameraFacing.back,
          focalLengthMm: 0,
          sensorWidthMm: 0,
          sensorHeightMm: 0,
        );

        expect(undescribed.isDescribed, isFalse);
        expect(undescribed.horizontalFovDegrees, 0);
      },
    );
  });

  group('picking a lens for a job', () {
    test('the widest lens is not the one to trust after dark', () {
      final capability = CameraCapability.fromJson(_moto);

      expect(capability.widest(CameraFacing.back)?.id, '2');
      expect(capability.mostSensitive(CameraFacing.back)?.id, '0');
    });

    test('reports nothing for a direction the handset cannot look', () {
      final capability = CameraCapability.fromJson(_a17);

      expect(capability.mostSensitive(CameraFacing.external), isNull);
    });
  });

  group('concurrency', () {
    test('answers pairing from reported sets, not from the feature flag', () {
      final capability = CameraCapability.fromJson(_moto);

      expect(capability.canRunTogether('0', '1'), isTrue);
      // The flag guarantees only the primary pair, so the ultrawide must not be
      // assumed to participate just because the device declares support.
      expect(capability.canRunTogether('1', '2'), isFalse);
    });

    test('a handset without concurrency is worth one lens at a time', () {
      final capability = CameraCapability.fromJson(_a17);

      expect(capability.concurrentSupported, isFalse);
      expect(capability.canRunTogether('0', '1'), isFalse);
      // Its widest lens, and no more, however many it happens to carry.
      expect(capability.simultaneousCoverageDegrees(), closeTo(92.2, 0.5));
    });

    test('the widest lens on the A17 is also its darkest by a wide margin', () {
      final capability = CameraCapability.fromJson(_a17);

      expect(capability.widest(CameraFacing.back)?.id, '2');
      expect(capability.mostSensitive(CameraFacing.back)?.id, '0');
      expect(
        capability.widest(CameraFacing.back)?.sensorAreaMm2,
        lessThan(
          capability.mostSensitive(CameraFacing.back)!.sensorAreaMm2 / 3,
        ),
      );
    });

    test('a concurrent pair is worth the sum of its arcs', () {
      final capability = CameraCapability.fromJson(_moto);

      expect(capability.simultaneousCoverageDegrees(), closeTo(150.0, 1.0));
    });
  });

  group('switch timing', () {
    test('uses the median so one cold open does not set the dwell', () {
      const timing = CameraSwitchTiming(samplesMs: [180, 200, 210, 220, 900]);

      expect(timing.medianMs, 210);
      expect(timing.maxMs, 900);
    });

    test('blind window is the dwell away plus both switches', () {
      const timing = CameraSwitchTiming(samplesMs: [400]);

      expect(timing.blindWindowMs(2000), 2800);
    });

    test('duty cycle sits below half because switching is not free', () {
      const timing = CameraSwitchTiming(samplesMs: [400]);

      expect(timing.dutyCycle(2000), closeTo(0.4167, 0.001));
    });

    test('an unmeasured switch reports zero rather than guessing', () {
      expect(CameraSwitchTiming.none.isMeasured, isFalse);
      expect(CameraSwitchTiming.none.medianMs, 0);
    });
  });

  group('platform boundary', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test(
      'reports unavailable when no platform implementation is present',
      () async {
        const channel = MethodChannel('test/camera-missing');
        final probe = PlatformCameraProbe(channel: channel);

        final capability = await probe.inspect();

        expect(capability.available, isFalse);
        expect(capability.lenses, isEmpty);
      },
    );

    test('parses a device response into described lenses', () async {
      const channel = MethodChannel('test/camera-present');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'inspect' ? _moto : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final probe = PlatformCameraProbe(channel: channel);

      final capability = await probe.inspect();

      expect(capability.available, isTrue);
      expect(capability.lenses, hasLength(3));
      expect(capability.hardwareLevel, 'full');
    });

    test('a refused permission leaves the node with no measurement', () async {
      const channel = MethodChannel('test/camera-denied');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(
              code: 'probe_failed',
              message: 'denied',
            ),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final probe = PlatformCameraProbe(channel: channel);

      final timing = await probe.measureSwitch(firstId: '0', secondId: '1');

      expect(timing.isMeasured, isFalse);
    });
  });

  test('round trips through json so a node can advertise what it measured', () {
    final capability = CameraCapability.fromJson(_moto);

    final restored = CameraCapability.fromJson(capability.toJson());

    expect(restored.lenses, hasLength(3));
    expect(restored.concurrentSets, [
      ['0', '1'],
    ]);
    expect(
      restored.simultaneousCoverageDegrees(),
      closeTo(capability.simultaneousCoverageDegrees(), 0.001),
    );
  });
}

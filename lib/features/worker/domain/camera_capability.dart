import 'dart:math' as math;

/// Which way a lens points. `external` covers USB and similar attachments that
/// are not fixed to the chassis, so their bearing cannot be inferred from the
/// handset's orientation the way front and back can.
enum CameraFacing {
  front,
  back,
  external,
  unknown;

  static CameraFacing parse(Object? value) => switch (value) {
    'front' => CameraFacing.front,
    'back' => CameraFacing.back,
    'external' => CameraFacing.external,
    _ => CameraFacing.unknown,
  };
}

/// One physical lens, described by what the camera HAL reports rather than by
/// a specification sheet.
///
/// Field of view is derived here instead of being read from the platform,
/// because vendors quote diagonal or post-crop figures that do not describe
/// what the sensor actually sees, and because deriving it keeps the arithmetic
/// testable without a handset attached.
class CameraLens {
  const CameraLens({
    required this.id,
    required this.facing,
    required this.focalLengthMm,
    required this.sensorWidthMm,
    required this.sensorHeightMm,
  });

  final String id;
  final CameraFacing facing;
  final double focalLengthMm;
  final double sensorWidthMm;
  final double sensorHeightMm;

  /// Horizontal angle of view in degrees. Zero when the HAL withheld the
  /// figures it needs, which is treated as unknown rather than as a lens that
  /// sees nothing.
  double get horizontalFovDegrees {
    if (focalLengthMm <= 0 || sensorWidthMm <= 0) return 0;
    return 2 * math.atan(sensorWidthMm / (2 * focalLengthMm)) * 180 / math.pi;
  }

  /// Vertical angle of view in degrees, which decides whether a person close to
  /// the node fits in frame and therefore how high the node can be mounted.
  double get verticalFovDegrees {
    if (focalLengthMm <= 0 || sensorHeightMm <= 0) return 0;
    return 2 * math.atan(sensorHeightMm / (2 * focalLengthMm)) * 180 / math.pi;
  }

  /// Stands in for light gathering, which is what decides whether a lens is
  /// usable after dark. Angle of view says nothing about this, and on current
  /// handsets the widest lens is routinely the least sensitive one.
  double get sensorAreaMm2 => sensorWidthMm * sensorHeightMm;

  bool get isDescribed => horizontalFovDegrees > 0;

  factory CameraLens.fromJson(Map<String, Object?> json) => CameraLens(
    id: json['id'] as String? ?? '',
    facing: CameraFacing.parse(json['facing']),
    focalLengthMm: _toDouble(json['focalLengthMm']),
    sensorWidthMm: _toDouble(json['sensorWidthMm']),
    sensorHeightMm: _toDouble(json['sensorHeightMm']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'facing': facing.name,
    'focalLengthMm': focalLengthMm,
    'sensorWidthMm': sensorWidthMm,
    'sensorHeightMm': sensorHeightMm,
  };
}

/// Measured cost of closing one camera and opening another.
///
/// This sets the blind window for any node that has to alternate between lenses
/// because its HAL will not run them together, so it is measured per device
/// rather than assumed: it varies by vendor and there is no useful default.
class CameraSwitchTiming {
  const CameraSwitchTiming({required this.samplesMs});

  final List<double> samplesMs;

  static const none = CameraSwitchTiming(samplesMs: []);

  bool get isMeasured => samplesMs.isNotEmpty;

  double get minMs => isMeasured ? samplesMs.reduce(math.min) : 0;

  double get maxMs => isMeasured ? samplesMs.reduce(math.max) : 0;

  /// Median rather than mean, because a single slow first open after a cold
  /// HAL start would otherwise drag the figure the dwell is chosen from.
  double get medianMs {
    if (!isMeasured) return 0;
    final sorted = [...samplesMs]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// How long an arc is unwatched while the node is looking at the other one:
  /// the dwell it spends away, plus the switch out and the switch back.
  double blindWindowMs(double dwellMs) => dwellMs + 2 * medianMs;

  /// Share of wall-clock time a given arc is actually being watched, which is
  /// below half because switching is not free.
  double dutyCycle(double dwellMs) {
    final cycle = 2 * (dwellMs + medianMs);
    if (cycle <= 0) return 0;
    return dwellMs / cycle;
  }

  factory CameraSwitchTiming.fromJson(Map<String, Object?> json) =>
      CameraSwitchTiming(
        samplesMs: (json['samplesMs'] as List<Object?>? ?? const [])
            .map(_toDouble)
            .where((sample) => sample > 0)
            .toList(growable: false),
      );

  Map<String, Object?> toJson() => {'samplesMs': samplesMs};
}

/// What one node can see, advertised to the brain the same way its generators
/// are.
///
/// A camera node is only routable if the brain knows its optics, so this is a
/// capability report rather than a diagnostic: two handsets of the same age
/// disagree about concurrent capture, and their lenses differ enough that
/// aiming cannot be planned from the model name.
class CameraCapability {
  const CameraCapability({
    required this.available,
    required this.lenses,
    required this.concurrentSupported,
    required this.concurrentSets,
    required this.hardwareLevel,
    required this.switchTiming,
    this.detail,
  });

  final bool available;
  final List<CameraLens> lenses;

  /// Whether the device declares `android.hardware.camera.concurrent`. False
  /// means the node can only watch one arc at a time and must alternate.
  final bool concurrentSupported;

  /// The lens id combinations the HAL will actually run together. The feature
  /// flag alone guarantees only the primary front and back pair, so a node
  /// cannot assume any wider lens participates without asking.
  final List<List<String>> concurrentSets;

  final String hardwareLevel;
  final CameraSwitchTiming switchTiming;
  final String? detail;

  static const unavailable = CameraCapability(
    available: false,
    lenses: [],
    concurrentSupported: false,
    concurrentSets: [],
    hardwareLevel: 'unknown',
    switchTiming: CameraSwitchTiming.none,
    detail: 'Camera inspection is unavailable on this platform.',
  );

  Iterable<CameraLens> facing(CameraFacing facing) =>
      lenses.where((lens) => lens.facing == facing && lens.isDescribed);

  /// The lens that gathers the most light for a given direction, which is the
  /// one to trust after dark and the one to give any recognition work.
  CameraLens? mostSensitive(CameraFacing facing) {
    final candidates = this.facing(facing).toList();
    if (candidates.isEmpty) return null;
    return candidates.reduce(
      (best, lens) => lens.sensorAreaMm2 > best.sensorAreaMm2 ? lens : best,
    );
  }

  /// The widest lens for a direction, which covers the most ground but is
  /// routinely the least sensitive one on the same handset.
  CameraLens? widest(CameraFacing facing) {
    final candidates = this.facing(facing).toList();
    if (candidates.isEmpty) return null;
    return candidates.reduce(
      (best, lens) =>
          lens.horizontalFovDegrees > best.horizontalFovDegrees ? lens : best,
    );
  }

  /// Whether two named lenses can run at the same time. Answers from the
  /// reported combinations rather than from the feature flag, because the flag
  /// promises only that some pair works.
  bool canRunTogether(String firstId, String secondId) => concurrentSets.any(
    (set) => set.contains(firstId) && set.contains(secondId),
  );

  /// Sum of the angles a node can watch at one instant, which is what its
  /// coverage is actually worth. Alternating raises the arcs a node visits but
  /// not the arcs it sees at any moment.
  double simultaneousCoverageDegrees() {
    if (lenses.isEmpty) return 0;
    if (!concurrentSupported || concurrentSets.isEmpty) {
      final best = lenses
          .where((lens) => lens.isDescribed)
          .fold<double>(
            0,
            (best, lens) => math.max(best, lens.horizontalFovDegrees),
          );
      return best;
    }
    var best = 0.0;
    for (final set in concurrentSets) {
      final total = set
          .map((id) => lenses.where((lens) => lens.id == id))
          .expand((matches) => matches)
          .where((lens) => lens.isDescribed)
          .fold<double>(0, (sum, lens) => sum + lens.horizontalFovDegrees);
      best = math.max(best, total);
    }
    return best;
  }

  factory CameraCapability.fromJson(Map<String, Object?> json) {
    final lenses = (json['lenses'] as List<Object?>? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((entry) => CameraLens.fromJson(entry.cast<String, Object?>()))
        .toList(growable: false);
    final sets = (json['concurrentSets'] as List<Object?>? ?? const [])
        .whereType<List<Object?>>()
        .map((set) => set.whereType<String>().toList(growable: false))
        .where((set) => set.isNotEmpty)
        .toList(growable: false);
    final timing = json['switchTiming'];
    return CameraCapability(
      available: json['available'] == true,
      lenses: lenses,
      concurrentSupported: json['concurrentSupported'] == true,
      concurrentSets: sets,
      hardwareLevel: json['hardwareLevel'] as String? ?? 'unknown',
      switchTiming: timing is Map<Object?, Object?>
          ? CameraSwitchTiming.fromJson(timing.cast<String, Object?>())
          : CameraSwitchTiming.none,
      detail: json['detail'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'available': available,
    'lenses': lenses.map((lens) => lens.toJson()).toList(growable: false),
    'concurrentSupported': concurrentSupported,
    'concurrentSets': concurrentSets,
    'hardwareLevel': hardwareLevel,
    'switchTiming': switchTiming.toJson(),
    if (detail != null) 'detail': detail,
  };
}

/// The platform boundary, kept narrow so the presentation layer never touches a
/// method channel directly and tests can substitute a recorded device.
abstract interface class CameraProbeBoundary {
  /// Reads lens geometry and concurrency support. Does not need camera
  /// permission, because characteristics are readable without it, so a node can
  /// describe itself before anyone has granted anything.
  Future<CameraCapability> inspect();

  /// Times closing one lens and opening another. Needs camera permission, since
  /// it genuinely opens the devices, so it is separate from `inspect` rather
  /// than folded into it.
  Future<CameraSwitchTiming> measureSwitch({
    required String firstId,
    required String secondId,
    int rounds,
  });
}

double _toDouble(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text) ?? 0,
  _ => 0,
};

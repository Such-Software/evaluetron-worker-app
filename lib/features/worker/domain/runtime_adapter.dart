import 'dart:typed_data';

/// What a node advertises it can execute.
///
/// The brain's router selects a worker by advertised *generator and model*, so a
/// generator listed with no model under it is a generator no job can ever reach:
/// the node registers, heartbeats, looks perfectly healthy, and every request for
/// it fails with "no worker available". That failure has already happened once on
/// the Python worker, which is why [ready] is not something a descriptor may
/// simply assert. It is checked.
class RuntimeDescriptor {
  /// Use [RuntimeDescriptor.serving] for a ready runtime; this constructor exists
  /// for [unavailable] and for the not-ready results a failed probe returns.
  const RuntimeDescriptor({
    required this.generators,
    required this.models,
    required this.methods,
    required this.ready,
  });

  /// A runtime that has proved, by probe, that it can execute what it advertises.
  ///
  /// Throws rather than degrading to `ready: false`, because every field here is
  /// assembled by this application from a probe it just performed: an empty model
  /// list is a programming error at the call site, not a runtime condition, and
  /// silently advertising nothing is precisely the failure that is hard to see.
  factory RuntimeDescriptor.serving({
    required Map<String, List<String>> models,
    required Map<String, List<String>> methods,
  }) {
    if (models.isEmpty) {
      throw ArgumentError.value(
        models,
        'models',
        'A ready runtime must serve something',
      );
    }
    for (final entry in models.entries) {
      if (entry.value.isEmpty) {
        throw ArgumentError.value(
          models,
          'models',
          'Generator "${entry.key}" advertises no model, so no job could reach it',
        );
      }
    }
    return RuntimeDescriptor(
      generators: List.unmodifiable(models.keys),
      models: Map.unmodifiable({
        for (final entry in models.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      methods: Map.unmodifiable({
        for (final entry in methods.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      ready: true,
    );
  }

  final List<String> generators;
  final Map<String, List<String>> models;
  final Map<String, List<String>> methods;
  final bool ready;

  /// The state every runtime starts in, and returns to whenever a probe fails.
  ///
  /// Fail-closed is the whole posture: a node that cannot prove it can execute
  /// something advertises nothing, so the brain routes elsewhere rather than
  /// sending work to a device that will drop it.
  static const unavailable = RuntimeDescriptor(
    generators: [],
    models: {},
    methods: {},
    ready: false,
  );
}

class RuntimeArtifact {
  const RuntimeArtifact({required this.contentType, required this.bytes});

  final String contentType;
  final Uint8List bytes;
}

/// A failure the node is willing to describe to the brain, and through it to a
/// customer.
///
/// Every message here crosses a trust boundary twice, so it must name what went
/// wrong without naming a host, a path, or a model file.
class RuntimeRequestException implements Exception {
  const RuntimeRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class WorkerRuntimeAdapter {
  /// What this node currently advertises. Never optimistic: it reports
  /// [RuntimeDescriptor.unavailable] until a [probe] has succeeded, and returns
  /// to it as soon as one fails.
  RuntimeDescriptor get descriptor;

  /// Ask the runtime what it can actually do, and update [descriptor].
  ///
  /// Separate from construction because a runtime is a moving target: the server
  /// behind it may not be up when the app launches, the model may be pulled or
  /// deleted while a session runs, and a phone changes networks. The session
  /// probes before registration and every heartbeat. Changed capabilities are
  /// re-registered, so healthy network sessions do not retain stale model claims.
  ///
  /// Must not throw. A probe that cannot reach its runtime is an answer —
  /// [RuntimeDescriptor.unavailable] — not an error, because the caller's only
  /// sensible response either way is to advertise nothing.
  Future<RuntimeDescriptor> probe();

  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  );
}

/// A node with no model runtime installed.
///
/// The honest default, and still the right adapter for a device that is only
/// carrying sensors: it advertises nothing and refuses everything, so the brain
/// never routes generation to it.
class UnavailableRuntimeAdapter implements WorkerRuntimeAdapter {
  const UnavailableRuntimeAdapter();

  @override
  RuntimeDescriptor get descriptor => RuntimeDescriptor.unavailable;

  @override
  Future<RuntimeDescriptor> probe() async => RuntimeDescriptor.unavailable;

  @override
  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  ) {
    throw const RuntimeRequestException('No model runtime is available.');
  }
}

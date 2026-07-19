import 'dart:typed_data';

class RuntimeDescriptor {
  const RuntimeDescriptor({
    required this.generators,
    required this.models,
    required this.methods,
    required this.ready,
  });

  final List<String> generators;
  final Map<String, List<String>> models;
  final Map<String, List<String>> methods;
  final bool ready;

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

class RuntimeRequestException implements Exception {
  const RuntimeRequestException(this.message);

  final String message;
}

abstract interface class WorkerRuntimeAdapter {
  RuntimeDescriptor get descriptor;

  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  );
}

class UnavailableRuntimeAdapter implements WorkerRuntimeAdapter {
  const UnavailableRuntimeAdapter();

  @override
  RuntimeDescriptor get descriptor => RuntimeDescriptor.unavailable;

  @override
  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  ) {
    throw const RuntimeRequestException('No model runtime is available.');
  }
}

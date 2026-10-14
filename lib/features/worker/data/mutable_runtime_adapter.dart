import '../domain/runtime_adapter.dart';

/// One runtime reference that outlives the runtimes behind it.
///
/// The job server binds its adapter once, at construction, and a live session
/// must not be torn down because somebody corrected a port. This holds the
/// current implementation behind a stable identity, so changing the runtime
/// configuration swaps what executes work without disturbing the listener, the
/// registration, or the heartbeat.
///
/// Adopting a new runtime resets the advertised descriptor to
/// [RuntimeDescriptor.unavailable] rather than carrying the old one forward. The
/// previous runtime's capabilities say nothing about the new one, and the gap
/// between the swap and the next probe is exactly when an optimistic descriptor
/// would send a job somewhere that cannot serve it.
class MutableRuntimeAdapter implements WorkerRuntimeAdapter {
  MutableRuntimeAdapter([WorkerRuntimeAdapter? initial])
    : _adapter = initial ?? const UnavailableRuntimeAdapter();

  WorkerRuntimeAdapter _adapter;

  /// The runtime currently behind this reference, for a caller that needs to ask
  /// it something the adapter interface does not carry.
  WorkerRuntimeAdapter get current => _adapter;

  void adopt(WorkerRuntimeAdapter adapter) => _adapter = adapter;

  @override
  RuntimeDescriptor get descriptor => _adapter.descriptor;

  @override
  Future<RuntimeDescriptor> probe() => _adapter.probe();

  @override
  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  ) => _adapter.run(generator, parameters);
}

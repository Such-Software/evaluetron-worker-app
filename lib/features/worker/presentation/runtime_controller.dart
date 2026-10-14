import 'package:flutter/foundation.dart';

import '../data/llm_runtime_adapter.dart';
import '../data/mutable_runtime_adapter.dart';
import '../data/runtime_settings_store.dart';
import '../domain/llm_runtime_settings.dart';
import '../domain/runtime_adapter.dart';

/// Builds the runtime behind a set of settings. Injected in tests so a probe can
/// be exercised without a model server.
typedef RuntimeAdapterFactory =
    WorkerRuntimeAdapter Function(LlmRuntimeSettings settings);

/// Owns this node's model runtime: what it is configured to be, whether it
/// answered, and what it therefore advertises.
///
/// Kept apart from [WorkerController] because the two answer different questions
/// and fail independently. A session can be perfectly healthy — paired,
/// registered, heartbeating — while the runtime behind it is down, and a runtime
/// can be up on a node nobody has started. Folding them together produced a
/// single status line that could not say which of the two was wrong.
class RuntimeController extends ChangeNotifier {
  RuntimeController({
    required RuntimeSettingsStore store,
    RuntimeAdapterFactory? buildAdapter,
  }) : _store = store,
       _buildAdapter = buildAdapter ?? _defaultAdapter;

  static LlmRuntimeAdapter _defaultAdapter(LlmRuntimeSettings settings) =>
      LlmRuntimeAdapter(settings: settings);

  final RuntimeSettingsStore _store;
  final RuntimeAdapterFactory _buildAdapter;

  /// The stable reference the job server binds to for the life of the app.
  final MutableRuntimeAdapter adapter = MutableRuntimeAdapter();

  LlmRuntimeSettings? settings;
  bool loading = true;

  /// Set while a probe is in flight, so the screen can say "checking" rather than
  /// flickering through "not ready" on its way to an answer.
  bool probing = false;

  /// Why the last probe failed, in words for the person holding the device.
  ///
  /// Deliberately more specific than anything the brain is told: a person who can
  /// see "the runtime does not serve qwen3:8b" fixes it in a moment, where the
  /// brain needs to know only that this node serves nothing.
  String? failure;

  RuntimeDescriptor get descriptor => adapter.descriptor;

  bool get configured => settings != null;

  Future<void> initialize() async {
    try {
      final stored = await _store.read();
      if (stored != null) _adopt(stored);
    } on Object {
      failure = 'Stored runtime settings could not be read on this device.';
    } finally {
      loading = false;
      notifyListeners();
    }
    if (settings != null) await probe();
  }

  /// Accept new settings, store them, and prove them.
  ///
  /// Stored before the probe rather than after, so a runtime that is merely down
  /// right now is still remembered: the alternative asks somebody to retype an
  /// address because the server they are about to start is not running yet.
  Future<void> apply(LlmRuntimeSettings next) async {
    _adopt(next);
    notifyListeners();
    try {
      await _store.write(next);
    } on Object {
      failure = 'These settings could not be saved on this device.';
      notifyListeners();
    }
    await probe();
  }

  /// Forget the runtime and go back to advertising nothing.
  Future<void> disable() async {
    settings = null;
    failure = null;
    adapter.adopt(const UnavailableRuntimeAdapter());
    notifyListeners();
    try {
      await _store.clear();
    } on Object {
      failure =
          'The runtime is disabled for this session, but its saved settings '
          'could not be removed. It may return after restarting. Retry disabling it.';
      notifyListeners();
    }
  }

  Future<RuntimeDescriptor> probe() async {
    if (settings == null) return RuntimeDescriptor.unavailable;
    probing = true;
    notifyListeners();
    try {
      final descriptor = await adapter.probe();
      final current = adapter.current;
      failure = current is LlmRuntimeAdapter ? current.probeFailure : null;
      return descriptor;
    } finally {
      probing = false;
      notifyListeners();
    }
  }

  void _adopt(LlmRuntimeSettings next) {
    settings = next;
    failure = null;
    adapter.adopt(_buildAdapter(next));
  }
}

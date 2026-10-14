import 'package:evaluetron_worker_app/features/worker/data/mutable_runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/data/runtime_settings_store.dart';
import 'package:evaluetron_worker_app/features/worker/domain/llm_runtime_settings.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/presentation/runtime_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A runtime whose readiness the test decides, so the controller's own behaviour
/// is what is under examination rather than a model server's.
class _StubRuntime implements WorkerRuntimeAdapter {
  _StubRuntime({required this.serves});

  final bool serves;
  int probes = 0;
  RuntimeDescriptor _descriptor = RuntimeDescriptor.unavailable;

  @override
  RuntimeDescriptor get descriptor => _descriptor;

  @override
  Future<RuntimeDescriptor> probe() async {
    probes++;
    return _descriptor = serves
        ? RuntimeDescriptor.serving(
            models: {
              'llm': ['stub'],
            },
            methods: {
              'llm': ['test'],
            },
          )
        : RuntimeDescriptor.unavailable;
  }

  @override
  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  ) => throw const RuntimeRequestException('not in this test');
}

void main() {
  final settings = LlmRuntimeSettings.parse(
    baseUrl: 'http://127.0.0.1:8080',
    model: 'stub',
  );

  group('what a ready descriptor is allowed to claim', () {
    test('refuses a generator advertised with no model under it', () {
      // The brain's router selects by advertised generator *and* model, so this
      // shape registers a healthy-looking node that every job routes past with
      // "no worker available". It has happened once already on the Python worker.
      expect(
        () => RuntimeDescriptor.serving(models: {'llm': []}, methods: {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RuntimeDescriptor.serving(models: {}, methods: {}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'derives the generator list from the models, so the two cannot disagree',
      () {
        final descriptor = RuntimeDescriptor.serving(
          models: {
            'llm': ['qwen3:8b'],
          },
          methods: {
            'llm': ['ollama'],
          },
        );
        expect(descriptor.generators, ['llm']);
        expect(descriptor.ready, isTrue);
      },
    );
  });

  group('one runtime reference, many runtimes', () {
    test('forgets what the last runtime advertised when a new one arrives', () {
      // The gap between a swap and the next probe is exactly when carrying the
      // old descriptor forward would send a job somewhere that cannot serve it.
      final ready = _StubRuntime(serves: true);
      final adapter = MutableRuntimeAdapter(ready);

      return adapter.probe().then((_) {
        expect(adapter.descriptor.ready, isTrue);
        adapter.adopt(const UnavailableRuntimeAdapter());
        expect(adapter.descriptor.ready, isFalse);
      });
    });
  });

  group('the runtime a node remembers', () {
    test(
      'reports failed removal and keeps local capability withdrawn until retry',
      () async {
        final store = _FailingClearStore(settings);
        final controller = RuntimeController(
          store: store,
          buildAdapter: (_) => _StubRuntime(serves: true),
        );
        await controller.initialize();
        await controller.disable();
        expect(controller.configured, isFalse);
        expect(controller.descriptor.ready, isFalse);
        expect(controller.failure, isNotNull);
        expect(store.value, isNotNull);

        store.failClear = false;
        await controller.disable();
        expect(controller.failure, isNull);
        expect(store.value, isNull);

        final restarted = RuntimeController(store: store);
        await restarted.initialize();
        expect(restarted.configured, isFalse);
      },
    );
    test('starts with nothing, and probes nothing', () async {
      final controller = RuntimeController(store: MemoryRuntimeSettingsStore());
      await controller.initialize();

      expect(controller.configured, isFalse);
      expect(controller.descriptor.ready, isFalse);
      expect(controller.loading, isFalse);
    });

    test('restores stored settings and proves them on the way up', () async {
      final runtime = _StubRuntime(serves: true);
      final controller = RuntimeController(
        store: MemoryRuntimeSettingsStore(settings),
        buildAdapter: (_) => runtime,
      );

      await controller.initialize();

      expect(controller.configured, isTrue);
      expect(runtime.probes, 1);
      expect(controller.descriptor.ready, isTrue);
      expect(controller.failure, isNull);
    });

    test('remembers a runtime that is merely down right now', () async {
      // Storing only what probes successfully would ask somebody to retype an
      // address because the server they are about to start is not running yet.
      final store = MemoryRuntimeSettingsStore();
      final controller = RuntimeController(
        store: store,
        buildAdapter: (_) => _StubRuntime(serves: false),
      );

      await controller.apply(settings);

      expect(store.value, isNotNull);
      expect(controller.configured, isTrue);
      expect(controller.descriptor.ready, isFalse);
    });

    test('goes back to advertising nothing when told to stop', () async {
      final store = MemoryRuntimeSettingsStore();
      final controller = RuntimeController(
        store: store,
        buildAdapter: (_) => _StubRuntime(serves: true),
      );
      await controller.apply(settings);
      expect(controller.descriptor.ready, isTrue);

      await controller.disable();

      expect(controller.configured, isFalse);
      expect(controller.descriptor.ready, isFalse);
      expect(store.value, isNull);
    });

    test(
      'discards stored settings a newer build would no longer accept',
      () async {
        // Re-parsed rather than trusted, so tightening a bound cannot leave an
        // older value half-honoured. The node falls back to advertising nothing,
        // which is the safe direction.
        final store = MemoryRuntimeSettingsStore();
        await store.write(settings);
        final controller = RuntimeController(
          store: _CorruptedStore(),
          buildAdapter: (_) => _StubRuntime(serves: true),
        );

        await controller.initialize();

        expect(controller.configured, isFalse);
        expect(controller.descriptor.ready, isFalse);
      },
    );
  });
}

/// A store whose contents no longer parse, as an older build's would not.
class _FailingClearStore extends MemoryRuntimeSettingsStore {
  _FailingClearStore(super.value);
  bool failClear = true;

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('storage unavailable');
    await super.clear();
  }
}

class _CorruptedStore implements RuntimeSettingsStore {
  bool cleared = false;

  @override
  Future<LlmRuntimeSettings?> read() async {
    // What SecureRuntimeSettingsStore does on unreadable content: discard and
    // report nothing, rather than surfacing a half-built value.
    cleared = true;
    return null;
  }

  @override
  Future<void> write(LlmRuntimeSettings settings) async {}

  @override
  Future<void> clear() async => cleared = true;
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/llm_runtime_settings.dart';

abstract interface class RuntimeSettingsStore {
  Future<LlmRuntimeSettings?> read();
  Future<void> write(LlmRuntimeSettings settings);
  Future<void> clear();
}

/// Where this node remembers which model runtime it serves.
///
/// The platform secure store rather than ordinary preferences, not because a
/// model address is a secret but because it is the store this app already
/// carries, and one storage dependency is one thing to get right. It shares the
/// node credential's device-bound options for the same reason those exist: this
/// setting describes a runtime on *this* device, and a copy restored onto another
/// handset would point at a server that is not there.
class SecureRuntimeSettingsStore implements RuntimeSettingsStore {
  SecureRuntimeSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'evaluetron_worker'),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _key = 'evaluetron.node.runtime.llm.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<LlmRuntimeSettings?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      return LlmRuntimeSettings.fromJson(
        (jsonDecode(encoded) as Map<Object?, Object?>).cast<String, Object?>(),
      );
    } on Object {
      // Unreadable, or written by a build whose bounds were looser than this
      // one's. Either way it is discarded rather than half-honoured: the node
      // falls back to advertising nothing, which is the safe direction.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(LlmRuntimeSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryRuntimeSettingsStore implements RuntimeSettingsStore {
  MemoryRuntimeSettingsStore([this.value]);

  LlmRuntimeSettings? value;

  @override
  Future<LlmRuntimeSettings?> read() async => value;

  @override
  Future<void> write(LlmRuntimeSettings settings) async => value = settings;

  @override
  Future<void> clear() async => value = null;
}

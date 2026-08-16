import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/managed_network.dart';
import '../domain/network_enrollment.dart';

class PlatformManagedNetworkSecretStore implements ManagedNetworkSecretStore {
  PlatformManagedNetworkSecretStore({FlutterSecureStorage? storage})
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

  static const _key = 'evaluetron.managed-network.secret.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<ManagedNetworkSecret?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      return ManagedNetworkSecret.fromJson(
        (jsonDecode(encoded) as Map<Object?, Object?>).cast<String, Object?>(),
      );
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(ManagedNetworkSecret secret) {
    return _storage.write(key: _key, value: jsonEncode(secret.toJson()));
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryManagedNetworkSecretStore implements ManagedNetworkSecretStore {
  MemoryManagedNetworkSecretStore([this.value]);

  ManagedNetworkSecret? value;

  @override
  Future<ManagedNetworkSecret?> read() async => value;

  @override
  Future<void> write(ManagedNetworkSecret secret) async {
    value = secret;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/node_registration.dart';

abstract interface class NodeCredentialStore {
  Future<NodeRegistration?> read();
  Future<void> write(NodeRegistration registration);
  Future<void> clear();
}

class PlatformSecureNodeCredentialStore implements NodeCredentialStore {
  PlatformSecureNodeCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(
      aOptions: AndroidOptions(storageNamespace: 'evaluetron_worker'),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    );

  static const _registrationKey = 'evaluetron.node.registration.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<NodeRegistration?> read() async {
    final encoded = await _storage.read(key: _registrationKey);
    if (encoded == null) return null;
    try {
      return NodeRegistration.fromJson(
        (jsonDecode(encoded) as Map<Object?, Object?>).cast<String, Object?>(),
      );
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(NodeRegistration registration) {
    return _storage.write(
      key: _registrationKey,
      value: jsonEncode(registration.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _registrationKey);
}

class MemoryNodeCredentialStore implements NodeCredentialStore {
  MemoryNodeCredentialStore([this.value]);

  NodeRegistration? value;

  @override
  Future<NodeRegistration?> read() async => value;

  @override
  Future<void> write(NodeRegistration registration) async {
    value = registration;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

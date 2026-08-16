import 'dart:io';

class NebulaKeyPair {
  const NebulaKeyPair({
    required this.publicKeyPem,
    required this.privateKeyPem,
  });

  final String publicKeyPem;
  final String privateKeyPem;
}

class ManagedNetworkMetadata {
  const ManagedNetworkMetadata({
    required this.meshName,
    required this.endpoint,
    required this.brainIp,
  });

  final String meshName;
  final String endpoint;
  final String brainIp;

  Map<String, Object> toJson() => {
    'meshName': meshName,
    'endpoint': endpoint,
    'brainIp': brainIp,
  };

  factory ManagedNetworkMetadata.fromJson(Map<String, Object?> json) {
    return ManagedNetworkMetadata(
      meshName: _requiredString(json, 'meshName', maxLength: 128),
      endpoint: _requiredString(json, 'endpoint', maxLength: 512),
      brainIp: _requiredString(json, 'brainIp', maxLength: 64),
    );
  }
}

/// The brain-issued fleet listener for this node's group.
///
/// It is the only fleet address this device may treat as authentic, because a
/// pairing QR carries its own unverified fleet field.
class ManagedServiceProfile {
  const ManagedServiceProfile({required this.group, required this.serviceUrl});

  final String group;
  final Uri serviceUrl;

  Map<String, Object> toJson() => {
    'group': group,
    'serviceUrl': serviceUrl.toString(),
  };

  factory ManagedServiceProfile.fromJson(Map<String, Object?> json) {
    final serviceUrl = Uri.tryParse(
      _requiredString(json, 'serviceUrl', maxLength: 512),
    );
    if (serviceUrl == null || !serviceUrl.hasAuthority) {
      throw const FormatException('Invalid managed network field: serviceUrl.');
    }
    return ManagedServiceProfile(
      group: _requiredString(json, 'group', maxLength: 64),
      serviceUrl: serviceUrl,
    );
  }
}

class ManagedNetworkProfile {
  const ManagedNetworkProfile({
    required this.version,
    required this.caPem,
    required this.certificatePem,
    required this.opaqueConfig,
    required this.metadata,
    this.service,
  });

  final String version;
  final String caPem;
  final String certificatePem;

  /// Brain-issued Nebula configuration retained for a future audited engine.
  ///
  /// The Flutter layer does not interpret it or derive routes from it.
  final String opaqueConfig;
  final ManagedNetworkMetadata metadata;

  /// Absent on profiles issued by a host helper older than the listener split.
  final ManagedServiceProfile? service;

  ManagedRoutePolicy get routePolicy =>
      ManagedRoutePolicy.forBrain(metadata.brainIp);

  /// Whether [origin] names the brain that issued this profile.
  ///
  /// Pairing carries the fleet origin as an independent field, so it must be
  /// proven against the address the brain signed for before any credential
  /// travels to it. Ports are deployment configuration and are not compared.
  bool authorizesFleetOrigin(Uri origin) {
    final candidate = InternetAddress.tryParse(origin.host);
    if (candidate == null || !_isSameAddress(candidate, metadata.brainIp)) {
      return false;
    }
    final issued = service?.serviceUrl.host;
    return issued == null || _isSameAddress(candidate, issued);
  }

  Map<String, Object> toJson() => {
    'version': version,
    'caPem': caPem,
    'certificatePem': certificatePem,
    'opaqueConfig': opaqueConfig,
    'metadata': metadata.toJson(),
    if (service != null) 'service': service!.toJson(),
  };

  factory ManagedNetworkProfile.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    if (metadata is! Map<Object?, Object?>) {
      throw const FormatException('Managed network metadata is missing.');
    }
    final service = json['service'];
    final profile = ManagedNetworkProfile(
      version: _requiredString(json, 'version', maxLength: 64),
      caPem: _requiredPem(json, 'caPem', 'NEBULA CERTIFICATE'),
      certificatePem: _requiredPem(
        json,
        'certificatePem',
        'NEBULA CERTIFICATE',
      ),
      opaqueConfig: _requiredString(json, 'opaqueConfig', maxLength: 196608),
      metadata: ManagedNetworkMetadata.fromJson(
        metadata.cast<String, Object?>(),
      ),
      service: service is Map<Object?, Object?>
          ? ManagedServiceProfile.fromJson(service.cast<String, Object?>())
          : null,
    );
    // Validation is deliberately eager before anything can reach a tunnel.
    profile.routePolicy;
    return profile;
  }

  static bool _isSameAddress(InternetAddress candidate, String issued) {
    final address = InternetAddress.tryParse(issued.split('/').first);
    if (address == null || address.type != candidate.type) return false;
    final left = address.rawAddress;
    final right = candidate.rawAddress;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class ManagedNetworkSecret {
  const ManagedNetworkSecret({
    required this.profile,
    required this.privateKeyPem,
  });

  final ManagedNetworkProfile profile;
  final String privateKeyPem;

  Map<String, Object> toJson() => {
    'profile': profile.toJson(),
    'privateKeyPem': privateKeyPem,
  };

  factory ManagedNetworkSecret.fromJson(Map<String, Object?> json) {
    final profile = json['profile'];
    if (profile is! Map<Object?, Object?>) {
      throw const FormatException('Managed network profile is missing.');
    }
    final privateKey = _requiredString(json, 'privateKeyPem', maxLength: 16384);
    if (!privateKey.contains('PRIVATE KEY')) {
      throw const FormatException('Managed network private key is invalid.');
    }
    return ManagedNetworkSecret(
      profile: ManagedNetworkProfile.fromJson(profile.cast<String, Object?>()),
      privateKeyPem: privateKey,
    );
  }
}

class ManagedRoutePolicy {
  const ManagedRoutePolicy._(this.routes);

  final List<String> routes;

  factory ManagedRoutePolicy.forBrain(String brainIp) {
    final parts = brainIp.split('/');
    if (parts.length > 2 || parts.first.isEmpty) {
      throw const FormatException(
        'Managed brain address must be a private IP or CIDR.',
      );
    }
    final address = InternetAddress.tryParse(parts.first);
    if (address == null || !_isPrivateOrLoopback(address)) {
      throw const FormatException(
        'Managed brain address must be a private or link-local IP.',
      );
    }
    if (parts.length == 2) {
      final suppliedPrefix = int.tryParse(parts[1]);
      final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (suppliedPrefix == null ||
          suppliedPrefix < 0 ||
          suppliedPrefix > maxPrefix) {
        throw const FormatException(
          'Managed brain address has an invalid CIDR prefix.',
        );
      }
    }
    final prefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
    return ManagedRoutePolicy._(
      List.unmodifiable(['${address.address}/$prefix']),
    );
  }

  static bool _isPrivateOrLoopback(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return (bytes[0] & 0xfe) == 0xfc;
  }
}

String _requiredString(
  Map<String, Object?> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('Invalid managed network field: $key.');
  }
  return value;
}

String _requiredPem(Map<String, Object?> json, String key, String label) {
  final value = _requiredString(json, key, maxLength: 65536);
  if (!value.contains('BEGIN $label') || !value.contains('END $label')) {
    throw FormatException('Invalid managed network field: $key.');
  }
  return value;
}

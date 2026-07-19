import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/managed_network.dart';
import '../domain/network_enrollment.dart';

class HttpManagedNetworkEnrollmentClient
    implements ManagedNetworkEnrollmentClient {
  HttpManagedNetworkEnrollmentClient({HttpClient? client})
    : _client = client ?? HttpClient();

  static const _timeout = Duration(seconds: 40);
  static const _maxResponseBytes = 256 * 1024;
  final HttpClient _client;

  @override
  Future<ManagedNetworkProfile> enroll({
    required Uri brainBaseUrl,
    required String oneTimeToken,
    required String publicKeyPem,
  }) async {
    final validatedBrain = _validateBrainOrigin(brainBaseUrl);
    if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(oneTimeToken) ||
        publicKeyPem.isEmpty ||
        publicKeyPem.length > 16384) {
      throw const NetworkEnrollmentException(
        'Managed network enrollment input is invalid.',
      );
    }
    final endpoint = validatedBrain.resolve('/enroll/nebula');
    try {
      final request = await _client.postUrl(endpoint).timeout(_timeout);
      final encoded = utf8.encode(jsonEncode({'publicKey': publicKeyPem}));
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $oneTimeToken')
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.acceptHeader, 'application/json')
        ..headers.contentLength = encoded.length
        ..add(encoded);
      final response = await request.close().timeout(_timeout);
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            if (buffer.length + chunk.length > _maxResponseBytes) {
              throw const NetworkEnrollmentException(
                'Brain returned an oversized network profile.',
              );
            }
            return buffer..addAll(chunk);
          })
          .timeout(_timeout);
      final decoded = (jsonDecode(utf8.decode(bytes)) as Map<Object?, Object?>)
          .cast<String, Object?>();
      if (response.statusCode != HttpStatus.ok || decoded['ok'] != true) {
        throw NetworkEnrollmentException(
          decoded['error'] is String
              ? decoded['error']! as String
              : 'Managed network enrollment was rejected.',
        );
      }
      final enrollment = decoded['enrollment'];
      if (enrollment is! Map<Object?, Object?>) {
        throw const NetworkEnrollmentException(
          'Brain returned no managed network profile.',
        );
      }
      final body = enrollment.cast<String, Object?>();
      final managed = body['managed'];
      if (managed is! Map<Object?, Object?>) {
        throw const NetworkEnrollmentException(
          'Brain returned incomplete managed network metadata.',
        );
      }
      return ManagedNetworkProfile.fromJson({
        'version': body['version'],
        'caPem': body['ca'],
        'certificatePem': body['certificate'],
        'opaqueConfig': body['config'],
        'metadata': managed.cast<String, Object?>(),
      });
    } on NetworkEnrollmentException {
      rethrow;
    } on TimeoutException {
      throw const NetworkEnrollmentException(
        'Managed network enrollment timed out.',
      );
    } on HandshakeException {
      throw const NetworkEnrollmentException(
        'Could not establish a trusted TLS connection.',
      );
    } on Object {
      throw const NetworkEnrollmentException(
        'Could not securely complete managed network enrollment.',
      );
    }
  }

  static Uri _validateBrainOrigin(Uri uri) {
    if (!uri.hasAuthority ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const NetworkEnrollmentException(
        'Managed network brain address is invalid.',
      );
    }
    if (uri.scheme == 'http') {
      final address = InternetAddress.tryParse(uri.host);
      if (address == null || !_isPrivateOrLoopback(address)) {
        throw const NetworkEnrollmentException(
          'Managed network enrollment requires HTTPS outside a private network.',
        );
      }
    }
    return uri.replace(path: '');
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

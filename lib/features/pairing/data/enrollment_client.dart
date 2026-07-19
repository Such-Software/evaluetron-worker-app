import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/enrollment.dart';
import '../domain/node_registration.dart';

abstract interface class EnrollmentClient {
  Future<NodeRegistration> enroll(EnrollmentDraft draft);
}

class EnrollmentException implements Exception {
  const EnrollmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HttpEnrollmentClient implements EnrollmentClient {
  HttpEnrollmentClient({HttpClient? client}) : _client = client ?? HttpClient();

  static const _timeout = Duration(seconds: 15);
  final HttpClient _client;

  @override
  Future<NodeRegistration> enroll(EnrollmentDraft draft) async {
    final endpoint = draft.brainBaseUrl.resolve('/internal/nodes/enroll');
    try {
      final request = await _client.postUrl(endpoint).timeout(_timeout);
      request
        ..followRedirects = false
        ..headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${draft.enrollmentToken}',
        )
        ..headers.set(HttpHeaders.acceptHeader, 'application/json')
        ..headers.set(HttpHeaders.contentLengthHeader, '0');
      final response = await request.close().timeout(_timeout);
      final body = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (body.length > 65536) {
        throw const EnrollmentException(
          'Brain returned an oversized response.',
        );
      }
      final decoded = (jsonDecode(body) as Map<Object?, Object?>)
          .cast<String, Object?>();
      if (response.statusCode != HttpStatus.created) {
        throw EnrollmentException(
          decoded['error'] is String
              ? decoded['error']! as String
              : 'Enrollment was rejected.',
        );
      }
      final node = (decoded['node']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final token = decoded['nodeToken'];
      if (token is! String || !token.startsWith('evn_')) {
        throw const EnrollmentException(
          'Brain did not return a valid node credential.',
        );
      }
      return NodeRegistration(
        brainBaseUrl: draft.brainBaseUrl,
        nodeId: node['nodeId']! as String,
        credentialId: decoded['credentialId']! as String,
        nodeName: node['name']! as String,
        nodeToken: token,
        roles: (node['roles']! as List<Object?>).cast<String>(),
      );
    } on EnrollmentException {
      rethrow;
    } on TimeoutException {
      throw const EnrollmentException('The brain did not respond in time.');
    } on HandshakeException {
      throw const EnrollmentException(
        'Could not establish a trusted TLS connection.',
      );
    } on Object {
      throw const EnrollmentException(
        'Could not reach the brain or read its response.',
      );
    }
  }
}

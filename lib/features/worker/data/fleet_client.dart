import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../pairing/domain/node_registration.dart';
import '../domain/runtime_adapter.dart';
import 'dispatch_authenticator.dart';

abstract interface class FleetClient {
  Future<void> register(
    NodeRegistration registration,
    WorkerAdvertisement advertisement,
  );
  Future<void> heartbeat(NodeRegistration registration);
}

class WorkerAdvertisement {
  const WorkerAdvertisement({required this.endpoint, required this.runtime});

  final Uri endpoint;
  final RuntimeDescriptor runtime;
}

/// Why a fleet call failed, so a live session can tell a lost brain from a
/// revoked credential instead of treating every fault as terminal.
enum FleetFailure {
  /// The brain refused the node credential itself.
  unauthorized,

  /// The brain holds no registration for this worker and expects a new one.
  unregistered,

  /// The brain is unreachable or temporarily unable to answer.
  unavailable,

  /// The brain understood the call and refused it.
  rejected,
}

class FleetException implements Exception {
  const FleetException(this.message, {this.failure = FleetFailure.rejected});

  final String message;
  final FleetFailure failure;
}

class HttpFleetClient implements FleetClient {
  HttpFleetClient({HttpClient? client}) : _client = client ?? HttpClient();

  static const _timeout = Duration(seconds: 15);
  final HttpClient _client;

  @override
  Future<void> register(
    NodeRegistration registration,
    WorkerAdvertisement advertisement,
  ) {
    return _post(registration, '/internal/workers/register', {
      'workerId': registration.nodeName,
      'class': 'edge',
      'generators': advertisement.runtime.generators,
      'models': advertisement.runtime.models,
      'methods': advertisement.runtime.methods,
      'capacity': 1,
      'url': advertisement.endpoint.toString(),
      'dispatchAuth': DispatchAuthenticator.scheme,
      'details': {
        'client': 'evaluetron-worker-app',
        'runtimeReady': advertisement.runtime.ready,
        'sessionMode': 'foreground',
      },
    });
  }

  @override
  Future<void> heartbeat(NodeRegistration registration) {
    return _post(registration, '/internal/workers/heartbeat', {
      'workerId': registration.nodeName,
    });
  }

  Future<void> _post(
    NodeRegistration registration,
    String path,
    Map<String, Object> payload,
  ) async {
    final ({int status, String body}) answer;
    try {
      answer = await _exchange(registration, path, payload);
    } on Object {
      throw const FleetException(
        'The brain did not answer this device.',
        failure: FleetFailure.unavailable,
      );
    }
    if (answer.body.length > 65536) {
      throw const FleetException('Brain returned an oversized response.');
    }
    if (answer.status < 200 || answer.status >= 300) {
      var message = 'Brain rejected the worker session.';
      try {
        final decoded = (jsonDecode(answer.body) as Map<Object?, Object?>)
            .cast<String, Object?>();
        if (decoded['error'] is String) message = decoded['error']! as String;
      } on Object {
        // Keep the bounded generic message.
      }
      throw FleetException(message, failure: _failureFor(answer.status));
    }
  }

  Future<({int status, String body})> _exchange(
    NodeRegistration registration,
    String path,
    Map<String, Object> payload,
  ) async {
    final request = await _client
        .postUrl(registration.brainBaseUrl.resolve(path))
        .timeout(_timeout);
    final encoded = utf8.encode(jsonEncode(payload));
    request
      ..followRedirects = false
      ..headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${registration.nodeToken}',
      )
      ..headers.contentType = ContentType.json
      ..headers.contentLength = encoded.length
      ..add(encoded);
    final response = await request.close().timeout(_timeout);
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join().timeout(_timeout),
    );
  }

  /// The brain answers 404 to a heartbeat for a worker it no longer holds, and
  /// 409 while it cannot reach this device. Both are recoverable.
  static FleetFailure _failureFor(int status) => switch (status) {
    HttpStatus.unauthorized => FleetFailure.unauthorized,
    HttpStatus.notFound => FleetFailure.unregistered,
    HttpStatus.requestTimeout ||
    HttpStatus.conflict ||
    HttpStatus.tooManyRequests => FleetFailure.unavailable,
    >= 500 => FleetFailure.unavailable,
    _ => FleetFailure.rejected,
  };
}

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

class FleetException implements Exception {
  const FleetException(this.message);

  final String message;
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
    final body = await utf8.decoder.bind(response).join().timeout(_timeout);
    if (body.length > 65536) {
      throw const FleetException('Brain returned an oversized response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Brain rejected the worker session.';
      try {
        final decoded = (jsonDecode(body) as Map<Object?, Object?>)
            .cast<String, Object?>();
        if (decoded['error'] is String) message = decoded['error']! as String;
      } on Object {
        // Keep the bounded generic message.
      }
      throw FleetException(message);
    }
  }
}

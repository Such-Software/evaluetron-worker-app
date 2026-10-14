import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../pairing/domain/node_registration.dart';
import '../domain/runtime_adapter.dart';
import 'dispatch_authenticator.dart';

abstract interface class WorkerServer {
  Uri? get endpoint;
  RuntimeDescriptor get runtime;

  /// Re-ask the runtime what it can execute, and report what it said.
  ///
  /// Called immediately before every registration, so what the brain is told
  /// about this node is never older than the last time it was told anything. A
  /// model server that has stopped, or a model that has been deleted, therefore
  /// costs at most one dispatch rather than every dispatch until the session is
  /// restarted by hand.
  Future<RuntimeDescriptor> probeRuntime();

  Future<void> start(NodeRegistration registration);
  Future<void> stop();
}

class HttpWorkerJobServer implements WorkerServer {
  HttpWorkerJobServer({
    required WorkerRuntimeAdapter adapter,
    this.port = 0,
    this.maxRequestBytes = 1024 * 1024,
    this.maxArtifactBytes = 64 * 1024 * 1024,
    this.advertisedHost,
  }) : _adapter = adapter;

  final WorkerRuntimeAdapter _adapter;
  final int port;
  final int maxRequestBytes;
  final int maxArtifactBytes;
  final String? advertisedHost;
  HttpServer? _server;
  DispatchAuthenticator? _authenticator;
  bool _busy = false;

  @override
  Uri? endpoint;

  @override
  RuntimeDescriptor get runtime => _adapter.descriptor;

  @override
  Future<RuntimeDescriptor> probeRuntime() => _adapter.probe();

  /// The single interface this listener accepts connections on.
  @visibleForTesting
  InternetAddress? get boundAddress => _server?.address;

  @override
  Future<void> start(NodeRegistration registration) async {
    if (_server != null) return;
    final routeAddress = advertisedHost == null
        ? await _routeAddress(registration.brainBaseUrl)
        : InternetAddress(advertisedHost!);
    if (!_isPrivateOrLoopback(routeAddress)) {
      throw const SocketException(
        'The selected worker address is not private or loopback.',
      );
    }
    // Bind the advertised interface itself: /health answers before any
    // authentication, so it must not be reachable from other networks.
    final server = await HttpServer.bind(routeAddress, port, shared: false);
    _authenticator = DispatchAuthenticator(nodeToken: registration.nodeToken);
    _server = server;
    endpoint = Uri(
      scheme: 'http',
      host: routeAddress.address,
      port: server.port,
    );
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    endpoint = null;
    _authenticator = null;
    _busy = false;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(request.response, HttpStatus.ok, {
        'ok': true,
        'generators': runtime.generators,
        'models': runtime.models,
        'methods': runtime.methods,
        'runtimeReady': runtime.ready,
        'dispatchAuth': DispatchAuthenticator.scheme,
      });
      return;
    }
    if (request.method != 'POST' || request.uri.path != '/jobs') {
      await _text(request.response, HttpStatus.notFound, 'not found');
      return;
    }
    Uint8List body;
    try {
      body = await _readBounded(request, maxRequestBytes);
    } on _BodyTooLarge {
      await _text(
        request.response,
        HttpStatus.requestEntityTooLarge,
        'request too large',
      );
      return;
    }
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    if (!(_authenticator?.verify(headers: headers, body: body) ?? false)) {
      await _text(request.response, HttpStatus.unauthorized, 'unauthorized');
      return;
    }
    if (_busy) {
      await _text(request.response, HttpStatus.serviceUnavailable, 'busy');
      return;
    }
    _busy = true;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Request must be a JSON object.');
      }
      final generator = decoded['generator'];
      final parameters = decoded['params'];
      if (generator is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(generator) ||
          parameters is! Map<String, Object?>) {
        throw const FormatException('Invalid generator or parameters.');
      }
      if (!runtime.ready || !runtime.generators.contains(generator)) {
        await _text(
          request.response,
          HttpStatus.badRequest,
          'unsupported generator',
        );
        return;
      }
      final artifact = await _adapter.run(generator, parameters);
      if (artifact.bytes.isEmpty ||
          artifact.bytes.length > maxArtifactBytes ||
          !_validContentType(artifact.contentType)) {
        throw const RuntimeRequestException(
          'Runtime returned an invalid artifact.',
        );
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(artifact.contentType)
        ..contentLength = artifact.bytes.length
        ..add(artifact.bytes);
      await request.response.close();
    } on FormatException {
      await _text(request.response, HttpStatus.badRequest, 'invalid request');
    } on RuntimeRequestException {
      await _text(request.response, HttpStatus.badGateway, 'runtime failed');
    } on Object {
      await _text(
        request.response,
        HttpStatus.internalServerError,
        'worker error',
      );
    } finally {
      _busy = false;
    }
  }

  static Future<InternetAddress> _routeAddress(Uri brain) async {
    final port = brain.hasPort
        ? brain.port
        : brain.scheme == 'https'
        ? 443
        : 80;
    final socket = await Socket.connect(
      brain.host,
      port,
      timeout: const Duration(seconds: 5),
    );
    final destination = socket.remoteAddress;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: true,
        includeLinkLocal: true,
        type: destination.type,
      );
      return selectAdvertisedAddress(
        destination,
        interfaces.expand((interface) => interface.addresses),
      );
    } finally {
      await socket.close();
    }
  }

  static bool _isPrivateOrLoopback(InternetAddress address) {
    if (address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  static bool _validContentType(String value) {
    if (value.length > 128 || value.contains('\r') || value.contains('\n')) {
      return false;
    }
    try {
      ContentType.parse(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static Future<Uint8List> _readBounded(HttpRequest request, int limit) async {
    if (request.contentLength > limit) throw const _BodyTooLarge();
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request) {
      length += chunk.length;
      if (length > limit) throw const _BodyTooLarge();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> value,
  ) async {
    final body = utf8.encode(jsonEncode(value));
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..contentLength = body.length
      ..add(body);
    await response.close();
  }

  static Future<void> _text(
    HttpResponse response,
    int status,
    String value,
  ) async {
    final body = utf8.encode(value);
    response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..contentLength = body.length
      ..add(body);
    await response.close();
  }
}

InternetAddress selectAdvertisedAddress(
  InternetAddress destination,
  Iterable<InternetAddress> candidates,
) {
  final matching = candidates.where((candidate) {
    if (candidate.type != destination.type ||
        !HttpWorkerJobServer._isPrivateOrLoopback(candidate)) {
      return false;
    }
    if (destination.isLoopback) return candidate.isLoopback;
    if (candidate.isLoopback) return false;
    if (destination.isLinkLocal) return candidate.isLinkLocal;
    return !candidate.isLinkLocal;
  }).toList();
  if (matching.isEmpty) {
    throw const SocketException(
      'No private local interface can advertise this Worker session.',
    );
  }
  matching.sort((left, right) {
    final prefix = _commonPrefixBits(
      right.rawAddress,
      destination.rawAddress,
    ).compareTo(_commonPrefixBits(left.rawAddress, destination.rawAddress));
    return prefix != 0 ? prefix : left.address.compareTo(right.address);
  });
  return matching.first;
}

int _commonPrefixBits(List<int> left, List<int> right) {
  var bits = 0;
  for (var index = 0; index < left.length && index < right.length; index++) {
    final difference = left[index] ^ right[index];
    if (difference == 0) {
      bits += 8;
      continue;
    }
    for (var bit = 7; bit >= 0; bit--) {
      if ((difference & (1 << bit)) != 0) return bits;
      bits++;
    }
  }
  return bits;
}

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}

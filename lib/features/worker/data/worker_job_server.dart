import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../pairing/domain/node_registration.dart';
import '../domain/runtime_adapter.dart';
import 'dispatch_authenticator.dart';

abstract interface class WorkerServer {
  Uri? get endpoint;
  RuntimeDescriptor get runtime;

  Future<void> start(NodeRegistration registration);
  Future<void> stop();
}

class HttpWorkerJobServer implements WorkerServer {
  HttpWorkerJobServer({
    required WorkerRuntimeAdapter adapter,
    this.port = 8090,
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
    final bindAddress = routeAddress.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;
    final server = await HttpServer.bind(bindAddress, port, shared: false);
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
    try {
      return socket.address;
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

class _BodyTooLarge implements Exception {
  const _BodyTooLarge();
}

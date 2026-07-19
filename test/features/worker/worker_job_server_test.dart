import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/worker_job_server.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'evn_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  late HttpWorkerJobServer server;

  setUp(() async {
    server = HttpWorkerJobServer(
      adapter: _EchoRuntime(),
      port: 0,
      advertisedHost: '127.0.0.1',
    );
    await server.start(
      NodeRegistration(
        brainBaseUrl: Uri.parse('http://127.0.0.1:8082'),
        nodeId: 'node',
        credentialId: 'credential',
        nodeName: 'worker-test',
        nodeToken: token,
        roles: const ['worker'],
      ),
    );
  });

  tearDown(() => server.stop());

  test('serves health and requires authenticated job requests', () async {
    final health = await _request(server.endpoint!.resolve('/health'));
    expect(health.statusCode, HttpStatus.ok);
    expect(jsonDecode(health.body)['dispatchAuth'], 'hmac-sha256-v1');

    final body = utf8.encode(
      jsonEncode({
        'generator': 'echo',
        'params': {'text': 'hello'},
      }),
    );
    final unsigned = await _request(
      server.endpoint!.resolve('/jobs'),
      method: 'POST',
      body: body,
    );
    expect(unsigned.statusCode, HttpStatus.unauthorized);

    final headers = _signedHeaders(token, body);
    final accepted = await _request(
      server.endpoint!.resolve('/jobs'),
      method: 'POST',
      body: body,
      headers: headers,
    );
    expect(accepted.statusCode, HttpStatus.ok);
    expect(accepted.body, 'hello');

    final replay = await _request(
      server.endpoint!.resolve('/jobs'),
      method: 'POST',
      body: body,
      headers: headers,
    );
    expect(replay.statusCode, HttpStatus.unauthorized);
  });
}

class _EchoRuntime implements WorkerRuntimeAdapter {
  @override
  RuntimeDescriptor get descriptor => const RuntimeDescriptor(
    generators: ['echo'],
    models: {
      'echo': ['built-in'],
    },
    methods: {
      'echo': ['test'],
    },
    ready: true,
  );

  @override
  Future<RuntimeArtifact> run(
    String generator,
    Map<String, Object?> parameters,
  ) async {
    return RuntimeArtifact(
      contentType: 'text/plain; charset=utf-8',
      bytes: Uint8List.fromList(utf8.encode(parameters['text']! as String)),
    );
  }
}

Map<String, String> _signedHeaders(String token, List<int> body) {
  final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
      .toString();
  const nonce = 'AQIDBAUGBwgJCgsMDQ4PEA';
  final key = Hmac(
    sha256,
    utf8.encode(token),
  ).convert(utf8.encode('evaluetron-worker-dispatch-key-v1')).bytes;
  final payload = [
    'v1',
    timestamp,
    nonce,
    'POST',
    '/jobs',
    sha256.convert(body),
  ].join('\n');
  final signature = base64Url
      .encode(Hmac(sha256, key).convert(utf8.encode(payload)).bytes)
      .replaceAll('=', '');
  return {
    'x-evaluetron-dispatch-version': '1',
    'x-evaluetron-dispatch-timestamp': timestamp,
    'x-evaluetron-dispatch-nonce': nonce,
    'x-evaluetron-dispatch-signature': signature,
  };
}

Future<({int statusCode, String body})> _request(
  Uri endpoint, {
  String method = 'GET',
  List<int> body = const [],
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, endpoint);
    headers.forEach(request.headers.set);
    if (body.isNotEmpty) {
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    return (
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

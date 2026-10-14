import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/llm_runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/data/mutable_runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/data/worker_job_server.dart';
import 'package:evaluetron_worker_app/features/worker/domain/llm_runtime_settings.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole path a customer's words travel on this device, with nothing stubbed
/// between the brain's socket and the model server's.
///
/// Every layer below is covered on its own; this exists because the failures that
/// actually reach customers live in the joins. A dispatch the brain signs has to
/// authenticate, reach a runtime that was probed rather than assumed, be refused
/// when the runtime is not ready, and come back as bytes the brain can store —
/// and no unit test of any one part can say whether those five things line up.
void main() {
  const token = 'evn_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  late HttpServer modelServer;
  late Uri modelBase;
  late MutableRuntimeAdapter runtime;
  late HttpWorkerJobServer worker;
  late String served;
  late String reply;

  setUp(() async {
    // Reset per test: these are what each case varies to stand for a model being
    // pulled or a model answering with nothing, and leaking one into the next
    // test is how a suite starts lying about which behaviour it proved.
    served = 'qwen3-local';
    reply = 'Because the tide was out.';
    modelServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    modelBase = Uri.parse('http://127.0.0.1:${modelServer.port}');
    modelServer.listen((request) async {
      await utf8.decoder.bind(request).join();
      final body = switch (request.uri.path) {
        '/v1/models' => {
          'data': [
            {'id': served},
          ],
        },
        '/v1/chat/completions' => {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': reply},
              'finish_reason': 'stop',
            },
          ],
        },
        _ => null,
      };
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });

    runtime = MutableRuntimeAdapter(
      LlmRuntimeAdapter(
        settings: LlmRuntimeSettings.parse(
          baseUrl: modelBase.toString(),
          model: 'qwen3-local',
        ),
      ),
    );
    worker = HttpWorkerJobServer(
      adapter: runtime,
      port: 0,
      advertisedHost: '127.0.0.1',
    );
    await worker.start(
      NodeRegistration(
        brainBaseUrl: Uri.parse('http://127.0.0.1:8082'),
        nodeId: 'node',
        credentialId: 'credential',
        nodeName: 'worker-e2e',
        nodeToken: token,
        roles: const ['worker'],
      ),
    );
  });

  tearDown(() async {
    await worker.stop();
    await modelServer.close(force: true);
  });

  Future<({int status, String body})> dispatch(Map<String, Object?> params) {
    final body = utf8.encode(
      jsonEncode({'generator': 'llm', 'params': params}),
    );
    return _post(
      worker.endpoint!.resolve('/jobs'),
      body,
      _signedHeaders(token, body),
    );
  }

  test(
    'a signed dispatch reaches the model and comes back as an artifact',
    () async {
      await worker.probeRuntime();

      final health = await _get(worker.endpoint!.resolve('/health'));
      expect(jsonDecode(health.body)['runtimeReady'], isTrue);
      expect(jsonDecode(health.body)['models'], {
        'llm': ['qwen3-local'],
      });

      final answer = await dispatch({'prompt': 'why is the sea salty?'});

      expect(answer.status, HttpStatus.ok);
      expect(answer.body, 'Because the tide was out.');
    },
  );

  test('refuses work before the runtime has been probed', () async {
    // The listener is up and the credential is good, but nothing has proved the
    // model server is there. Advertising follows proof, and so does serving.
    final answer = await dispatch({'prompt': 'too early'});

    expect(answer.status, HttpStatus.badRequest);
    final health = await _get(worker.endpoint!.resolve('/health'));
    expect(jsonDecode(health.body)['runtimeReady'], isFalse);
    expect(jsonDecode(health.body)['generators'], isEmpty);
  });

  test('stops serving when the model behind it goes away', () async {
    await worker.probeRuntime();
    expect((await dispatch({'prompt': 'first'})).status, HttpStatus.ok);

    // The operator pulls the model; the server is still up and still answers.
    served = 'something-else';
    await worker.probeRuntime();

    expect(
      (await dispatch({'prompt': 'second'})).status,
      HttpStatus.badRequest,
    );
    final health = await _get(worker.endpoint!.resolve('/health'));
    expect(jsonDecode(health.body)['runtimeReady'], isFalse);
  });

  test('reports a runtime failure as a gateway fault, not as success', () async {
    // The brain reads this status to decide whether the customer is charged. An
    // empty answer returned as 200 produced a job the brain called successful and
    // then could not deliver.
    await worker.probeRuntime();
    reply = '   ';

    final answer = await dispatch({'prompt': 'say nothing'});

    expect(answer.status, HttpStatus.badGateway);
  });

  test(
    'swapping the runtime withdraws the old one until the new is proved',
    () async {
      await worker.probeRuntime();
      expect((await dispatch({'prompt': 'first'})).status, HttpStatus.ok);

      // What happens when somebody corrects the address on the Runtime screen: the
      // listener, the registration and the heartbeat all survive it.
      runtime.adopt(const UnavailableRuntimeAdapter());

      expect(
        (await dispatch({'prompt': 'second'})).status,
        HttpStatus.badRequest,
      );
      expect(worker.endpoint, isNotNull);
    },
  );

  test('an unsigned dispatch never reaches the model at all', () async {
    await worker.probeRuntime();
    final body = utf8.encode(
      jsonEncode({
        'generator': 'llm',
        'params': {'prompt': 'let me in'},
      }),
    );

    final answer = await _post(
      worker.endpoint!.resolve('/jobs'),
      body,
      const {},
    );

    expect(answer.status, HttpStatus.unauthorized);
  });
}

Map<String, String> _signedHeaders(String token, List<int> body) {
  final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
      .toString();
  final nonce = base64Url
      .encode(
        List<int>.generate(
          16,
          (index) => (index * 7 + DateTime.now().microsecond) % 251,
        ),
      )
      .replaceAll('=', '');
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

Future<({int status, String body})> _get(Uri endpoint) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(endpoint)).close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<({int status, String body})> _post(
  Uri endpoint,
  List<int> body,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint);
    headers.forEach(request.headers.set);
    request
      ..headers.contentType = ContentType.json
      ..contentLength = body.length
      ..add(body);
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

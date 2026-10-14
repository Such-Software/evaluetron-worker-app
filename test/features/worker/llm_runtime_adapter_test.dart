import 'dart:convert';
import 'dart:io';

import 'package:evaluetron_worker_app/features/worker/data/llm_runtime_adapter.dart';
import 'package:evaluetron_worker_app/features/worker/domain/llm_runtime_settings.dart';
import 'package:evaluetron_worker_app/features/worker/domain/runtime_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in model server on loopback.
///
/// A real socket rather than a mocked client, because the things worth checking
/// here are the request path, the shape on the wire, and what happens when the
/// other end misbehaves — none of which a mock would tell the truth about.
class _FakeModelServer {
  _FakeModelServer(this._server) {
    _server.listen((request) async {
      requestedPaths.add(request.uri.path);
      final body = await utf8.decoder.bind(request).join();
      if (body.isNotEmpty) {
        lastRequest = (jsonDecode(body) as Map<Object?, Object?>)
            .cast<String, Object?>();
      }
      final handler = handlers[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final answer = handler();
      request.response
        ..statusCode = answer.status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(answer.body));
      await request.response.close();
    });
  }

  static Future<_FakeModelServer> start() async =>
      _FakeModelServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final requestedPaths = <String>[];
  final handlers =
      <String, ({int status, Map<String, Object?> body}) Function()>{};
  Map<String, Object?>? lastRequest;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  void servesOpenAiModels(List<String> ids) {
    handlers['/v1/models'] = () => (
      status: HttpStatus.ok,
      body: {
        'data': [
          for (final id in ids) {'id': id},
        ],
      },
    );
  }

  void servesOllamaModels(List<String> names, {String prefix = ''}) {
    handlers['$prefix/api/tags'] = () => (
      status: HttpStatus.ok,
      body: {
        'models': [
          for (final name in names) {'name': name},
        ],
      },
    );
  }

  void answers(
    String content, {
    String path = '/v1/chat/completions',
    String finish = 'stop',
  }) {
    handlers[path] = () => (
      status: HttpStatus.ok,
      body: path.endsWith('/api/chat')
          ? {
              'message': {'role': 'assistant', 'content': content},
            }
          : {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': content},
                  'finish_reason': finish,
                },
              ],
            },
    );
  }

  Future<void> close() => _server.close(force: true);
}

void main() {
  late _FakeModelServer server;

  setUp(() async => server = await _FakeModelServer.start());
  tearDown(() => server.close());

  LlmRuntimeAdapter adapterFor({
    String model = 'qwen3-local',
    bool think = false,
    Uri? base,
  }) {
    return LlmRuntimeAdapter(
      settings: LlmRuntimeSettings.parse(
        baseUrl: (base ?? server.baseUrl).toString(),
        model: model,
        think: think,
      ),
      probeTimeout: const Duration(seconds: 2),
      requestTimeout: const Duration(seconds: 5),
    );
  }

  group('proving what this node can do', () {
    test('advertises nothing until a probe has succeeded', () {
      // Fail-closed is the whole posture: a descriptor is never optimistic, so a
      // node that has not yet checked is a node the brain routes around.
      expect(adapterFor().descriptor.ready, isFalse);
      expect(adapterFor().descriptor.generators, isEmpty);
    });

    test('advertises the generator and the model together once it has', () async {
      // Never one without the other: the router selects by advertised model, so a
      // generator with no model under it is one no job can ever reach.
      server.servesOpenAiModels(['qwen3-local']);
      final adapter = adapterFor(
        base: server.baseUrl.replace(port: server.baseUrl.port),
      );

      final descriptor = await adapter.probe();

      expect(descriptor.ready, isTrue);
      expect(descriptor.generators, ['llm']);
      expect(descriptor.models['llm'], ['qwen3-local']);
      expect(descriptor.methods['llm'], ['openai-compatible']);
      expect(adapter.probeFailure, isNull);
    });

    test(
      'refuses to advertise a model the server does not actually serve',
      () async {
        // Reachability is not readiness. A server that never pulled the model would
        // take every job and fail it, costing a customer the wait and this operator
        // the dispatch.
        server.servesOpenAiModels(['some-other-model']);
        final adapter = adapterFor();

        expect((await adapter.probe()).ready, isFalse);
        expect(adapter.probeFailure, contains('does not serve'));
      },
    );

    test('treats an unreachable runtime as an answer, not an error', () async {
      // The caller's only sensible response either way is to advertise nothing,
      // so a probe that throws would just make every call site write the same
      // catch block.
      final adapter = LlmRuntimeAdapter(
        settings: LlmRuntimeSettings.parse(
          baseUrl: 'http://127.0.0.1:1',
          model: 'qwen3-local',
        ),
        probeTimeout: const Duration(milliseconds: 500),
      );

      expect((await adapter.probe()).ready, isFalse);
      expect(adapter.probeFailure, isNotNull);
      expect(adapter.probeFailure, isNot(contains('127.0.0.1')));
    });

    test('withdraws what it advertised when a later probe fails', () async {
      server.servesOpenAiModels(['qwen3-local']);
      final adapter = adapterFor();
      expect((await adapter.probe()).ready, isTrue);

      server.handlers.clear();
      expect((await adapter.probe()).ready, isFalse);
      expect(adapter.descriptor.generators, isEmpty);
    });
  });

  group('running a job', () {
    test('answers a prompt through the portable endpoint', () async {
      server
        ..servesOpenAiModels(['qwen3-local'])
        ..answers('Sixty-seven.');
      final adapter = adapterFor();
      await adapter.probe();

      final artifact = await adapter.run('llm', {'prompt': 'how many?'});

      expect(utf8.decode(artifact.bytes), 'Sixty-seven.');
      expect(artifact.contentType, 'text/plain; charset=utf-8');
      expect(server.requestedPaths, contains('/v1/chat/completions'));
      expect(server.lastRequest!['model'], 'qwen3-local');
      expect(server.lastRequest!['stream'], isFalse);
    });

    test('takes the words under either name the brain sends them by', () async {
      // `text` is what the job schema has always called them; `prompt` is what
      // every chat command sends. Accepting one produced a "required" error on a
      // request the customer could plainly see they had typed.
      server
        ..servesOpenAiModels(['qwen3-local'])
        ..answers('fine');
      final adapter = adapterFor();
      await adapter.probe();

      await adapter.run('llm', {'text': 'under text'});
      expect((server.lastRequest!['messages']! as List).last, {
        'role': 'user',
        'content': 'under text',
      });
      await adapter.run('llm', {'prompt': 'under prompt'});
      expect((server.lastRequest!['messages']! as List).last, {
        'role': 'user',
        'content': 'under prompt',
      });
    });

    test('uses Ollama’s own endpoint, and asks it not to reason', () async {
      // Its OpenAI-compatible endpoint ignores every documented way of turning
      // reasoning off.
      final ollama = await _FakeModelServer.start();
      addTearDown(ollama.close);
      ollama
        ..servesOllamaModels(['qwen3:8b'], prefix: '/ollama')
        ..answers('brief', path: '/ollama/api/chat');
      final adapter = LlmRuntimeAdapter(
        settings: LlmRuntimeSettings.parse(
          // Recognised by path rather than port, since the fake binds an
          // ephemeral one — the same shape as Ollama behind a reverse proxy.
          baseUrl: 'http://127.0.0.1:${ollama.baseUrl.port}/ollama',
          model: 'qwen3:8b',
        ),
      );

      expect((await adapter.probe()).methods['llm'], ['ollama']);
      final artifact = await adapter.run('llm', {'prompt': 'hello'});

      expect(utf8.decode(artifact.bytes), 'brief');
      expect(ollama.lastRequest!['think'], isFalse);
      expect(
        (ollama.lastRequest!['options']! as Map)['num_predict'],
        isA<int>(),
      );
    });

    test(
      'clamps a requested answer length to the operator’s ceiling',
      () async {
        server
          ..servesOpenAiModels(['qwen3-local'])
          ..answers('ok');
        final adapter = LlmRuntimeAdapter(
          settings: LlmRuntimeSettings.parse(
            baseUrl: server.baseUrl.toString(),
            model: 'qwen3-local',
            maxTokens: 64,
          ),
        );
        await adapter.probe();

        await adapter.run('llm', {'prompt': 'x', 'max_tokens': 100000});

        expect(server.lastRequest!['max_tokens'], 64);
      },
    );

    test('fails loudly when the model answers with nothing', () async {
      // A reasoning model that spent its whole budget thinking returns nothing
      // usable. Failing here releases the credit hold and reports something true;
      // returning empty bytes produced a job the brain called successful and then
      // could not deliver.
      server
        ..servesOpenAiModels(['qwen3-local'])
        ..answers('   ', finish: 'length');
      final adapter = adapterFor();
      await adapter.probe();

      await expectLater(
        adapter.run('llm', {'prompt': 'think about it'}),
        throwsA(
          isA<RuntimeRequestException>().having(
            (error) => error.message,
            'message',
            allOf(contains('nothing'), contains('length')),
          ),
        ),
      );
    });

    test(
      'refuses a web-grounded request rather than answering as if it had searched',
      () async {
        // A local model with no search attached cannot honour this flag, and
        // answering from training data while appearing to have searched is the one
        // failure a web-grounded answer cannot afford. Refusing releases the hold
        // and lets the brain route it to a node that can.
        server
          ..servesOpenAiModels(['qwen3-local'])
          ..answers('I would be making this up.');
        final adapter = adapterFor();
        await adapter.probe();

        await expectLater(
          adapter.run('llm', {'prompt': 'what happened today', 'web': true}),
          throwsA(isA<RuntimeRequestException>()),
        );
        expect(server.requestedPaths, isNot(contains('/v1/chat/completions')));
      },
    );

    test(
      'refuses a generator it does not serve, and any job before it is ready',
      () async {
        server
          ..servesOpenAiModels(['qwen3-local'])
          ..answers('ok');
        final unprobed = adapterFor();

        await expectLater(
          unprobed.run('llm', {'prompt': 'too early'}),
          throwsA(isA<RuntimeRequestException>()),
        );
        await unprobed.probe();
        await expectLater(
          unprobed.run('image', {'prompt': 'not mine'}),
          throwsA(isA<RuntimeRequestException>()),
        );
      },
    );

    test('refuses an empty prompt without troubling the runtime', () async {
      server
        ..servesOpenAiModels(['qwen3-local'])
        ..answers('ok');
      final adapter = adapterFor();
      await adapter.probe();
      server.requestedPaths.clear();

      await expectLater(
        adapter.run('llm', {'prompt': '   '}),
        throwsA(isA<RuntimeRequestException>()),
      );
      expect(server.requestedPaths, isEmpty);
    });

    test('reports a runtime refusal by status, never by its body', () async {
      // A model server's error text names file paths and internal hosts, and this
      // message travels to the brain and on to a customer.
      server.servesOpenAiModels(['qwen3-local']);
      server.handlers['/v1/chat/completions'] = () => (
        status: HttpStatus.internalServerError,
        body: {'error': 'failed loading /srv/models/qwen3.gguf on 10.42.0.7'},
      );
      final adapter = adapterFor();
      await adapter.probe();

      await expectLater(
        adapter.run('llm', {'prompt': 'x'}),
        throwsA(
          isA<RuntimeRequestException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('500'),
              isNot(contains('10.42')),
              isNot(contains('gguf')),
            ),
          ),
        ),
      );
    });
  });
}

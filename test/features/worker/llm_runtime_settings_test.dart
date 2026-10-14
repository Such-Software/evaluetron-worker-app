import 'package:evaluetron_worker_app/features/worker/domain/llm_runtime_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LlmRuntimeSettings parse(
    String baseUrl, {
    String model = 'qwen3:8b',
    bool think = false,
  }) => LlmRuntimeSettings.parse(baseUrl: baseUrl, model: model, think: think);

  group('the address somebody typed', () {
    test('accepts a base with or without /v1, and stores one form', () {
      // Every OpenAI-compatible client documents its base *with* /v1, so both are
      // things a person reasonably types. Keeping either verbatim produces
      // /v1/v1/chat/completions and a 404 that names nothing useful.
      expect(
        parse('http://127.0.0.1:8080/v1').baseUrl.toString(),
        'http://127.0.0.1:8080',
      );
      expect(
        parse('http://127.0.0.1:8080/v1/').baseUrl.toString(),
        'http://127.0.0.1:8080',
      );
      expect(
        parse('http://127.0.0.1:8080/').baseUrl.toString(),
        'http://127.0.0.1:8080',
      );
      expect(
        parse('http://127.0.0.1:8080').baseUrl.toString(),
        'http://127.0.0.1:8080',
      );
    });

    test(
      'keeps a path that is not /v1, because a reverse proxy may add one',
      () {
        expect(
          parse('http://10.0.0.5/models/v1').baseUrl.toString(),
          'http://10.0.0.5/models',
        );
        expect(
          parse('http://10.0.0.5/llama').baseUrl.toString(),
          'http://10.0.0.5/llama',
        );
      },
    );

    test('accepts loopback and every private range, including CGNAT', () {
      // CGNAT is where several mesh VPNs put their peers, so a Pi reached over
      // one is a local runtime by any sensible reading.
      for (final host in [
        'localhost',
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.10',
        '169.254.4.4',
        '100.64.0.1',
        '[::1]',
        '[fd00::1]',
        '[fe80::1]',
      ]) {
        expect(
          () => parse('http://$host:11434'),
          returnsNormally,
          reason: host,
        );
      }
    });

    test(
      'refuses a runtime that is not on this device or its private network',
      () {
        // A "local model" reachable across the internet is not a local model, and
        // sending every question a customer asks to an arbitrary host is the
        // privacy position this service sells against.
        for (final host in [
          'example.com',
          '8.8.8.8',
          '172.32.0.1',
          '100.128.0.1',
          '[2001:db8::1]',
        ]) {
          expect(
            () => parse('http://$host:11434'),
            throwsA(isA<LlmRuntimeSettingsException>()),
            reason: host,
          );
        }
      },
    );

    test(
      'refuses an address that is not one, or that hides something in itself',
      () {
        expect(
          () => parse('ftp://127.0.0.1'),
          throwsA(isA<LlmRuntimeSettingsException>()),
        );
        expect(
          () => parse('127.0.0.1:8080'),
          throwsA(isA<LlmRuntimeSettingsException>()),
        );
        expect(() => parse(''), throwsA(isA<LlmRuntimeSettingsException>()));
        expect(
          () => parse('http://user:pass@127.0.0.1:8080'),
          throwsA(isA<LlmRuntimeSettingsException>()),
        );
        expect(
          () => parse('http://127.0.0.1:8080?k=v'),
          throwsA(isA<LlmRuntimeSettingsException>()),
        );
        expect(
          () => parse('http://127.0.0.1:8080#f'),
          throwsA(isA<LlmRuntimeSettingsException>()),
        );
      },
    );
  });

  group('the model somebody named', () {
    test('accepts the punctuation real model names carry', () {
      // Ollama tags with a colon and every aggregator namespaces with a slash.
      // Validating these as plain identifiers rejected every model in service.
      for (final model in [
        'qwen3:8b',
        'meta-llama/llama-3.3-70b-instruct',
        'gemma-2-9b.Q4_K_M',
      ]) {
        expect(
          () => parse('http://127.0.0.1:11434', model: model),
          returnsNormally,
          reason: model,
        );
      }
    });

    test('refuses an empty or malformed name', () {
      for (final model in [
        '',
        '   ',
        '../etc/passwd',
        'has space',
        r'semi;colon',
      ]) {
        expect(
          () => parse('http://127.0.0.1:11434', model: model),
          throwsA(isA<LlmRuntimeSettingsException>()),
          reason: model,
        );
      }
    });
  });

  group('which dialect to speak', () {
    test('uses Ollama’s own endpoint when reasoning must be off', () {
      // Its OpenAI-compatible endpoint ignores every documented way of turning
      // reasoning off, and reasoning nobody reads is time somebody spends
      // watching a typing indicator.
      expect(
        parse('http://127.0.0.1:11434').dialect,
        LlmServerDialect.ollamaNative,
      );
      // Behind a reverse proxy, where the port says nothing.
      expect(
        parse('http://192.168.1.5/ollama').dialect,
        LlmServerDialect.ollamaNative,
      );
    });

    test('does not look for it in a hostname, which can never carry one', () {
      // parse() accepts only address literals and `localhost`, so a hostname
      // check would read like a safety net while catching nothing. Naming this
      // keeps somebody from adding one back.
      expect(
        () => parse('http://ollama.local:8080'),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
    });

    test(
      'keeps the portable path for anything else, and whenever reasoning is wanted',
      () {
        expect(
          parse('http://127.0.0.1:8080').dialect,
          LlmServerDialect.openAiCompatible,
        );
        // Asking Ollama to reason is a request its compatibility endpoint honours,
        // so there is nothing left for the native path to fix.
        expect(
          parse('http://127.0.0.1:11434', think: true).dialect,
          LlmServerDialect.openAiCompatible,
        );
      },
    );
  });

  group('bounds', () {
    test('refuses an answer length outside what the transports can carry', () {
      final base = 'http://127.0.0.1:11434';
      expect(
        () => LlmRuntimeSettings.parse(baseUrl: base, model: 'm', maxTokens: 0),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
      expect(
        () => LlmRuntimeSettings.parse(
          baseUrl: base,
          model: 'm',
          maxTokens: 4096,
        ),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
      expect(
        () =>
            LlmRuntimeSettings.parse(baseUrl: base, model: 'm', temperature: 3),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
    });
  });

  group('what survives storage', () {
    test('round-trips', () {
      final original = LlmRuntimeSettings.parse(
        baseUrl: 'http://192.168.1.50:8080/v1',
        model: 'qwen3:8b',
        maxTokens: 512,
        temperature: 0.2,
        think: true,
      );
      final restored = LlmRuntimeSettings.fromJson(original.toJson());

      expect(restored.baseUrl, original.baseUrl);
      expect(restored.model, original.model);
      expect(restored.maxTokens, 512);
      expect(restored.temperature, 0.2);
      expect(restored.think, isTrue);
    });

    test('re-runs every bound rather than trusting what was written', () {
      // A build that tightens a bound must not keep honouring a value an older
      // one wrote, and the file sits on a device its owner can edit.
      expect(
        () => LlmRuntimeSettings.fromJson({
          'baseUrl': 'http://example.com:8080',
          'model': 'qwen3:8b',
        }),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
      expect(
        () => LlmRuntimeSettings.fromJson({
          'baseUrl': 'http://127.0.0.1:8080',
          'model': 'qwen3:8b',
          'maxTokens': 999999,
        }),
        throwsA(isA<LlmRuntimeSettingsException>()),
      );
    });
  });
}

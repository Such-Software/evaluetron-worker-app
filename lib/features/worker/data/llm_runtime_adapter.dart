import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/llm_runtime_settings.dart';
import '../domain/runtime_adapter.dart';

/// Executes `llm` jobs against a model server running on this device or its
/// private network.
///
/// Delegating over HTTP rather than linking an inference engine into the app is
/// what makes this node real today: `llama-server`, Ollama and vLLM all speak the
/// same request, they are what a Raspberry Pi or a rooted handset actually runs,
/// and the Python worker has been serving customers through this exact contract
/// for months. An in-process engine — llama.cpp over FFI — is a second
/// implementation of [WorkerRuntimeAdapter] rather than a rewrite of this one:
/// that is the point of the seam.
///
/// Everything here is bounded, because the other end is a process this app does
/// not supervise and the caller is a brain that has already reserved a customer's
/// credits against an answer arriving.
class LlmRuntimeAdapter implements WorkerRuntimeAdapter {
  LlmRuntimeAdapter({
    required LlmRuntimeSettings settings,
    HttpClient? client,
    Duration probeTimeout = const Duration(seconds: 5),
    Duration requestTimeout = const Duration(seconds: 180),
    int maxResponseBytes = 4 * 1024 * 1024,
  }) : _settings = settings,
       _client = client ?? HttpClient(),
       _probeTimeout = probeTimeout,
       _requestTimeout = requestTimeout,
       _maxResponseBytes = maxResponseBytes;

  /// The generator this adapter serves. One, deliberately: a phone that claims
  /// image or speech it cannot deliver is worse than a phone that claims nothing.
  static const generator = 'llm';

  final LlmRuntimeSettings _settings;
  final HttpClient _client;
  final Duration _probeTimeout;
  final Duration _requestTimeout;
  final int _maxResponseBytes;

  RuntimeDescriptor _descriptor = RuntimeDescriptor.unavailable;

  @override
  RuntimeDescriptor get descriptor => _descriptor;

  LlmRuntimeSettings get settings => _settings;

  /// Why the last probe failed, for a person looking at the Worker screen.
  ///
  /// Held separately from the descriptor because the brain must be told only that
  /// this node serves nothing, while the person holding the device needs to know
  /// whether their server is down or their model name is wrong.
  String? probeFailure;

  /// Ask the server what it serves, and believe it only if it names our model.
  ///
  /// Reachability alone is not readiness. A server that is up but has never
  /// pulled the configured model would take every job and fail it, which costs a
  /// customer the wait and this operator the dispatch, so the model has to appear
  /// in the server's own listing before this node advertises anything.
  @override
  Future<RuntimeDescriptor> probe() async {
    try {
      final served = await _listModels();
      if (!served.contains(_settings.model)) {
        probeFailure = served.isEmpty
            ? 'The runtime is reachable but serves no models.'
            : 'The runtime does not serve "${_settings.model}".';
        return _descriptor = RuntimeDescriptor.unavailable;
      }
      probeFailure = null;
      return _descriptor = RuntimeDescriptor.serving(
        models: {
          generator: [_settings.model],
        },
        methods: {
          generator: [_settings.dialect.wireName],
        },
      );
    } on TimeoutException {
      probeFailure = 'The model runtime did not answer in time.';
      return _descriptor = RuntimeDescriptor.unavailable;
    } on Object {
      // Deliberately not the underlying message: it names a host and a port, and
      // this string is shown on screen and may be carried to the brain.
      probeFailure = 'No model runtime answered at that address.';
      return _descriptor = RuntimeDescriptor.unavailable;
    }
  }

  @override
  Future<RuntimeArtifact> run(
    String generatorName,
    Map<String, Object?> parameters,
  ) async {
    if (generatorName != generator || !_descriptor.ready) {
      throw const RuntimeRequestException(
        'This node does not serve that generator.',
      );
    }

    final prompt = _prompt(parameters);
    if (parameters['web'] == true) {
      // The brain sends this to ask for an answer grounded in a live search. A
      // resold model that searches for itself may ignore it safely; a local model
      // with no search attached may not, because answering from training data
      // while appearing to have searched is the one failure a web-grounded answer
      // cannot afford. Refusing releases the customer's hold and tells them
      // something true, so the brain can route the request to a node that can.
      throw const RuntimeRequestException(
        'This node cannot ground an answer in a live web search.',
      );
    }

    final budget = _budget(parameters);
    final messages = <Map<String, String>>[
      if (_settings.systemPrompt.isNotEmpty)
        {'role': 'system', 'content': _settings.systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final answer = switch (_settings.dialect) {
      LlmServerDialect.ollamaNative => await _askOllama(messages, budget),
      LlmServerDialect.openAiCompatible => await _askOpenAiCompatible(
        messages,
        budget,
      ),
    };

    return RuntimeArtifact(
      contentType: 'text/plain; charset=utf-8',
      bytes: Uint8List.fromList(utf8.encode(answer)),
    );
  }

  /// The customer's words, under either name the brain may send them by.
  ///
  /// `text` is what the job schema has always called them and `prompt` is what
  /// every chat command sends; accepting only one produced a "required" error on
  /// a request the customer could plainly see they had typed.
  static String _prompt(Map<String, Object?> parameters) {
    final text = parameters['text'];
    final prompt = parameters['prompt'];
    final chosen = (text is String && text.trim().isNotEmpty)
        ? text
        : (prompt is String ? prompt : '');
    final trimmed = chosen.trim();
    if (trimmed.isEmpty) {
      throw const RuntimeRequestException('That request carried no prompt.');
    }
    return trimmed;
  }

  int _budget(Map<String, Object?> parameters) {
    final requested = parameters['max_tokens'];
    final asked = requested is num ? requested.toInt() : _settings.maxTokens;
    return asked.clamp(1, _settings.maxTokens);
  }

  Future<String> _askOpenAiCompatible(
    List<Map<String, String>> messages,
    int budget,
  ) async {
    final body = await _postJson(
      _settings.baseUrl.resolve(
        '${_settings.baseUrl.path}/v1/chat/completions',
      ),
      {
        'model': _settings.model,
        'messages': messages,
        'max_tokens': budget,
        'temperature': _settings.temperature,
        'stream': false,
      },
    );
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const RuntimeRequestException(
        'The model runtime returned no answer.',
      );
    }
    final choice = (choices.first as Map<Object?, Object?>)
        .cast<String, Object?>();
    final message = (choice['message'] as Map<Object?, Object?>?)
        ?.cast<String, Object?>();
    final content = (message?['content'] as String? ?? '').trim();
    if (content.isEmpty) {
      // A reasoning model that spent its whole budget thinking returns nothing
      // usable. Failing here releases the credit hold and reports something true;
      // returning empty bytes produced a job the brain called successful and then
      // could not deliver.
      final reason = choice['finish_reason'] as String? ?? 'unknown';
      throw RuntimeRequestException(
        'The model answered with nothing (finish_reason=$reason). '
        'Allow a longer answer, or turn reasoning off.',
      );
    }
    return content;
  }

  Future<String> _askOllama(
    List<Map<String, String>> messages,
    int budget,
  ) async {
    final body = await _postJson(
      _settings.baseUrl.resolve('${_settings.baseUrl.path}/api/chat'),
      {
        'model': _settings.model,
        'messages': messages,
        // The reason this path exists at all: Ollama's OpenAI-compatible endpoint
        // ignores every documented way of asking a model not to reason.
        'think': false,
        'stream': false,
        'options': {
          'num_predict': budget,
          'temperature': _settings.temperature,
        },
      },
    );
    final message = (body['message'] as Map<Object?, Object?>?)
        ?.cast<String, Object?>();
    final content = (message?['content'] as String? ?? '').trim();
    if (content.isEmpty) {
      throw const RuntimeRequestException(
        'The model answered with nothing. Allow a longer answer, or turn reasoning on for this model.',
      );
    }
    return content;
  }

  /// What the server says it serves, in whichever shape its dialect answers.
  Future<Set<String>> _listModels() async {
    if (_settings.dialect == LlmServerDialect.ollamaNative) {
      final body = await _getJson(
        _settings.baseUrl.resolve('${_settings.baseUrl.path}/api/tags'),
        _probeTimeout,
      );
      final models = body['models'];
      if (models is! List) return const {};
      return {
        for (final entry in models)
          if (entry is Map && entry['name'] is String) entry['name']! as String,
        // Ollama names a model `qwen3:8b` but reports `qwen3:8b` only with its
        // tag; accept the bare name too so a person who typed one is not told
        // their model is missing when it is sitting right there.
        for (final entry in models)
          if (entry is Map && entry['name'] is String)
            (entry['name']! as String).split(':').first,
      };
    }
    final body = await _getJson(
      _settings.baseUrl.resolve('${_settings.baseUrl.path}/v1/models'),
      _probeTimeout,
    );
    final data = body['data'];
    if (data is! List) return const {};
    return {
      for (final entry in data)
        if (entry is Map && entry['id'] is String) entry['id']! as String,
    };
  }

  Future<Map<String, Object?>> _getJson(Uri url, Duration timeout) async {
    final request = await _client.getUrl(url).timeout(timeout);
    request.followRedirects = false;
    return _readJson(await request.close().timeout(timeout), timeout);
  }

  Future<Map<String, Object?>> _postJson(
    Uri url,
    Map<String, Object?> payload,
  ) async {
    final HttpClientResponse response;
    try {
      final request = await _client.postUrl(url).timeout(_requestTimeout);
      final encoded = utf8.encode(jsonEncode(payload));
      request
        ..followRedirects = false
        ..headers.contentType = ContentType.json
        ..headers.contentLength = encoded.length
        ..add(encoded);
      response = await request.close().timeout(_requestTimeout);
    } on TimeoutException {
      throw const RuntimeRequestException(
        'The model runtime did not answer in time.',
      );
    } on Object {
      throw const RuntimeRequestException(
        'This node could not reach its model runtime.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The status, never the body: a model server's error text names file paths
      // and internal hosts, and this reaches the brain.
      throw RuntimeRequestException(
        'The model runtime refused the request (${response.statusCode}).',
      );
    }
    try {
      return await _readJson(response, _requestTimeout);
    } on RuntimeRequestException {
      rethrow;
    } on Object {
      throw const RuntimeRequestException(
        'The model runtime returned something unreadable.',
      );
    }
  }

  /// Read a bounded JSON object, so a runaway server cannot exhaust a phone.
  Future<Map<String, Object?>> _readJson(
    HttpClientResponse response,
    Duration timeout,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > _maxResponseBytes) {
        throw const RuntimeRequestException(
          'The model runtime returned too much data.',
        );
      }
    }
    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
    if (decoded is! Map) {
      throw const RuntimeRequestException(
        'The model runtime returned something unreadable.',
      );
    }
    return decoded.cast<String, Object?>();
  }
}

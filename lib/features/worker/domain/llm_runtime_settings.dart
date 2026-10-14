/// Where this node's language model runs, and how it should be asked.
///
/// A value object rather than a bag of strings because every field here has a
/// bound that matters, and the bounds are easier to defend in one place than at
/// each call site. Parsing is total: [LlmRuntimeSettings.parse] either returns
/// settings that the adapter can use without re-checking anything, or throws with
/// a sentence the person typing can act on.
library;

class LlmRuntimeSettingsException implements Exception {
  const LlmRuntimeSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Which dialect the adapter speaks to the server behind [LlmRuntimeSettings].
enum LlmServerDialect {
  /// `POST {base}/v1/chat/completions`. Works with llama.cpp's `llama-server`,
  /// vLLM, LM Studio, and Ollama's compatibility endpoint.
  openAiCompatible('openai-compatible'),

  /// `POST {base}/api/chat`. Ollama's own endpoint, which is used only because
  /// its OpenAI-compatible one ignores every documented way of turning reasoning
  /// off — and reasoning nobody reads is time a person spends watching a typing
  /// indicator.
  ollamaNative('ollama');

  const LlmServerDialect(this.wireName);

  /// What the brain's console shows as this node's method for `llm`.
  final String wireName;
}

class LlmRuntimeSettings {
  const LlmRuntimeSettings._({
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.systemPrompt,
    required this.think,
  });

  /// A ceiling, not a target. For a locally hosted model the only thing it spends
  /// is time, and the transports this service answers on truncate well before
  /// 2048 tokens of prose. Matched to the Python worker so the same model gives
  /// the same answer whichever node serves it.
  static const maxTokenCeiling = 2048;
  static const defaultMaxTokens = maxTokenCeiling;
  static const defaultTemperature = 0.7;

  /// Chat is not a document.
  ///
  /// Without this a model answers a one-line question with headings, bold markup
  /// and a bulleted list, which arrives as literal asterisks because the
  /// transports send plain text on purpose, and runs past what a phone shows.
  static const defaultSystemPrompt =
      'You are answering in a group chat. Reply in at most three short sentences, '
      'in plain prose. No markdown, no bullet points, no headings, no bold. '
      'Answer the question directly and stop; do not offer follow-up help.';

  /// The server root, with no trailing slash and no trailing `/v1`.
  ///
  /// Both forms are things a person reasonably types — every OpenAI-compatible
  /// client documents its base *with* `/v1` — and keeping either verbatim
  /// produces `/v1/v1/chat/completions` and a 404 that names nothing useful.
  final Uri baseUrl;
  final String model;
  final int maxTokens;
  final double temperature;
  final String systemPrompt;

  /// Let the model reason before answering.
  ///
  /// Off by default because it is slow and invisible: measured on qwen3:8b, 416
  /// tokens in 8.7s with thinking against 174 in 3.9s without, for an answer of
  /// the same length and quality. Turn it on for a model that has to reason to be
  /// right.
  final bool think;

  /// Which dialect to speak, inferred rather than configured.
  ///
  /// Asking a person to name their server's dialect is asking them to know
  /// something the address already says, and to get it wrong in a way that
  /// produces a puzzling 404.
  ///
  /// Ollama is recognised by its port, or by a path segment where it sits behind
  /// a reverse proxy. Deliberately *not* by hostname: [parse] accepts only
  /// address literals and `localhost`, so no host this can ever see could carry
  /// the name, and a check for one would read like a safety net while catching
  /// nothing. A person running it somewhere unrecognisable still gets a working
  /// node over the compatibility endpoint, only with reasoning left on.
  LlmServerDialect get dialect {
    if (think) return LlmServerDialect.openAiCompatible;
    final looksLikeOllama =
        baseUrl.port == 11434 ||
        baseUrl.pathSegments.any(
          (segment) => segment.toLowerCase() == 'ollama',
        );
    return looksLikeOllama
        ? LlmServerDialect.ollamaNative
        : LlmServerDialect.openAiCompatible;
  }

  /// Parse what a person typed into settings the adapter can trust.
  ///
  /// The address bound is deliberate and narrower than the Python worker's, which
  /// runs on a machine an operator chose and can point anywhere. This runs on a
  /// phone somebody carries, so a runtime address is accepted only on loopback or
  /// a private network: a "local model" reachable across the internet is not a
  /// local model, and sending every question a customer asks to an arbitrary host
  /// is exactly the privacy position this service sells against.
  static LlmRuntimeSettings parse({
    required String baseUrl,
    required String model,
    int maxTokens = defaultMaxTokens,
    double temperature = defaultTemperature,
    String systemPrompt = defaultSystemPrompt,
    bool think = false,
  }) {
    final trimmedModel = model.trim();
    if (trimmedModel.isEmpty) {
      throw const LlmRuntimeSettingsException(
        'Name the model this node serves.',
      );
    }
    if (trimmedModel.length > 128 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$').hasMatch(trimmedModel)) {
      throw const LlmRuntimeSettingsException(
        'That model name has an unsupported character.',
      );
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(baseUrl.trim());
    } on FormatException {
      throw const LlmRuntimeSettingsException('That is not a valid address.');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw const LlmRuntimeSettingsException(
        'The address must start with http:// or https://.',
      );
    }
    if (!parsed.hasAuthority || parsed.host.isEmpty) {
      throw const LlmRuntimeSettingsException('The address must name a host.');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw const LlmRuntimeSettingsException(
        'The address must not embed credentials.',
      );
    }
    if (parsed.hasFragment || parsed.hasQuery) {
      throw const LlmRuntimeSettingsException(
        'The address must not carry a query or fragment.',
      );
    }
    if (!isPrivateOrLoopbackHost(parsed.host)) {
      throw const LlmRuntimeSettingsException(
        'A model runtime must be on this device or its private network.',
      );
    }

    if (maxTokens < 1 || maxTokens > maxTokenCeiling) {
      throw LlmRuntimeSettingsException(
        'Answer length must be between 1 and $maxTokenCeiling tokens.',
      );
    }
    if (temperature < 0 || temperature > 2) {
      throw const LlmRuntimeSettingsException(
        'Temperature must be between 0 and 2.',
      );
    }

    return LlmRuntimeSettings._(
      baseUrl: _normalizeBase(parsed),
      model: trimmedModel,
      maxTokens: maxTokens,
      temperature: temperature,
      systemPrompt: systemPrompt.trim(),
      think: think,
    );
  }

  /// Strip a trailing `/v1` and any trailing slashes, so the adapter can append
  /// whichever path its dialect needs without guessing what is already there.
  static Uri _normalizeBase(Uri parsed) {
    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/v1')) path = path.substring(0, path.length - 3);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return parsed.replace(path: path, query: null, fragment: null);
  }

  /// Loopback, RFC1918, CGNAT, link-local, or unique-local — plus `localhost`.
  ///
  /// A bare name that is not `localhost` cannot be shown to be private without
  /// resolving it, and resolution is not something a validator should do: the
  /// answer can change between the check and the connection. Refusing names is
  /// the honest bound, and an address is what a person running a local model has.
  static bool isPrivateOrLoopbackHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost') return true;

    final v4 = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(name);
    if (v4 != null) {
      final octets = [
        for (var group = 1; group <= 4; group++) int.parse(v4.group(group)!),
      ];
      if (octets.any((octet) => octet > 255)) return false;
      if (octets[0] == 127) return true;
      if (octets[0] == 10) return true;
      if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
      if (octets[0] == 192 && octets[1] == 168) return true;
      if (octets[0] == 169 && octets[1] == 254) return true;
      // CGNAT: 100.64.0.0/10, which is where several mesh VPNs put their peers.
      if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return true;
      return false;
    }

    // Uri strips the brackets from a literal IPv6 host.
    if (name.contains(':')) {
      if (name == '::1') return true;
      final head = name.split(':').first;
      if (head.isEmpty) return false;
      final leading = int.tryParse(head, radix: 16);
      if (leading == null) return false;
      // fc00::/7 unique-local, fe80::/10 link-local.
      if ((leading & 0xfe00) == 0xfc00) return true;
      if ((leading & 0xffc0) == 0xfe80) return true;
      return false;
    }

    return false;
  }

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl.toString(),
    'model': model,
    'maxTokens': maxTokens,
    'temperature': temperature,
    'systemPrompt': systemPrompt,
    'think': think,
  };

  /// Rebuild from storage, re-running every bound.
  ///
  /// Stored settings are re-parsed rather than trusted: a build that tightens a
  /// bound must not keep honouring a value written by an older one, and the file
  /// is on a device somebody owns.
  static LlmRuntimeSettings fromJson(Map<String, Object?> json) => parse(
    baseUrl: json['baseUrl'] as String? ?? '',
    model: json['model'] as String? ?? '',
    maxTokens: (json['maxTokens'] as num?)?.toInt() ?? defaultMaxTokens,
    temperature:
        (json['temperature'] as num?)?.toDouble() ?? defaultTemperature,
    systemPrompt: json['systemPrompt'] as String? ?? defaultSystemPrompt,
    think: json['think'] as bool? ?? false,
  );
}

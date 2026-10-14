import 'package:flutter/material.dart';

import '../domain/llm_runtime_settings.dart';
import 'runtime_controller.dart';

/// Where a person points this node at a model runtime, and sees whether it
/// answered.
///
/// The screen is built around one honest claim: nothing is advertised to the
/// fleet until a probe has proved it. So the status here is the same status the
/// brain is given, and a person who sees "ready" here can be certain a customer's
/// request would reach this device.
class RuntimePage extends StatefulWidget {
  const RuntimePage({required this.controller, super.key});

  final RuntimeController controller;

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends State<RuntimePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _maxTokens;
  bool _think = false;
  bool _advanced = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _baseUrl = TextEditingController(
      text: settings?.baseUrl.toString() ?? 'http://127.0.0.1:11434',
    );
    _model = TextEditingController(text: settings?.model ?? '');
    _maxTokens = TextEditingController(
      text: '${settings?.maxTokens ?? LlmRuntimeSettings.defaultMaxTokens}',
    );
    _think = settings?.think ?? false;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _maxTokens.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final LlmRuntimeSettings next;
    try {
      next = LlmRuntimeSettings.parse(
        baseUrl: _baseUrl.text,
        model: _model.text,
        maxTokens:
            int.tryParse(_maxTokens.text.trim()) ??
            LlmRuntimeSettings.defaultMaxTokens,
        think: _think,
      );
    } on LlmRuntimeSettingsException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    await widget.controller.apply(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final descriptor = controller.descriptor;
        final theme = Theme.of(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Runtime', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            descriptor.ready
                                ? Icons.memory
                                : Icons.memory_outlined,
                            size: 44,
                            color: descriptor.ready
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _title(controller),
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              key: const Key('runtime-status'),
                              _summary(controller),
                            ),
                          ),
                          if (descriptor.ready) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Advertising ${descriptor.generators.join(', ')} '
                              '· ${descriptor.models[descriptor.generators.first]!.join(', ')}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (controller.configured)
                                OutlinedButton.icon(
                                  key: const Key('runtime-test'),
                                  onPressed: controller.probing
                                      ? null
                                      : controller.probe,
                                  icon: const Icon(Icons.wifi_tethering),
                                  label: const Text('Test now'),
                                ),
                              if (controller.configured ||
                                  controller.failure != null)
                                TextButton.icon(
                                  key: const Key('runtime-disable'),
                                  onPressed: controller.disable,
                                  icon: const Icon(Icons.link_off),
                                  label: Text(
                                    controller.configured
                                        ? 'Stop serving models'
                                        : 'Retry clearing settings',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Model server',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'An OpenAI-compatible server on this device or its private '
                              'network — llama.cpp, Ollama, vLLM, or LM Studio. A runtime '
                              'reachable from the internet is not a local one, so those '
                              'addresses are refused.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              key: const Key('runtime-base-url'),
                              controller: _baseUrl,
                              autocorrect: false,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                helperText:
                                    'With or without a trailing /v1 — either works.',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('runtime-model'),
                              controller: _model,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                                hintText: 'qwen3:8b',
                                helperText:
                                    'Must be a model the server already serves. '
                                    'This node advertises nothing until it is.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _advanced = !_advanced),
                              icon: Icon(
                                _advanced
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                              label: Text(
                                _advanced ? 'Fewer options' : 'More options',
                              ),
                            ),
                            if (_advanced) ...[
                              const SizedBox(height: 8),
                              TextField(
                                key: const Key('runtime-max-tokens'),
                                controller: _maxTokens,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Longest answer, in tokens',
                                  helperText:
                                      'A ceiling, not a target. Locally, the only thing it spends is time.',
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                key: const Key('runtime-think'),
                                contentPadding: EdgeInsets.zero,
                                value: _think,
                                onChanged: (value) =>
                                    setState(() => _think = value),
                                title: const Text('Let the model reason first'),
                                subtitle: const Text(
                                  'Slower, and the reasoning is never shown. Turn it on only for '
                                  'a model that has to reason to be right.',
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                key: const Key('runtime-error'),
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              key: const Key('runtime-save'),
                              onPressed: controller.probing ? null : _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Save and test'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _title(RuntimeController controller) {
    if (controller.probing) return 'Checking the runtime';
    if (!controller.configured) return 'No model runtime';
    return controller.descriptor.ready ? 'Serving' : 'Runtime unavailable';
  }

  static String _summary(RuntimeController controller) {
    if (controller.probing) return 'Asking the model server what it serves.';
    if (!controller.configured) {
      if (controller.failure != null) return controller.failure!;
      return 'This node advertises no generators. Point it at a model server to serve '
          'text generation, or leave it as it is — a node with no runtime is still a '
          'fleet member and can still carry sensors.';
    }
    if (controller.descriptor.ready) {
      return 'The model server answered and serves the configured model. This node '
          'accepts authenticated text generation from its paired brain.';
    }
    return controller.failure ??
        'The model server did not answer. This node advertises nothing until it does.';
  }
}

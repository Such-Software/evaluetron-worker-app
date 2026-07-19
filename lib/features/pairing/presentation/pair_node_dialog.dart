import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/enrollment.dart';

class PairNodeDialog extends StatefulWidget {
  const PairNodeDialog({
    required this.onPair,
    this.scannerSupported,
    super.key,
  });

  final Future<bool> Function(EnrollmentDraft draft) onPair;
  final bool? scannerSupported;

  @override
  State<PairNodeDialog> createState() => _PairNodeDialogState();
}

class _PairNodeDialogState extends State<PairNodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _brain = TextEditingController();
  final _token = TextEditingController();
  bool _manual = false;
  bool _plainHttpAccepted = false;
  bool _submitting = false;
  String? _error;

  bool get _scannerSupported =>
      widget.scannerSupported ?? (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _link.dispose();
    _brain.dispose();
    _token.dispose();
    super.dispose();
  }

  EnrollmentDraft _parse() {
    return _manual
        ? EnrollmentDraft.fromFields(brain: _brain.text, token: _token.text)
        : EnrollmentDraft.parseUri(_link.text);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final draft = _parse();
      if (draft.usesPlainHttp && !_plainHttpAccepted) {
        setState(() {
          _error =
              'Plain HTTP exposes the one-time enrollment token. Confirm only on a trusted private network.';
        });
        return;
      }
      setState(() {
        _submitting = true;
        _error = null;
      });
      final paired = await widget.onPair(draft);
      if (paired && mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _EnrollmentScanner()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _manual = false;
      _link.text = result;
      _error = null;
    });
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair this node'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Paste the private enrollment link from Evaluetron Fleet. '
                  'The app exchanges it once—there are no shell or Termux steps.',
                ),
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  key: const Key('scan-enrollment'),
                  onPressed: _scannerSupported && !_submitting ? _scan : null,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Fleet QR'),
                ),
                if (!_scannerSupported)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Camera scanning is available on Android and iOS. Paste the link on desktop.',
                    ),
                  ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.link),
                      label: Text('Enrollment link'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.edit),
                      label: Text('Manual'),
                    ),
                  ],
                  selected: {_manual},
                  onSelectionChanged: (value) {
                    setState(() {
                      _manual = value.single;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 20),
                if (!_manual)
                  TextFormField(
                    key: const Key('enrollment-link-field'),
                    controller: _link,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Enrollment link',
                      hintText:
                          'evaluetron-worker://enroll?v=1&brain=https%3A%2F%2F…&token=eve_…',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enrollment link is required.'
                        : null,
                  )
                else ...[
                  TextFormField(
                    key: const Key('brain-address-field'),
                    controller: _brain,
                    autofocus: true,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Private brain address',
                      hintText: 'https://brain.example/private',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Brain address is required.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('enrollment-token-field'),
                    controller: _token,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'One-time enrollment token',
                      hintText: 'eve_…',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enrollment token is required.'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _plainHttpAccepted,
                  onChanged: (value) {
                    setState(() => _plainHttpAccepted = value ?? false);
                  },
                  title: const Text('Allow HTTP on my trusted private network'),
                  subtitle: const Text(
                    'Leave off for HTTPS. TLS certificates are never bypassed.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('pair-submit'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text(_submitting ? 'Pairing…' : 'Pair securely'),
        ),
      ],
    );
  }
}

class _EnrollmentScanner extends StatefulWidget {
  const _EnrollmentScanner();

  @override
  State<_EnrollmentScanner> createState() => _EnrollmentScannerState();
}

class _EnrollmentScannerState extends State<_EnrollmentScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    try {
      EnrollmentDraft.parseUri(value);
      _handled = true;
      _controller.stop();
      Navigator.pop(context, value);
    } on FormatException {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'That is not a valid Evaluetron Worker enrollment QR.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Fleet QR'),
        leading: IconButton(
          tooltip: 'Cancel scanning',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _detected,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable. Go back and paste the enrollment link instead.\n\n$error',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Point the camera at the private QR shown in Evaluetron Fleet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

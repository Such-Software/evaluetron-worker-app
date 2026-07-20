import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/enrollment.dart';
import '../domain/pairing_result.dart';

class PairNodeDialog extends StatefulWidget {
  const PairNodeDialog({
    required this.onPair,
    this.scannerSupported,
    super.key,
  });

  final Future<PairingResult> Function(EnrollmentDraft draft) onPair;
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
  String? _approvedPlainHttpOrigin;
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
      if (draft.usesPlainHttp &&
          _approvedPlainHttpOrigin != draft.brainBaseUrl.origin) {
        final approved = await _confirmPlainHttp(draft);
        if (!approved || !mounted) return;
        setState(() {
          _approvedPlainHttpOrigin = draft.brainBaseUrl.origin;
          _error = null;
        });
      }
      setState(() {
        _submitting = true;
        _error = null;
      });
      final result = await widget.onPair(draft);
      if (!mounted) return;
      if (result.paired) {
        Navigator.pop(context);
      } else {
        setState(() {
          _error = result.error ?? 'Enrollment did not complete.';
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Enrollment could not complete safely. Try a new Fleet QR.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmPlainHttp(EnrollmentDraft draft) async {
    final managed = draft.networkEnrollment != null;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              managed
                  ? 'Use the private tunnel route?'
                  : 'Use this trusted LAN?',
            ),
            content: Text(
              managed
                  ? 'Enrollment will continue over ${draft.brainBaseUrl.origin} after the managed tunnel connects.'
                  : 'The one-time credential will be sent to ${draft.brainBaseUrl.origin} without TLS. Continue only while this phone is on the trusted private network.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                key: const Key('confirm-private-http'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  managed ? 'Use private route' : 'Pair on trusted LAN',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _EnrollmentScanner()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _manual = false;
      _link.text = result;
      _approvedPlainHttpOrigin = null;
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
                  'Enrollment and credential storage complete within the app.',
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
                      _approvedPlainHttpOrigin = null;
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
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    formats: const [BarcodeFormat.qrCode],
    lensType: CameraLensType.normal,
    autoZoom: Platform.isAndroid,
  );
  bool _handled = false;
  bool _processing = false;
  String _guidance =
      'Point the camera at the private QR shown in Evaluetron Fleet.';
  bool _guidanceIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_handled || _processing) return;
    _processing = true;
    _handleDetection(capture);
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    final decoded = decodedBarcodeValues(capture);
    final value = validEnrollmentValue(capture);
    if (value == null) {
      if (decoded.isNotEmpty && mounted) {
        setState(() {
          _guidance =
              'QR detected, but it is not a valid Worker enrollment. Create a new Phone QR in Fleet.';
          _guidanceIsError = true;
        });
      }
      _processing = false;
      return;
    }
    _handled = true;
    await _controller.stop();
    if (mounted) Navigator.pop(context, value);
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
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _guidance,
                      textAlign: TextAlign.center,
                      style: _guidanceIsError
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            )
                          : null,
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

@visibleForTesting
List<String> decodedBarcodeValues(BarcodeCapture capture) {
  final values = <String>{};
  for (final barcode in capture.barcodes) {
    for (final candidate in [barcode.rawValue, barcode.displayValue]) {
      final normalized = candidate?.trim() ?? '';
      if (normalized.isNotEmpty) values.add(normalized);
    }
  }
  return values.toList(growable: false);
}

@visibleForTesting
String? validEnrollmentValue(BarcodeCapture capture) {
  for (final value in decodedBarcodeValues(capture)) {
    try {
      EnrollmentDraft.parseUri(value);
      return value;
    } on FormatException {
      continue;
    }
  }
  return null;
}

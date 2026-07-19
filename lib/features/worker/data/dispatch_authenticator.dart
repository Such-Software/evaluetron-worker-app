import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class DispatchAuthenticator {
  DispatchAuthenticator({
    required String nodeToken,
    DateTime Function()? clock,
    this.maxSkew = const Duration(seconds: 60),
    this.nonceTtl = const Duration(minutes: 5),
    this.nonceLimit = 4096,
  }) : _key = Uint8List.fromList(
         Hmac(
           sha256,
           utf8.encode(nodeToken),
         ).convert(utf8.encode('evaluetron-worker-dispatch-key-v1')).bytes,
       ),
       _clock = clock ?? DateTime.now;

  static const version = '1';
  static const scheme = 'hmac-sha256-v1';

  final Uint8List _key;
  final DateTime Function() _clock;
  final Duration maxSkew;
  final Duration nonceTtl;
  final int nonceLimit;
  final Map<String, DateTime> _nonces = {};

  bool verify({
    required Map<String, String> headers,
    required Uint8List body,
    String method = 'POST',
    String path = '/jobs',
  }) {
    final normalized = {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final suppliedVersion = normalized['x-evaluetron-dispatch-version'] ?? '';
    final timestamp = normalized['x-evaluetron-dispatch-timestamp'] ?? '';
    final nonce = normalized['x-evaluetron-dispatch-nonce'] ?? '';
    final signature = normalized['x-evaluetron-dispatch-signature'] ?? '';
    if (suppliedVersion != version ||
        !RegExp(r'^\d{10}$').hasMatch(timestamp) ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(nonce) ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(signature)) {
      return false;
    }
    final now = _clock().toUtc();
    final issued = DateTime.fromMillisecondsSinceEpoch(
      int.parse(timestamp) * 1000,
      isUtc: true,
    );
    if (now.difference(issued).abs() > maxSkew) return false;
    final payload = canonicalPayload(
      timestamp: timestamp,
      nonce: nonce,
      method: method,
      path: path,
      body: body,
    );
    final expected = _base64Url(
      Hmac(sha256, _key).convert(utf8.encode(payload)).bytes,
    );
    if (!_constantTimeEquals(signature, expected)) return false;
    _prune(now);
    if (_nonces.containsKey(nonce) || _nonces.length >= nonceLimit) {
      return false;
    }
    _nonces[nonce] = now;
    return true;
  }

  static String canonicalPayload({
    required String timestamp,
    required String nonce,
    required String method,
    required String path,
    required Uint8List body,
  }) {
    final bodyHash = sha256.convert(body).toString();
    return [
      'v$version',
      timestamp,
      nonce,
      method.toUpperCase(),
      path,
      bodyHash,
    ].join('\n');
  }

  void _prune(DateTime now) {
    final oldest = now.subtract(nonceTtl);
    _nonces.removeWhere((_, seenAt) => seenAt.isBefore(oldest));
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

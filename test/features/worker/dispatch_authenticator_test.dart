import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:evaluetron_worker_app/features/worker/data/dispatch_authenticator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'evn_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final body = Uint8List.fromList(
    utf8.encode('{"generator":"llm","params":{"text":"hi"}}'),
  );
  const timestamp = '1750000000';
  const nonce = 'AQIDBAUGBwgJCgsMDQ4PEA';
  final clock = DateTime.fromMillisecondsSinceEpoch(1750000000000, isUtc: true);
  const headers = {
    'x-evaluetron-dispatch-version': '1',
    'x-evaluetron-dispatch-timestamp': timestamp,
    'x-evaluetron-dispatch-nonce': nonce,
    'x-evaluetron-dispatch-signature':
        'ATGWJFsHrybfmBq1T3lxuyN9LtsHzNqznRN85llRuTQ',
  };

  test('matches the cross-runtime signing vector', () {
    final key = Hmac(
      sha256,
      utf8.encode(token),
    ).convert(utf8.encode('evaluetron-worker-dispatch-key-v1')).toString();
    expect(
      key,
      'c45ed7bbc4ac1bfb1fd644bd5a81608970909479b1aabf220583d3bc58299650',
    );
    expect(
      DispatchAuthenticator(
        nodeToken: token,
        clock: () => clock,
      ).verify(headers: headers, body: body),
      isTrue,
    );
  });

  test('rejects replay, modified payloads, and stale requests', () {
    final authenticator = DispatchAuthenticator(
      nodeToken: token,
      clock: () => clock,
    );
    expect(authenticator.verify(headers: headers, body: body), isTrue);
    expect(authenticator.verify(headers: headers, body: body), isFalse);

    final newAuthenticator = DispatchAuthenticator(
      nodeToken: token,
      clock: () => clock,
    );
    expect(
      newAuthenticator.verify(
        headers: headers,
        body: Uint8List.fromList([...body, 0x20]),
      ),
      isFalse,
    );
    expect(
      DispatchAuthenticator(
        nodeToken: token,
        clock: () => clock.add(const Duration(seconds: 61)),
      ).verify(headers: headers, body: body),
      isFalse,
    );
  });
}

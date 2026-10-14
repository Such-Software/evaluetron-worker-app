import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:evaluetron_worker_app/features/pairing/domain/node_registration.dart';
import 'package:evaluetron_worker_app/features/worker/data/fleet_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> oversized({
    required bool declared,
    required bool multibyte,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    final bytes = multibyte
        ? utf8.encode('é' * 40000)
        : List<int>.filled(70000, 120);
    server.listen((request) async {
      await request.drain<void>();
      if (declared) request.response.contentLength = bytes.length;
      request.response.add(bytes);
      try {
        await request.response.close();
      } on Object {
        /* Client refuses the oversized body. */
      }
    });
    final random = Random.secure();
    final registration = NodeRegistration(
      brainBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      nodeId: 'test-node',
      credentialId: 'test-credential',
      nodeName: 'test-worker',
      nodeToken: base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ),
      roles: const ['worker'],
    );
    await expectLater(
      HttpFleetClient(client: client).heartbeat(registration),
      throwsA(
        isA<FleetException>().having(
          (e) => e.message.contains('oversized'),
          'size refusal',
          isTrue,
        ),
      ),
    );
  }

  test(
    'refuses an oversized declared response',
    () => oversized(declared: true, multibyte: false),
  );
  test(
    'bounds a chunked response without trusting content length',
    () => oversized(declared: false, multibyte: false),
  );
  test(
    'limits encoded bytes rather than decoded characters',
    () => oversized(declared: false, multibyte: true),
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:evaluetron_worker_app/features/pairing/data/enrollment_client.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exchanges the one-time token without placing it in the body', () async {
    const enrollmentToken = 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/internal/nodes/enroll');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $enrollmentToken',
      );
      expect(await utf8.decoder.bind(request).join(), isEmpty);
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ok': true,
            'node': {
              'nodeId': 'node-1',
              'name': 'phone-s22',
              'roles': ['worker', 'sensor'],
            },
            'credentialId': 'credential-1',
            'nodeToken': 'evn_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
          }),
        );
      await request.response.close();
    });

    final registration = await HttpEnrollmentClient().enroll(
      EnrollmentDraft.fromFields(
        brain: 'http://127.0.0.1:${server.port}',
        token: enrollmentToken,
      ),
    );
    await handled;

    expect(registration.nodeName, 'phone-s22');
    expect(registration.nodeToken, startsWith('evn_'));
    expect(registration.roles, ['worker', 'sensor']);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:evaluetron_worker_app/features/network/data/network_enrollment_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the compatible Brain network enrollment contract', () async {
    const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN123456';
    const publicKey =
        '-----BEGIN NEBULA X25519 PUBLIC KEY-----\npublic\n-----END NEBULA X25519 PUBLIC KEY-----';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final handled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/enroll/nebula');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $token',
      );
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'publicKey': publicKey,
      });
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ok': true,
            'enrollment': {
              'version': '1.10.3',
              'ca':
                  '-----BEGIN NEBULA CERTIFICATE-----\nca\n-----END NEBULA CERTIFICATE-----',
              'certificate':
                  '-----BEGIN NEBULA CERTIFICATE-----\nhost\n-----END NEBULA CERTIFICATE-----',
              'config': 'pki:\n  ca: /managed/ca.crt\n',
              'managed': {
                'meshName': 'evaluetron',
                'endpoint': 'vpn.example:4242',
                'brainIp': '192.168.100.1/24',
              },
            },
          }),
        );
      await request.response.close();
    });

    final profile = await HttpManagedNetworkEnrollmentClient().enroll(
      brainBaseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      oneTimeToken: token,
      publicKeyPem: publicKey,
    );
    await handled;

    expect(profile.metadata.meshName, 'evaluetron');
    expect(profile.routePolicy.routes, ['192.168.100.1/32']);
  });

  test('rejects public cleartext enrollment before network access', () async {
    expect(
      () => HttpManagedNetworkEnrollmentClient().enroll(
        brainBaseUrl: Uri.parse('http://8.8.8.8'),
        oneTimeToken: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN123456',
        publicKeyPem:
            '-----BEGIN NEBULA X25519 PUBLIC KEY-----\npublic\n-----END NEBULA X25519 PUBLIC KEY-----',
      ),
      throwsA(isA<Exception>()),
    );
  });
}

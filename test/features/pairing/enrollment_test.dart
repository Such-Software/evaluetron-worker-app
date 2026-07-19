import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';

  group('EnrollmentDraft', () {
    test('parses the canonical versioned enrollment URI', () {
      final uri = Uri(
        scheme: 'evaluetron-worker',
        host: 'enroll',
        queryParameters: {
          'v': '1',
          'brain': 'https://fleet.example.test:8082',
          'token': token,
        },
      );

      final draft = EnrollmentDraft.parseUri(uri.toString());

      expect(draft.brainBaseUrl, Uri.parse('https://fleet.example.test:8082'));
      expect(draft.enrollmentToken, token);
      expect(draft.usesPlainHttp, isFalse);
    });

    test('allows cleartext only on literal private or loopback addresses', () {
      for (final host in [
        '127.0.0.1',
        '10.20.30.40',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.20',
        '169.254.2.3',
        '[::1]',
        '[fd00::1]',
        '[fe80::1]',
      ]) {
        expect(
          () => EnrollmentDraft.fromFields(
            brain: 'http://$host:8082',
            token: token,
          ),
          returnsNormally,
          reason: host,
        );
      }
    });

    test('rejects public cleartext, hostnames, and adjacent public ranges', () {
      for (final host in [
        'example.test',
        '8.8.8.8',
        '172.15.255.255',
        '172.32.0.1',
        '192.167.1.2',
      ]) {
        expect(
          () => EnrollmentDraft.fromFields(
            brain: 'http://$host:8082',
            token: token,
          ),
          throwsFormatException,
          reason: host,
        );
      }
    });

    test('rejects missing or unknown protocol versions', () {
      for (final version in ['', '2']) {
        final uri = Uri(
          scheme: 'evaluetron-worker',
          host: 'enroll',
          queryParameters: {
            if (version.isNotEmpty) 'v': version,
            'brain': 'https://fleet.example.test',
            'token': token,
          },
        );
        expect(
          () => EnrollmentDraft.parseUri(uri.toString()),
          throwsFormatException,
        );
      }
    });

    test('rejects wrong scheme, user info, fragments, and malformed tokens', () {
      expect(
        () => EnrollmentDraft.parseUri(
          'evaluetron://enroll?v=1&brain=https%3A%2F%2Ffleet.example&token=$token',
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.fromFields(
          brain: 'https://operator:secret@fleet.example',
          token: token,
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.fromFields(
          brain: 'https://fleet.example/#fragment',
          token: token,
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.fromFields(
          brain: 'https://fleet.example/unexpected-path',
          token: token,
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.parseUri(
          'evaluetron-worker://enroll/extra?v=1'
          '&brain=https%3A%2F%2Ffleet.example&token=$token',
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.parseUri(
          'evaluetron-worker://enroll?v=1'
          '&brain=https%3A%2F%2Ffleet.example&token=$token&extra=nope',
        ),
        throwsFormatException,
      );
      expect(
        () => EnrollmentDraft.fromFields(
          brain: 'https://fleet.example',
          token: 'evn_wrong-kind',
        ),
        throwsFormatException,
      );
    });
  });
}

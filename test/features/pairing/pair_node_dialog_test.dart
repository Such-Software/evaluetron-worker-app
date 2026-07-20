import 'package:evaluetron_worker_app/features/pairing/domain/enrollment.dart';
import 'package:evaluetron_worker_app/features/pairing/domain/pairing_result.dart';
import 'package:evaluetron_worker_app/features/pairing/presentation/pair_node_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'eve_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';

void main() {
  testWidgets('private HTTP pairing requires a visible scoped confirmation', (
    tester,
  ) async {
    EnrollmentDraft? submitted;
    await tester.pumpWidget(
      _TestApp(
        onPair: (draft) async {
          submitted = draft;
          return const PairingResult.success();
        },
      ),
    );

    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('enrollment-link-field')),
      _enrollment('http://192.168.88.50:8082'),
    );
    await tester.tap(find.byKey(const Key('pair-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Use this trusted LAN?'), findsOneWidget);
    expect(find.textContaining('http://192.168.88.50:8082'), findsOneWidget);
    expect(submitted, isNull);

    await tester.tap(find.byKey(const Key('confirm-private-http')));
    await tester.pumpAndSettle();

    expect(submitted?.brainBaseUrl, Uri.parse('http://192.168.88.50:8082'));
    expect(find.text('Pair this node'), findsNothing);
  });

  testWidgets('enrollment failure remains visible inside the pairing dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        onPair: (_) async =>
            const PairingResult.failure('Enrollment expired. Create a new QR.'),
      ),
    );

    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('enrollment-link-field')),
      _enrollment('https://fleet.example'),
    );
    await tester.tap(find.byKey(const Key('pair-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enrollment expired. Create a new QR.'), findsOneWidget);
    expect(find.text('Pair this node'), findsOneWidget);
  });
}

String _enrollment(String brain) => Uri(
  scheme: 'evaluetron-worker',
  host: 'enroll',
  queryParameters: {'v': '1', 'brain': brain, 'token': _token},
).toString();

class _TestApp extends StatelessWidget {
  const _TestApp({required this.onPair});

  final Future<PairingResult> Function(EnrollmentDraft draft) onPair;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: const Key('open-dialog'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  PairNodeDialog(onPair: onPair, scannerSupported: false),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }
}

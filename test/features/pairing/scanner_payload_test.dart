import 'package:evaluetron_worker_app/features/pairing/presentation/pair_node_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  const enrollment =
      'evaluetron-worker://enroll?v=1&brain=http%3A%2F%2F192.168.88.50%3A8082&token=eve_abcdefghijklmnopqrstuvwxyzABCDEF';

  test('accepts a valid enrollment from any decoded barcode', () {
    const capture = BarcodeCapture(
      barcodes: [
        Barcode(rawValue: 'unrelated'),
        Barcode(rawValue: enrollment),
      ],
    );

    expect(validEnrollmentValue(capture), enrollment);
  });

  test('falls back to display value and rejects placeholder enrollments', () {
    const validCapture = BarcodeCapture(
      barcodes: [Barcode(displayValue: enrollment)],
    );
    const placeholderCapture = BarcodeCapture(
      barcodes: [
        Barcode(
          rawValue:
              'evaluetron-worker://enroll?v=1&brain=http%3A%2F%2FBRAIN_PRIVATE_IP%3A8082&token=eve_abcdefghijklmnopqrstuvwxyzABCDEF',
        ),
      ],
    );

    expect(validEnrollmentValue(validCapture), enrollment);
    expect(validEnrollmentValue(placeholderCapture), isNull);
  });
}

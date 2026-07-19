import 'dart:io';

import '../../network/domain/network_enrollment.dart';

class EnrollmentDraft {
  const EnrollmentDraft({
    required this.brainBaseUrl,
    required this.enrollmentToken,
    this.networkEnrollment,
  });

  /// Fleet listener base used only after any managed tunnel is connected.
  final Uri brainBaseUrl;
  final String enrollmentToken;
  final NetworkEnrollmentDraft? networkEnrollment;

  bool get usesPlainHttp => brainBaseUrl.scheme == 'http';

  static EnrollmentDraft parseUri(String input) {
    final uri = Uri.tryParse(input.trim());
    final parameters = uri?.queryParametersAll;
    final version = uri?.queryParameters['v'];
    final allowedKeys = version == '2'
        ? {'v', 'brain', 'fleet', 'token', 'networkToken'}
        : {'v', 'brain', 'token'};
    if (uri == null ||
        uri.scheme != 'evaluetron-worker' ||
        uri.host != 'enroll' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        !{'1', '2'}.contains(version) ||
        uri.queryParameters['brain'] == null ||
        uri.queryParameters['token'] == null ||
        (version == '2' &&
            (uri.queryParameters['fleet'] == null ||
                uri.queryParameters['networkToken'] == null)) ||
        parameters == null ||
        parameters.keys.any((key) => !allowedKeys.contains(key)) ||
        parameters.values.any((values) => values.length != 1) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Use a supported evaluetron-worker://enroll link from Fleet.',
      );
    }
    if (version == '2') {
      final publicBrain = _parseBaseUrl(
        uri.queryParameters['brain']!,
        allowPrivateHttp: false,
        label: 'Public brain address',
      );
      final draft = fromFields(
        brain: uri.queryParameters['fleet']!,
        token: uri.queryParameters['token']!,
      );
      final networkToken = uri.queryParameters['networkToken']!.trim();
      if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(networkToken)) {
        throw const FormatException(
          'Managed network token is invalid or incomplete.',
        );
      }
      return EnrollmentDraft(
        brainBaseUrl: draft.brainBaseUrl,
        enrollmentToken: draft.enrollmentToken,
        networkEnrollment: NetworkEnrollmentDraft(
          brainBaseUrl: publicBrain,
          oneTimeToken: networkToken,
        ),
      );
    }
    return fromFields(
      brain: uri.queryParameters['brain']!,
      token: uri.queryParameters['token']!,
    );
  }

  static EnrollmentDraft fromFields({
    required String brain,
    required String token,
  }) {
    final brainUri = _parseBaseUrl(
      brain,
      allowPrivateHttp: true,
      label: 'Brain address',
    );
    final normalizedToken = token.trim();
    if (!RegExp(r'^eve_[A-Za-z0-9_-]{32,}$').hasMatch(normalizedToken)) {
      throw const FormatException('Enrollment token is invalid or incomplete.');
    }
    return EnrollmentDraft(
      brainBaseUrl: brainUri,
      enrollmentToken: normalizedToken,
    );
  }

  static Uri _parseBaseUrl(
    String input, {
    required bool allowPrivateHttp,
    required String label,
  }) {
    final brainUri = Uri.tryParse(input.trim());
    if (brainUri == null ||
        !brainUri.hasAuthority ||
        !{'https', 'http'}.contains(brainUri.scheme) ||
        brainUri.hasQuery ||
        brainUri.hasFragment ||
        (brainUri.path.isNotEmpty && brainUri.path != '/') ||
        brainUri.userInfo.isNotEmpty) {
      throw FormatException(
        '$label must be an HTTP(S) origin without credentials.',
      );
    }
    if (brainUri.scheme == 'http' &&
        (!allowPrivateHttp || !_isPrivateOrLoopback(brainUri.host))) {
      throw FormatException(
        allowPrivateHttp
            ? 'Plain HTTP is allowed only for a private, link-local, or loopback IP.'
            : '$label must use HTTPS.',
      );
    }
    return brainUri.replace(
      path: brainUri.path.replaceFirst(RegExp(r'/$'), ''),
    );
  }

  static bool _isPrivateOrLoopback(String host) {
    if (host == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return address.isLoopback ||
        (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }
}

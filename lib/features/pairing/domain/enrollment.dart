import 'dart:io';

class EnrollmentDraft {
  const EnrollmentDraft({
    required this.brainBaseUrl,
    required this.enrollmentToken,
  });

  final Uri brainBaseUrl;
  final String enrollmentToken;

  bool get usesPlainHttp => brainBaseUrl.scheme == 'http';

  static EnrollmentDraft parseUri(String input) {
    final uri = Uri.tryParse(input.trim());
    final parameters = uri?.queryParametersAll;
    if (uri == null ||
        uri.scheme != 'evaluetron-worker' ||
        uri.host != 'enroll' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        uri.queryParameters['v'] != '1' ||
        uri.queryParameters['brain'] == null ||
        uri.queryParameters['token'] == null ||
        parameters == null ||
        parameters.keys.any((key) => !{'v', 'brain', 'token'}.contains(key)) ||
        parameters.values.any((values) => values.length != 1) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Use a version 1 evaluetron-worker://enroll link from Fleet.',
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
    final brainUri = Uri.tryParse(brain.trim());
    if (brainUri == null ||
        !brainUri.hasAuthority ||
        !{'https', 'http'}.contains(brainUri.scheme) ||
        brainUri.hasQuery ||
        brainUri.hasFragment ||
        (brainUri.path.isNotEmpty && brainUri.path != '/') ||
        brainUri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Brain address must be an HTTP(S) address without credentials.',
      );
    }
    final normalizedToken = token.trim();
    if (!RegExp(r'^eve_[A-Za-z0-9_-]{32,}$').hasMatch(normalizedToken)) {
      throw const FormatException('Enrollment token is invalid or incomplete.');
    }
    if (brainUri.scheme == 'http' && !_isPrivateOrLoopback(brainUri.host)) {
      throw const FormatException(
        'Plain HTTP is allowed only for a private, link-local, or loopback IP.',
      );
    }
    return EnrollmentDraft(
      brainBaseUrl: brainUri.replace(
        path: brainUri.path.replaceFirst(RegExp(r'/$'), ''),
      ),
      enrollmentToken: normalizedToken,
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

enum DistributionTrack {
  fullNode('Full node', 'Sideloaded Android or Linux'),
  storeSafe('Store-safe', 'Apple App Store or Google Play');

  const DistributionTrack(this.label, this.description);

  final String label;
  final String description;
}

class CapabilityPolicy {
  const CapabilityPolicy({
    required this.track,
    required this.allowed,
    required this.restrictions,
  });

  final DistributionTrack track;
  final List<String> allowed;
  final List<String> restrictions;

  static const fullNode = CapabilityPolicy(
    track: DistributionTrack.fullNode,
    allowed: [
      'User-started worker sessions',
      'Bundled or operator-installed native model runtimes',
      'Foreground sensor participation with explicit permission',
    ],
    restrictions: [
      'A model runtime is served over HTTP; in-process inference is not linked yet.',
      'Background survival depends on the operating system.',
      'Models and runtime artifacts must be signed and verified.',
    ],
  );

  static const storeSafe = CapabilityPolicy(
    track: DistributionTrack.storeSafe,
    allowed: [
      'User-visible, user-started foreground inference',
      'Models shipped in the app or handled as approved data assets',
      'Immediate stop and clear local status',
    ],
    restrictions: [
      'No downloaded executable code or arbitrary plug-ins.',
      'No invisible, indefinite background compute.',
      'Store declarations and OS foreground-service rules apply.',
    ],
  );
}

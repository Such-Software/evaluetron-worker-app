class PairingResult {
  const PairingResult.success() : paired = true, error = null;

  const PairingResult.failure(this.error) : paired = false;

  final bool paired;
  final String? error;
}

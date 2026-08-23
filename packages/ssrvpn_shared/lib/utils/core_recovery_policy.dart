class CoreRecoveryPolicy {
  CoreRecoveryPolicy({required this.maxAttempts})
      : assert(maxAttempts >= 0, 'maxAttempts must not be negative');

  final int maxAttempts;
  int _attempts = 0;

  int get attempts => _attempts;

  bool tryAcquire() {
    if (_attempts >= maxAttempts) return false;
    _attempts++;
    return true;
  }

  void recordUnhealthy() {
    _attempts++;
  }

  bool recordHealthy([DateTime? now]) {
    final hadAttempts = _attempts > 0;
    reset();
    return hadAttempts;
  }

  void reset() => _attempts = 0;
}

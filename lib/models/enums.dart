/// Device operational states
enum DeviceState {
  idle('IDLE'),
  monitoring('MONITORING'),
  fallDetected('FALL_DETECTED'),
  alertSent('ALERT_SENT');

  final String label;
  const DeviceState(this.label);
}

/// Fall event resolution status
enum FallStatus {
  confirmed('CONFIRMED'),
  falseAlarm('FALSE ALARM'),
  pending('PENDING');

  final String label;
  const FallStatus(this.label);
}

/// Connection status for device
enum ConnectionStatus { connected, disconnected, connecting, error }

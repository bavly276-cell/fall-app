class ActivityClassifierService {
  ActivityClassifierService._();

  static String classify({
    required double accelMag,
    required double heartRate,
    double? gyroMag,
  }) {
    final motion = (accelMag - 1.0).abs();
    final gyro = (gyroMag ?? 0.0).abs();

    if (motion < 0.05 && gyro < 0.08 && heartRate > 0 && heartRate < 80) {
      return 'sleeping';
    }

    if (motion < 0.12 && gyro < 0.2) {
      return 'sitting';
    }

    if (motion < 0.55 && heartRate < 135) {
      return 'walking';
    }

    return 'running';
  }
}

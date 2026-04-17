class HealthRulesService {
  HealthRulesService._();

  static const double lowHeartRate = 45.0;
  static const double highHeartRate = 140.0;
  static const double lowSpo2 = 92.0;

  static bool isHeartRateAbnormal(double heartRate) {
    if (heartRate <= 0) return false;
    return heartRate < lowHeartRate || heartRate > highHeartRate;
  }

  static bool isSpo2Abnormal(double spo2) {
    if (spo2 <= 0) return false;
    return spo2 < lowSpo2;
  }

  static bool isAbnormalVitals({
    required double heartRate,
    required double spo2,
  }) {
    return isHeartRateAbnormal(heartRate) || isSpo2Abnormal(spo2);
  }

  static String buildAlertReason({
    required bool fallDetected,
    required bool abnormalHealth,
    required bool geofenceBreached,
    required double heartRate,
    required double spo2,
  }) {
    if (fallDetected) return 'Fall detected';
    if (geofenceBreached) return 'Child left safe area';

    if (abnormalHealth) {
      if (isHeartRateAbnormal(heartRate) && isSpo2Abnormal(spo2)) {
        return 'Abnormal HR and SpO2';
      }
      if (isHeartRateAbnormal(heartRate)) {
        return 'Abnormal heart rate';
      }
      return 'Low SpO2 detected';
    }

    return 'All normal';
  }
}

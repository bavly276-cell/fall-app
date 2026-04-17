import 'package:cloud_firestore/cloud_firestore.dart';

class SafetyUpdate {
  final String childDeviceId;
  final double? latitude;
  final double? longitude;
  final String mapsUrl;
  final double heartRate;
  final double spo2;
  final double accelMag;
  final double? gyroMag;
  final bool fallDetected;
  final bool abnormalHealth;
  final bool geofenceBreached;
  final String alertLevel;
  final String alertReason;
  final String activity;
  final String triggerType;
  final DateTime timestamp;

  const SafetyUpdate({
    required this.childDeviceId,
    required this.latitude,
    required this.longitude,
    required this.mapsUrl,
    required this.heartRate,
    required this.spo2,
    required this.accelMag,
    required this.gyroMag,
    required this.fallDetected,
    required this.abnormalHealth,
    required this.geofenceBreached,
    required this.alertLevel,
    required this.alertReason,
    required this.activity,
    required this.triggerType,
    required this.timestamp,
  });

  bool get isDanger => alertLevel.toLowerCase() == 'danger';

  Map<String, dynamic> toMap({bool useServerTimestamp = false}) {
    return {
      'childDeviceId': childDeviceId,
      'latitude': latitude,
      'longitude': longitude,
      'mapsUrl': mapsUrl,
      'heartRate': heartRate,
      'spo2': spo2,
      'accelMag': accelMag,
      'gyroMag': gyroMag,
      'fallDetected': fallDetected,
      'abnormalHealth': abnormalHealth,
      'geofenceBreached': geofenceBreached,
      'alertLevel': alertLevel,
      'alertReason': alertReason,
      'activity': activity,
      'triggerType': triggerType,
      'timestamp': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(timestamp),
    };
  }

  factory SafetyUpdate.fromMap(Map<String, dynamic> map) {
    final rawTime = map['timestamp'];
    DateTime parsed;
    if (rawTime is Timestamp) {
      parsed = rawTime.toDate();
    } else if (rawTime is DateTime) {
      parsed = rawTime;
    } else {
      parsed = DateTime.now();
    }

    return SafetyUpdate(
      childDeviceId: map['childDeviceId'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      mapsUrl: map['mapsUrl'] as String? ?? '',
      heartRate: (map['heartRate'] as num?)?.toDouble() ?? 0.0,
      spo2: (map['spo2'] as num?)?.toDouble() ?? 0.0,
      accelMag: (map['accelMag'] as num?)?.toDouble() ?? 0.0,
      gyroMag: (map['gyroMag'] as num?)?.toDouble(),
      fallDetected: map['fallDetected'] as bool? ?? false,
      abnormalHealth: map['abnormalHealth'] as bool? ?? false,
      geofenceBreached: map['geofenceBreached'] as bool? ?? false,
      alertLevel: map['alertLevel'] as String? ?? 'normal',
      alertReason: map['alertReason'] as String? ?? 'All normal',
      activity: map['activity'] as String? ?? 'unknown',
      triggerType: map['triggerType'] as String? ?? 'periodic',
      timestamp: parsed,
    );
  }
}

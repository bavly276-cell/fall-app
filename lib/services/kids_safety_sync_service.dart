import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/safety_update.dart';
import 'activity_classifier_service.dart';
import 'firestore_service.dart';
import 'health_rules_service.dart';
import 'location_service.dart';

class KidsSafetySyncService {
  KidsSafetySyncService._();

  static const Duration periodicInterval = Duration(minutes: 5);

  static SafetyUpdate buildUpdate({
    required String childDeviceId,
    required String triggerType,
    required double heartRate,
    required double spo2,
    required double accelMag,
    required double? gyroMag,
    required bool fallDetected,
    required bool geofenceBreached,
    required Position? position,
  }) {
    final abnormalHealth = HealthRulesService.isAbnormalVitals(
      heartRate: heartRate,
      spo2: spo2,
    );

    final reason = HealthRulesService.buildAlertReason(
      fallDetected: fallDetected,
      abnormalHealth: abnormalHealth,
      geofenceBreached: geofenceBreached,
      heartRate: heartRate,
      spo2: spo2,
    );

    final danger = fallDetected || abnormalHealth || geofenceBreached;

    final activity = ActivityClassifierService.classify(
      accelMag: accelMag,
      gyroMag: gyroMag,
      heartRate: heartRate,
    );

    final mapsUrl =
        LocationService.getMapsUrl(position) ??
        (position == null
            ? ''
            : 'https://maps.google.com/?q=${position.latitude},${position.longitude}');

    return SafetyUpdate(
      childDeviceId: childDeviceId,
      latitude: position?.latitude,
      longitude: position?.longitude,
      mapsUrl: mapsUrl,
      heartRate: heartRate,
      spo2: spo2,
      accelMag: accelMag,
      gyroMag: gyroMag,
      fallDetected: fallDetected,
      abnormalHealth: abnormalHealth,
      geofenceBreached: geofenceBreached,
      alertLevel: danger ? 'danger' : 'normal',
      alertReason: reason,
      activity: activity,
      triggerType: triggerType,
      timestamp: DateTime.now(),
    );
  }

  static bool isGeofenceBreached({
    required Position? position,
    required double? safeLat,
    required double? safeLon,
    required double safeRadiusMeters,
  }) {
    if (position == null || safeLat == null || safeLon == null) return false;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      safeLat,
      safeLon,
    );

    return distance > max(10.0, safeRadiusMeters);
  }

  static Future<void> pushUpdate({
    required SafetyUpdate update,
    required String parentDeviceId,
    required bool immediate,
  }) async {
    await FirestoreService.saveSafetySnapshot(update: update);
    await FirestoreService.saveSafetyUpdate(update: update);

    if (immediate && parentDeviceId.trim().isNotEmpty) {
      await FirestoreService.queueParentPushAlert(
        parentDeviceId: parentDeviceId,
        update: update,
      );
    }
  }
}

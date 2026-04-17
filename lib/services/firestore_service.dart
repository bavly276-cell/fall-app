import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/fall_event.dart';
import '../models/safety_update.dart';

/// Service for syncing fall events and user profile to Cloud Firestore.
///
/// Firestore structure:
///   users/{deviceId}/
///     profile: { patientName, caregiverName, caregiverPhone, ... }
///     fall_events/{eventId}: { time, heartRate, tiltAngle, accelMag, status, gps }
class FirestoreService {
  static FirebaseFirestore get _db {
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase has not been initialized. Call Firebase.initializeApp() first.',
      );
    }
    return FirebaseFirestore.instance;
  }

  static void _logFirestoreError(String scope, Object error) {
    final msg = error.toString();
    final isOfflineUnavailable =
        msg.contains('[cloud_firestore/unavailable]') &&
        msg.toLowerCase().contains('offline');

    if (kIsWeb && isOfflineUnavailable) {
      return;
    }

    debugPrint('Firestore $scope error: $error');
  }

  static String _deviceId = 'default_device';

  /// Set the device/user identifier (call once after auth or device setup).
  static void setDeviceId(String id) {
    _deviceId = id;
  }

  static String get deviceId => _deviceId;

  // ── References ──

  static DocumentReference get _userDoc =>
      _db.collection('users').doc(_deviceId);

  static CollectionReference get _eventsCol =>
      _userDoc.collection('fall_events');

  static CollectionReference get _chatCol =>
      _userDoc.collection('chat_messages');

  static CollectionReference get _kidsLocationsCol =>
      _userDoc.collection('kids_locations'); // NEW kids mode GPS

  static CollectionReference get _safetyUpdatesCol =>
      _userDoc.collection('safety_updates');

  static CollectionReference get _safetyAlertsCol =>
      _userDoc.collection('safety_alerts');

  // ── Fall Events ──

  /// Save a fall event to Firestore.
  static Future<void> saveFallEvent(FallEvent event) async {
    try {
      await _eventsCol.add({
        'time': Timestamp.fromDate(event.time),
        'heartRate': event.heartRate,
        'tiltAngle': event.tiltAngle,
        'accelMag': event.accelMag,
        'status': event.status,
        'gpsLocation': event.gpsLocation,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logFirestoreError('saveFallEvent', e);
    }
  }

  /// Load all fall events from Firestore, ordered by time descending.
  static Future<List<FallEvent>> loadFallHistory() async {
    try {
      final snap = await _eventsCol
          .orderBy('time', descending: true)
          .limit(200)
          .get();

      return snap.docs.map((doc) {
        final d = doc.data() as Map<String, dynamic>;
        return FallEvent(
          time: (d['time'] as Timestamp).toDate(),
          heartRate: (d['heartRate'] as num).toDouble(),
          tiltAngle: (d['tiltAngle'] as num).toDouble(),
          accelMag: (d['accelMag'] as num?)?.toDouble() ?? 0.0,
          status: d['status'] as String? ?? 'CONFIRMED',
          gpsLocation: d['gpsLocation'] as String?,
        );
      }).toList();
    } catch (e) {
      _logFirestoreError('loadFallHistory', e);
      return [];
    }
  }

  /// Stream fall events in real-time.
  static Stream<List<FallEvent>> fallEventsStream() {
    return _eventsCol
        .orderBy('time', descending: true)
        .limit(200)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return FallEvent(
              time: (d['time'] as Timestamp).toDate(),
              heartRate: (d['heartRate'] as num).toDouble(),
              tiltAngle: (d['tiltAngle'] as num).toDouble(),
              accelMag: (d['accelMag'] as num?)?.toDouble() ?? 0.0,
              status: d['status'] as String? ?? 'CONFIRMED',
              gpsLocation: d['gpsLocation'] as String?,
            );
          }).toList(),
        );
  }

  /// Delete all fall events for this device.
  static Future<void> clearFallHistory() async {
    try {
      final snap = await _eventsCol.get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      _logFirestoreError('clearFallHistory', e);
    }
  }

  // ── User Profile ──

  /// Save user profile to Firestore.
  static Future<void> saveProfile({
    required String patientName,
    String? patientPhone,
    String? patientEmail,
    required String caregiverName,
    required String caregiverPhone,
    String? caregiverEmail,
    bool smsAlertEnabled = true,
    bool autoSmsOnConfirm = true,
  }) async {
    try {
      await _userDoc.set({
        'patientName': patientName,
        'patientPhone': patientPhone,
        'patientEmail': patientEmail,
        'caregiverName': caregiverName,
        'caregiverPhone': caregiverPhone,
        'caregiverEmail': caregiverEmail,
        'smsAlertEnabled': smsAlertEnabled,
        'autoSmsOnConfirm': autoSmsOnConfirm,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logFirestoreError('saveProfile', e);
    }
  }

  /// Save FCM token for this device/user.
  static Future<void> saveMessagingToken(String token) async {
    try {
      await _userDoc.set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logFirestoreError('saveMessagingToken', e);
    }
  }

  /// Save role + child/parent pairing configuration.
  static Future<void> saveMonitoringConfig({
    required String monitoringRole,
    String? linkedParentDeviceId,
    String? linkedChildDeviceId,
    double? safeZoneLat,
    double? safeZoneLon,
    double? safeZoneRadius,
  }) async {
    try {
      await _userDoc.set({
        'monitoringRole': monitoringRole,
        'linkedParentDeviceId': linkedParentDeviceId,
        'linkedChildDeviceId': linkedChildDeviceId,
        'safeZone': {
          'lat': safeZoneLat,
          'lon': safeZoneLon,
          'radius': safeZoneRadius,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logFirestoreError('saveMonitoringConfig', e);
    }
  }

  /// Load user profile from Firestore.
  static Future<Map<String, dynamic>?> loadProfile() async {
    try {
      final doc = await _userDoc.get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      _logFirestoreError('loadProfile', e);
    }
    return null;
  }

  // ── Sensor Log (optional — latest reading) ──

  /// Save latest sensor snapshot (for remote monitoring dashboard).
  static Future<void> updateSensorSnapshot({
    required double heartRate,
    required double spo2,
    required double tiltAngle,
    required double accelMag,
    required double battery,
    required String deviceState,
  }) async {
    try {
      await _userDoc.set({
        'lastSensor': {
          'heartRate': heartRate,
          'spo2': spo2,
          'tiltAngle': tiltAngle,
          'accelMag': accelMag,
          'battery': battery,
          'deviceState': deviceState,
          'timestamp': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      _logFirestoreError('updateSensorSnapshot', e);
    }
  }

  /// Save the latest merged kids safety snapshot on the user document.
  static Future<void> saveSafetySnapshot({required SafetyUpdate update}) async {
    try {
      await _userDoc.set({
        'lastSafetySnapshot': update.toMap(useServerTimestamp: true),
        'alertStatus': {
          'level': update.alertLevel,
          'reason': update.alertReason,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logFirestoreError('saveSafetySnapshot', e);
    }
  }

  /// Store historical safety updates for timeline/analytics.
  static Future<void> saveSafetyUpdate({required SafetyUpdate update}) async {
    try {
      await _safetyUpdatesCol.add(update.toMap(useServerTimestamp: true));
    } catch (e) {
      _logFirestoreError('saveSafetyUpdate', e);
    }
  }

  /// Queue an urgent push request. A Cloud Function picks this document
  /// and sends an FCM message to the linked parent phone.
  static Future<void> queueParentPushAlert({
    required String parentDeviceId,
    required SafetyUpdate update,
  }) async {
    try {
      await _safetyAlertsCol.add({
        'parentDeviceId': parentDeviceId,
        'childDeviceId': update.childDeviceId,
        'mapsUrl': update.mapsUrl,
        'latitude': update.latitude,
        'longitude': update.longitude,
        'heartRate': update.heartRate,
        'spo2': update.spo2,
        'fallDetected': update.fallDetected,
        'alertLevel': update.alertLevel,
        'alertReason': update.alertReason,
        'activity': update.activity,
        'triggerType': update.triggerType,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logFirestoreError('queueParentPushAlert', e);
    }
  }

  /// Stream latest child safety snapshot for parent monitoring UI.
  static Stream<SafetyUpdate?> streamLatestSafetySnapshot(
    String childDeviceId,
  ) {
    final id = childDeviceId.trim();
    if (id.isEmpty) return Stream<SafetyUpdate?>.value(null);

    return _db.collection('users').doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      final raw = data['lastSafetySnapshot'];
      if (raw is Map<String, dynamic>) {
        return SafetyUpdate.fromMap(raw);
      }
      if (raw is Map) {
        return SafetyUpdate.fromMap(Map<String, dynamic>.from(raw));
      }
      return null;
    });
  }

  /// Save a chat message (user or assistant) under the current user.
  static Future<void> saveChatMessage({
    required bool isUser,
    required String text,
  }) async {
    try {
      await _chatCol.add({
        'from': isUser ? 'user' : 'assistant',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logFirestoreError('saveChatMessage', e);
    }
  }

  // ── Kids Mode GPS Tracking ── (NEW)

  /// Save a kids mode GPS location point to Firestore.
  static Future<void> saveKidsLocation({
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _kidsLocationsCol.add({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logFirestoreError('saveKidsLocation', e);
    }
  }

  /// Load kids location history from Firestore (last 500 points).
  static Future<List<Map<String, dynamic>>> loadKidsLocationHistory() async {
    try {
      final snap = await _kidsLocationsCol
          .orderBy('timestamp', descending: true)
          .limit(500)
          .get();

      return snap.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _logFirestoreError('loadKidsLocationHistory', e);
      return [];
    }
  }

  /// Stream kids location history in real-time.
  static Stream<List<Map<String, dynamic>>> kidsLocationStream() {
    return _kidsLocationsCol
        .orderBy('timestamp', descending: true)
        .limit(500)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList(),
        );
  }

  /// Clear all kids location history.
  static Future<void> clearKidsLocationHistory() async {
    try {
      final snap = await _kidsLocationsCol.get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      _logFirestoreError('clearKidsLocationHistory', e);
    }
  }
}

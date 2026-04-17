import 'dart:async';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../utils/constants.dart';
import 'ble_service.dart';
import 'fall_detection_algorithm.dart';
import 'firestore_service.dart';
import 'health_rules_service.dart';
import 'kids_safety_sync_service.dart';
import 'location_service.dart';
import 'sms_service.dart';
import 'device_identity_service.dart';

/// Background service that keeps the BLE connection & fall monitoring active
/// even when the app is minimized. Uses a persistent Android foreground
/// notification so the OS doesn't kill the process.
class BackgroundMonitorService {
  BackgroundMonitorService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Initialize and configure the background service.
  /// Call once in main() before runApp().
  static Future<void> initialize() async {
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: true,
        autoStartOnBoot: true,
        foregroundServiceNotificationId: 226,
        initialNotificationTitle: 'Fall Detection Active',
        initialNotificationContent: 'Monitoring for falls in background',
        foregroundServiceTypes: [
          AndroidForegroundType.connectedDevice,
          AndroidForegroundType.location,
          AndroidForegroundType.dataSync,
        ],
      ),
    );
  }

  /// Start background monitoring.
  static Future<void> start() async {
    if (kIsWeb) return;
    try {
      final isRunning = await _service.isRunning();
      if (!isRunning) {
        await _service.startService();
        debugPrint('BackgroundService: Started');
      }
    } catch (e) {
      debugPrint('BackgroundService: start failed: $e');
    }
  }

  /// Stop background monitoring.
  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      _service.invoke('stop');
      debugPrint('BackgroundService: Stopped');
    } catch (e) {
      debugPrint('BackgroundService: stop failed: $e');
    }
  }

  /// Check if service is running.
  static Future<bool> isRunning() => _service.isRunning();

  /// Update the notification with current status.
  static void updateNotification({
    required String title,
    required String content,
  }) {
    _service.invoke('update', {'title': title, 'content': content});
  }
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}

/// Service entry point (runs in isolate on Android)
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    final prefs = await SharedPreferences.getInstance();

    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('BackgroundService Firebase init failed: $e');
      }
    }

    String appDeviceId = prefs.getString(AppConstants.prefDeviceId) ?? '';
    if (appDeviceId.trim().isEmpty) {
      try {
        appDeviceId = await DeviceIdentityService.getOrCreateDeviceId();
        await prefs.setString(AppConstants.prefDeviceId, appDeviceId);
      } catch (_) {}
    }

    if (appDeviceId.trim().isNotEmpty) {
      FirestoreService.setDeviceId(appDeviceId);
    }

    DateTime? lastSmsSentAt;
    final lastSmsAtMs = prefs.getInt('bg_last_sms_at_ms');
    if (lastSmsAtMs != null && lastSmsAtMs > 0) {
      lastSmsSentAt = DateTime.fromMillisecondsSinceEpoch(lastSmsAtMs);
    }

    Future<void> pushKidsSafetyUpdate({
      required String triggerType,
      required bool immediate,
      required bool fallDetected,
      double? gyroMag,
    }) async {
      final kidsModeEnabled =
          prefs.getBool(AppConstants.prefKidsModeEnabled) ?? false;
      final role = prefs.getString(AppConstants.prefMonitoringRole) ?? 'child';
      final parentId =
          (prefs.getString(AppConstants.prefLinkedParentDeviceId) ?? '').trim();

      if (!kidsModeEnabled || role != 'child') return;
      if (parentId.isEmpty || appDeviceId.trim().isEmpty) return;

      final hr = prefs.getDouble(AppConstants.prefLastSensorHr) ?? 0.0;
      final spo2 = prefs.getDouble(AppConstants.prefLastSensorSpo2) ?? 0.0;
      final acc = prefs.getDouble(AppConstants.prefLastSensorAcc) ?? 1.0;

      final abnormalHealth = HealthRulesService.isAbnormalVitals(
        heartRate: hr,
        spo2: spo2,
      );

      final isPeriodic = triggerType.startsWith('periodic');
      if (!immediate && !isPeriodic && !fallDetected && !abnormalHealth) {
        return;
      }

      final now = DateTime.now();
      if (immediate) {
        final lastImmediateMs = prefs.getInt('bg_last_kids_immediate_ms');
        if (lastImmediateMs != null && lastImmediateMs > 0) {
          final lastImmediate = DateTime.fromMillisecondsSinceEpoch(
            lastImmediateMs,
          );
          if (now.difference(lastImmediate) < const Duration(seconds: 45)) {
            return;
          }
        }
      }

      final position = await LocationService.getCurrentPosition();
      final safeLat = prefs.getDouble(AppConstants.prefSafeZoneLat);
      final safeLon = prefs.getDouble(AppConstants.prefSafeZoneLon);
      final safeRadius =
          prefs.getDouble(AppConstants.prefSafeZoneRadiusMeters) ?? 250.0;

      final geofenceBreached = KidsSafetySyncService.isGeofenceBreached(
        position: position,
        safeLat: safeLat,
        safeLon: safeLon,
        safeRadiusMeters: safeRadius,
      );

      final update = KidsSafetySyncService.buildUpdate(
        childDeviceId: appDeviceId,
        triggerType: triggerType,
        heartRate: hr,
        spo2: spo2,
        accelMag: acc,
        gyroMag: gyroMag,
        fallDetected: fallDetected,
        geofenceBreached: geofenceBreached,
        position: position,
      );

      await KidsSafetySyncService.pushUpdate(
        update: update,
        parentDeviceId: parentId,
        immediate: immediate || geofenceBreached,
      );

      if (position != null) {
        await FirestoreService.saveKidsLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      if (immediate || geofenceBreached) {
        await prefs.setInt(
          'bg_last_kids_immediate_ms',
          now.millisecondsSinceEpoch,
        );
      }
    }

    Timer? bleTick;
    Timer? notifTick;
    Timer? kidsSyncTick;
    bool subscriptionsReady = false;

    Future<void> ensureBleConnected() async {
      final deviceId = prefs.getString(AppConstants.prefLastBleDeviceId);
      if (deviceId == null || deviceId.trim().isEmpty) {
        return;
      }

      if (!BleService.isConnected) {
        try {
          service.setForegroundNotificationInfo(
            title: 'Fall Detection Active',
            content: 'Reconnecting to BLE device...',
          );
        } catch (_) {}

        bool ok = false;
        try {
          // Background isolate cannot safely show Android permission dialogs.
          // If permissions are missing, just stay alive and prompt the user to
          // open the app and grant them.
          ok = await BleService.autoConnectToDeviceId(
            deviceId,
            scanTimeout: const Duration(seconds: 10),
            requestPermissionsIfNeeded: false,
          );
        } catch (e) {
          debugPrint('BackgroundService autoConnect failed: $e');
          ok = false;
        }

        if (!ok) {
          try {
            service.setForegroundNotificationInfo(
              title: 'Fall Detection Active',
              content: 'Open the app to allow Bluetooth/Location permissions',
            );
          } catch (_) {}
          return;
        }
      }

      if (!subscriptionsReady && BleService.isConnected) {
        subscriptionsReady = true;

        await BleService.subscribeSensorData(
          onData: (SensorData data) {
            // Persist last received sensor data so UI can show it immediately
            // when the user re-opens the app.
            final now = DateTime.now();
            prefs.setDouble(
              AppConstants.prefLastSensorHr,
              data.heartRate.toDouble(),
            );
            prefs.setDouble(AppConstants.prefLastSensorSpo2, data.spo2);
            prefs.setDouble(AppConstants.prefLastSensorTilt, data.tiltAngle);
            prefs.setDouble(AppConstants.prefLastSensorAcc, data.accelMag);
            if (data.battery >= 0) {
              prefs.setDouble(
                AppConstants.prefLastSensorBatt,
                data.battery.toDouble(),
              );
            }
            prefs.setInt(
              AppConstants.prefLastSensorAtMs,
              now.millisecondsSinceEpoch,
            );

            // If Arduino sets FALL:1 in the stream, trigger SMS.
            if (data.fallFlag) {
              _maybeSendFallSmsFromBackground(
                service: service,
                prefs: prefs,
                lastSmsSentAt: lastSmsSentAt,
                onUpdateLastSent: (dt) {
                  lastSmsSentAt = dt;
                },
                heartRate: data.heartRate.toDouble(),
                tiltAngle: data.tiltAngle,
              );
            }

            final abnormalHealth = HealthRulesService.isAbnormalVitals(
              heartRate: data.heartRate.toDouble(),
              spo2: data.spo2,
            );
            if (data.fallFlag || abnormalHealth) {
              unawaited(
                pushKidsSafetyUpdate(
                  triggerType: data.fallFlag
                      ? 'immediate_fall_background'
                      : 'immediate_health_background',
                  immediate: true,
                  fallDetected: data.fallFlag,
                  gyroMag: data.gyroMag,
                ),
              );
            }
          },
        );

        await BleService.subscribeFallDetection(
          onFallData: (List<int> bytes) {
            if (bytes.isEmpty || bytes[0] != 1) return;
            // Binary fall alert: [fallFlag, hrHigh, hrLow, tiltAngle, accelMag*10]
            double hr = 0;
            double tilt = 0;
            if (bytes.length >= 4) {
              hr = ((bytes[1] << 8) | bytes[2]).toDouble();
              tilt = bytes[3].toDouble();
            }
            _maybeSendFallSmsFromBackground(
              service: service,
              prefs: prefs,
              lastSmsSentAt: lastSmsSentAt,
              onUpdateLastSent: (dt) {
                lastSmsSentAt = dt;
              },
              heartRate: hr,
              tiltAngle: tilt,
            );

            unawaited(
              pushKidsSafetyUpdate(
                triggerType: 'immediate_fall_packet_background',
                immediate: true,
                fallDetected: true,
              ),
            );
          },
        );
      }
    }

    service.on('stop').listen((_) {
      bleTick?.cancel();
      notifTick?.cancel();
      kidsSyncTick?.cancel();
      BleService.disconnect();
      service.stopSelf();
    });

    service.on('update').listen((data) {
      if (data != null) {
        service.setForegroundNotificationInfo(
          title: data['title'] ?? 'Fall Detection Active',
          content: data['content'] ?? 'Monitoring...',
        );
      }
    });

    // BLE keep-alive + reconnect loop
    bleTick = Timer.periodic(const Duration(seconds: 12), (_) async {
      try {
        await ensureBleConnected();
      } catch (e) {
        debugPrint('BackgroundService BLE tick error: $e');
      }
    });

    // Notification refresh loop (lightweight)
    notifTick = Timer.periodic(const Duration(seconds: 25), (_) async {
      try {
        final connected = BleService.isConnected;
        final lastHr = prefs.getDouble(AppConstants.prefLastSensorHr);
        final lastBatt = prefs.getDouble(AppConstants.prefLastSensorBatt);
        final status = connected ? 'BLE connected' : 'BLE reconnecting';
        final hrStr = (lastHr != null && lastHr > 0)
            ? 'HR ${lastHr.toInt()} BPM'
            : 'HR --';
        final battStr = (lastBatt != null && lastBatt > 0)
            ? 'BATT ${lastBatt.toInt()}%'
            : 'BATT --';

        service.setForegroundNotificationInfo(
          title: 'Fall Detection Active',
          content: '$status · $hrStr · $battStr',
        );
      } catch (_) {}
    });

    kidsSyncTick = Timer.periodic(const Duration(minutes: 1), (_) async {
      final now = DateTime.now();
      final lastSyncMs = prefs.getInt('bg_last_kids_sync_ms');
      if (lastSyncMs != null && lastSyncMs > 0) {
        final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
        if (now.difference(lastSync) < KidsSafetySyncService.periodicInterval) {
          return;
        }
      }

      try {
        await pushKidsSafetyUpdate(
          triggerType: 'periodic_background',
          immediate: false,
          fallDetected: false,
        );
        await prefs.setInt('bg_last_kids_sync_ms', now.millisecondsSinceEpoch);
      } catch (e) {
        debugPrint('BackgroundService periodic kids sync failed: $e');
      }
    });

    // Kick off immediately (but never crash the isolate on errors).
    unawaited(
      ensureBleConnected().catchError((e) {
        debugPrint('BackgroundService initial ensureBleConnected error: $e');
      }),
    );
  }
}

Future<void> _maybeSendFallSmsFromBackground({
  required AndroidServiceInstance service,
  required SharedPreferences prefs,
  required DateTime? lastSmsSentAt,
  required void Function(DateTime dt) onUpdateLastSent,
  required double heartRate,
  required double tiltAngle,
}) async {
  // Avoid spamming repeated SMS from rapid notifications.
  final now = DateTime.now();
  if (lastSmsSentAt != null && now.difference(lastSmsSentAt).inSeconds < 60) {
    return;
  }

  final smsEnabled = prefs.getBool('sms_alert_enabled') ?? true;
  final autoSms = prefs.getBool('auto_sms_on_confirm') ?? true;
  if (!smsEnabled || !autoSms) return;

  // CHECK IF BLE IS CONNECTED - Only send SMS if BLE is active
  if (!BleService.isConnected) {
    debugPrint('SMS not sent: BLE not connected');
    try {
      service.setForegroundNotificationInfo(
        title: 'Fall Detection Active',
        content: 'Fall detected, but BLE is not connected',
      );
    } catch (_) {}
    return;
  }

  final caregiverPhone =
      (prefs.getString(AppConstants.prefCaregiverPhone) ?? '').trim();
  if (caregiverPhone.isEmpty) {
    try {
      service.setForegroundNotificationInfo(
        title: 'Fall Detection Active',
        content: 'Fall detected, but caregiver phone is missing',
      );
    } catch (_) {}
    return;
  }

  final patientName =
      (prefs.getString(AppConstants.prefPatientName) ?? 'Patient').trim();
  final ok = await SmsService.sendFallAlert(
    phoneNumber: caregiverPhone,
    patientName: patientName.isNotEmpty ? patientName : 'Patient',
    heartRate: heartRate,
    tiltAngle: tiltAngle,
    fallTime: now,
    allowLaunchFallback: false,
    requireGps: true,
  );

  if (ok) {
    onUpdateLastSent(now);
    prefs.setInt('bg_last_sms_at_ms', now.millisecondsSinceEpoch);
    try {
      service.setForegroundNotificationInfo(
        title: 'Fall Detection Active',
        content: 'Fall detected · SMS sent to caregiver',
      );
    } catch (_) {}
  } else {
    try {
      service.setForegroundNotificationInfo(
        title: 'Fall Detection Active',
        content: 'Fall detected · SMS failed to send',
      );
    } catch (_) {}
  }
}

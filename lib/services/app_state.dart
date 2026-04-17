import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fall_event.dart';
import '../models/smartwatch_capability_report.dart';
import '../utils/constants.dart';
import 'activity_classifier_service.dart';
import 'ble_service.dart';
import 'device_identity_service.dart';
import 'fcm_service.dart';
import 'sms_service.dart';
import 'location_service.dart';
import 'fall_detection_algorithm.dart';
import 'firestore_service.dart';
import 'health_rules_service.dart';
import 'kids_safety_sync_service.dart';
import 'medical_analysis_service.dart';
import 'tflite_fall_detection_service.dart';

enum MonitoringRole { child, parent }

extension MonitoringRoleX on MonitoringRole {
  String get wireValue => this == MonitoringRole.parent ? 'parent' : 'child';

  static MonitoringRole fromWire(String raw) {
    return raw.toLowerCase() == 'parent'
        ? MonitoringRole.parent
        : MonitoringRole.child;
  }
}

class AppState extends ChangeNotifier {
  // ── Theme ──
  bool isDarkMode = true;

  // ── Device State ──
  String deviceState = 'IDLE';
  double batteryLevel = 0;
  double heartRate = 0.0;
  double spo2 = 0.0;
  double bodyTemperature = 37.0; // New: Body temperature support
  double tiltAngle = 0.0;
  double accelMag = 1.0;
  bool alertActive = false;
  bool _monitoring = false;
  bool get isMonitoring => _monitoring;

  // ── AI Detection State ──
  double aiFallProbability = 0.0;
  String aiLabel = 'Stable';

  // ── Caregiver / Patient ──
  String _caregiverName = '';
  String _patientName = '';
  String _caregiverPhone = '';
  String _patientPhone = '';
  String _caregiverEmail = '';
  String _patientEmail = '';

  String? _patientPhotoBase64;

  bool _onboardingComplete = false;

  // ── Kids Mode ── (NEW)
  bool _kidsModeEnabled = false;
  MonitoringRole _monitoringRole = MonitoringRole.child;
  String _linkedParentDeviceId = '';
  String _linkedChildDeviceId = '';
  String _deviceId = '';

  double? _safeZoneLat;
  double? _safeZoneLon;
  double _safeZoneRadiusMeters = 250.0;

  double? _lastKidsLat;
  double? _lastKidsLon;
  bool _kidsModeGpsValid = false;
  DateTime? _lastKidsGpsUpdate;
  DateTime? _lastKidsPeriodicSyncAt;
  DateTime? _lastKidsImmediateAlertAt;
  String _lastActivity = 'unknown';
  bool _geofenceBreached = false;

  List<({double lat, double lon, DateTime timestamp})> _kidsLocationHistory =
      [];

  bool get kidsModeEnabled => _kidsModeEnabled;
  MonitoringRole get monitoringRole => _monitoringRole;
  String get linkedParentDeviceId => _linkedParentDeviceId;
  String get linkedChildDeviceId => _linkedChildDeviceId;
  String get deviceId => _deviceId;
  double? get safeZoneLat => _safeZoneLat;
  double? get safeZoneLon => _safeZoneLon;
  double get safeZoneRadiusMeters => _safeZoneRadiusMeters;

  double? get lastKidsLat => _lastKidsLat;
  double? get lastKidsLon => _lastKidsLon;
  bool get kidsModeGpsValid => _kidsModeGpsValid;
  DateTime? get lastKidsGpsUpdate => _lastKidsGpsUpdate;
  DateTime? get lastKidsPeriodicSyncAt => _lastKidsPeriodicSyncAt;
  DateTime? get lastKidsImmediateAlertAt => _lastKidsImmediateAlertAt;
  String get lastActivity => _lastActivity;
  bool get geofenceBreached => _geofenceBreached;

  List<({double lat, double lon, DateTime timestamp})>
  get kidsLocationHistory => _kidsLocationHistory;

  StreamSubscription? _remoteKidsSub;
  StreamSubscription<Position>? _phoneLocationSub;
  Timer? _kidsPeriodicTimer;
  DateTime? _lastPhoneLocationCloudSyncAt;

  String get caregiverName => _caregiverName;
  String get patientName => _patientName;
  String get caregiverPhone => _caregiverPhone;
  String get patientPhone => _patientPhone;
  String get caregiverEmail => _caregiverEmail;
  String get patientEmail => _patientEmail;
  String? get patientPhotoBase64 => _patientPhotoBase64;
  bool get onboardingComplete => _onboardingComplete;

  set caregiverName(String v) {
    _caregiverName = v;
    _saveStringPref(AppConstants.prefCaregiverName, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  set patientName(String v) {
    _patientName = v;
    _saveStringPref(AppConstants.prefPatientName, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  set caregiverPhone(String v) {
    _caregiverPhone = v;
    _saveStringPref(AppConstants.prefCaregiverPhone, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  set patientPhone(String v) {
    _patientPhone = v;
    _saveStringPref(AppConstants.prefPatientPhone, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  set caregiverEmail(String v) {
    _caregiverEmail = v;
    _saveStringPref(AppConstants.prefCaregiverEmail, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  set patientEmail(String v) {
    _patientEmail = v;
    _saveStringPref(AppConstants.prefPatientEmail, v);
    _syncProfileToCloud();
    notifyListeners();
  }

  void markOnboardingComplete() {
    _onboardingComplete = true;
    _saveBoolPref(AppConstants.prefOnboardingComplete, true);
    notifyListeners();
  }

  // ── Kids Mode Methods ── (NEW)
  void enableKidsMode() {
    _kidsModeEnabled = true;
    _saveBoolPref(AppConstants.prefKidsModeEnabled, true);
    _kidsLocationHistory = [];
    unawaited(_startPhoneLocationTracking());
    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  void disableKidsMode() {
    _kidsModeEnabled = false;
    _saveBoolPref(AppConstants.prefKidsModeEnabled, false);
    _remoteKidsSub?.cancel();
    _stopPhoneLocationTracking();
    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  void setMonitoringRole(MonitoringRole role) {
    _monitoringRole = role;
    _saveStringPref(AppConstants.prefMonitoringRole, role.wireValue);
    if (_monitoringRole == MonitoringRole.child && _kidsModeEnabled) {
      unawaited(_startPhoneLocationTracking());
    } else {
      _stopPhoneLocationTracking();
    }
    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  void setLinkedParentDeviceId(String value) {
    _linkedParentDeviceId = value.trim();
    _saveStringPref(
      AppConstants.prefLinkedParentDeviceId,
      _linkedParentDeviceId,
    );
    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  void setLinkedChildDeviceId(String value) {
    _linkedChildDeviceId = value.trim();
    _saveStringPref(AppConstants.prefLinkedChildDeviceId, _linkedChildDeviceId);
    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  Future<void> setSafeZone({
    required double latitude,
    required double longitude,
    double radiusMeters = 250.0,
  }) async {
    _safeZoneLat = latitude;
    _safeZoneLon = longitude;
    _safeZoneRadiusMeters = radiusMeters;

    await _saveDoublePref(AppConstants.prefSafeZoneLat, latitude);
    await _saveDoublePref(AppConstants.prefSafeZoneLon, longitude);
    await _saveDoublePref(AppConstants.prefSafeZoneRadiusMeters, radiusMeters);

    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  Future<void> clearSafeZone() async {
    _safeZoneLat = null;
    _safeZoneLon = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.prefSafeZoneLat);
      await prefs.remove(AppConstants.prefSafeZoneLon);
    } catch (_) {}

    _syncMonitoringConfigToCloud();
    notifyListeners();
  }

  void updateKidsGpsLocation(double? lat, double? lon, bool valid) {
    _lastKidsLat = lat;
    _lastKidsLon = lon;
    _kidsModeGpsValid = valid;
    _lastKidsGpsUpdate = DateTime.now();

    if (valid && lat != null && lon != null) {
      _kidsLocationHistory.add((lat: lat, lon: lon, timestamp: DateTime.now()));
      // Keep only last 100 locations
      if (_kidsLocationHistory.length > 100) {
        _kidsLocationHistory.removeAt(0);
      }
    }

    notifyListeners();
  }

  Future<void> _startPhoneLocationTracking() async {
    if (!_kidsModeEnabled || _monitoringRole != MonitoringRole.child) return;

    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) return;

    await _phoneLocationSub?.cancel();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _phoneLocationSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) {
          updateKidsGpsLocation(position.latitude, position.longitude, true);

          if (!_firebaseReady || _monitoringRole != MonitoringRole.child) {
            return;
          }

          final now = DateTime.now();
          if (_lastPhoneLocationCloudSyncAt != null &&
              now.difference(_lastPhoneLocationCloudSyncAt!) <
                  const Duration(seconds: 20)) {
            return;
          }

          _lastPhoneLocationCloudSyncAt = now;
          FirestoreService.saveKidsLocation(
            latitude: position.latitude,
            longitude: position.longitude,
          );
        });
  }

  void _stopPhoneLocationTracking() {
    _phoneLocationSub?.cancel();
    _phoneLocationSub = null;
  }

  Future<void> setPatientPhotoBase64(String? base64) async {
    _patientPhotoBase64 = base64;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (base64 == null || base64.isEmpty) {
        await prefs.remove(AppConstants.prefProfilePhoto);
      } else {
        await prefs.setString(AppConstants.prefProfilePhoto, base64);
      }
    } catch (_) {}
    notifyListeners();
  }

  // ── SMS Settings ──
  bool smsAlertEnabled = true;
  bool autoSmsOnConfirm = true;
  bool _smsSending = false;
  String? lastSmsError;
  bool get smsSending => _smsSending;

  // ── BLE Device State ──
  String? bleDeviceName;
  String? bleDeviceId;
  double bleDeviceBattery = 0;
  bool _bleReconnecting = false;
  SmartwatchCapabilityReport? smartwatchCapabilityReport;

  // Persisted identity used for auto-connect on next app open.
  String? lastBleDeviceId;
  String? lastBleDeviceName;

  // Connected means the BLE layer is connected now.
  bool get isBleConnected => BleService.isConnected;
  bool get isBleReconnecting => _bleReconnecting;

  bool _autoConnectAttempted = false;

  // 20s cancellation window (report)
  static const int _alertCancelWindowSeconds = 20;
  static const Duration _falseAlarmCooldown = Duration(seconds: 15);
  Timer? _alertCountdownTimer;
  int _alertSecondsRemaining = 0;
  int get alertSecondsRemaining => _alertSecondsRemaining;

  DateTime? _lastFalseAlarmAt;

  // ── GPS ──
  String? lastGpsLocation;
  String? lastMapsUrl;

  // ── Phone-side fall detection algorithm (redundant safety layer) ──
  final FallDetectionAlgorithm _fallAlgorithm = FallDetectionAlgorithm();

  // ── Sensor data timestamp ──
  DateTime? lastSensorUpdate;

  // ── Fall History ──
  List<FallEvent> fallHistory = [];

  /// Whether Firebase/Firestore is available.
  bool _firebaseReady = false;
  bool get firebaseReady => _firebaseReady;

  AppState() {
    _initBleCallbacks();
    unawaited(_bootstrapLocalState());
  }

  Future<void> _bootstrapLocalState() async {
    await _loadLocalPrefs();

    try {
      _deviceId = await DeviceIdentityService.getOrCreateDeviceId();
      FirestoreService.setDeviceId(_deviceId);
    } catch (_) {}

    try {
      await TfliteFallDetectionService.instance.initialize();
    } catch (_) {}

    _startKidsPeriodicSyncTimer();
    if (_kidsModeEnabled && _monitoringRole == MonitoringRole.child) {
      unawaited(_startPhoneLocationTracking());
    }
    notifyListeners();
  }

  Future<void> _loadLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isDarkMode = prefs.getBool(AppConstants.prefDarkMode) ?? isDarkMode;
      _patientName =
          prefs.getString(AppConstants.prefPatientName) ?? _patientName;
      _patientPhone =
          prefs.getString(AppConstants.prefPatientPhone) ?? _patientPhone;
      _patientEmail =
          prefs.getString(AppConstants.prefPatientEmail) ?? _patientEmail;
      _caregiverName =
          prefs.getString(AppConstants.prefCaregiverName) ?? _caregiverName;
      _caregiverPhone =
          prefs.getString(AppConstants.prefCaregiverPhone) ?? _caregiverPhone;
      _caregiverEmail =
          prefs.getString(AppConstants.prefCaregiverEmail) ?? _caregiverEmail;
      final storedPhoto = prefs.getString(AppConstants.prefProfilePhoto);
      _patientPhotoBase64 = (storedPhoto != null && storedPhoto.isNotEmpty)
          ? storedPhoto
          : null;
      _onboardingComplete =
          prefs.getBool(AppConstants.prefOnboardingComplete) ?? false;
      smsAlertEnabled = prefs.getBool('sms_alert_enabled') ?? smsAlertEnabled;
      autoSmsOnConfirm =
          prefs.getBool('auto_sms_on_confirm') ?? autoSmsOnConfirm;

      // Restore last saved sensor snapshot (for immediate UI on app open)
      final lastHr = prefs.getDouble(AppConstants.prefLastSensorHr);
      final lastSpo2 = prefs.getDouble(AppConstants.prefLastSensorSpo2);
      final lastTilt = prefs.getDouble(AppConstants.prefLastSensorTilt);
      final lastAcc = prefs.getDouble(AppConstants.prefLastSensorAcc);
      final lastBatt = prefs.getDouble(AppConstants.prefLastSensorBatt);
      final lastAtMs = prefs.getInt(AppConstants.prefLastSensorAtMs);

      if (lastHr != null) heartRate = lastHr;
      if (lastSpo2 != null) spo2 = lastSpo2;
      if (lastTilt != null) tiltAngle = lastTilt;
      if (lastAcc != null) accelMag = lastAcc;
      if (lastBatt != null) batteryLevel = lastBatt;
      if (lastAtMs != null && lastAtMs > 0) {
        lastSensorUpdate = DateTime.fromMillisecondsSinceEpoch(lastAtMs);
      }

      // Restore last known device identity (used for auto-connect)
      lastBleDeviceId = prefs.getString(AppConstants.prefLastBleDeviceId);
      lastBleDeviceName = prefs.getString(AppConstants.prefLastBleDeviceName);

      // Kids safety mode config
      _kidsModeEnabled =
          prefs.getBool(AppConstants.prefKidsModeEnabled) ?? _kidsModeEnabled;
      _monitoringRole = MonitoringRoleX.fromWire(
        prefs.getString(AppConstants.prefMonitoringRole) ?? 'child',
      );
      _linkedParentDeviceId =
          prefs.getString(AppConstants.prefLinkedParentDeviceId) ??
          _linkedParentDeviceId;
      _linkedChildDeviceId =
          prefs.getString(AppConstants.prefLinkedChildDeviceId) ??
          _linkedChildDeviceId;
      _safeZoneLat = prefs.getDouble(AppConstants.prefSafeZoneLat);
      _safeZoneLon = prefs.getDouble(AppConstants.prefSafeZoneLon);
      _safeZoneRadiusMeters =
          prefs.getDouble(AppConstants.prefSafeZoneRadiusMeters) ??
          _safeZoneRadiusMeters;

      notifyListeners();
    } catch (_) {
      // Keep defaults if local storage is unavailable.
    }
  }

  Future<void> _saveStringPref(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _saveBoolPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _saveDoublePref(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }

  Future<void> _saveIntPref(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {}
  }

  /// Call after Firebase.initializeApp() completes.
  Future<void> initFirebase() async {
    if (_deviceId.trim().isEmpty) {
      _deviceId = await DeviceIdentityService.getOrCreateDeviceId();
      FirestoreService.setDeviceId(_deviceId);
    }

    _firebaseReady = true;

    try {
      await FcmService.initialize();
    } catch (_) {}

    // Load profile from cloud
    final profile = await FirestoreService.loadProfile().timeout(
      const Duration(seconds: 6),
      onTimeout: () => null,
    );
    if (profile != null) {
      _patientName = profile['patientName'] as String? ?? _patientName;
      _caregiverName = profile['caregiverName'] as String? ?? _caregiverName;
      _caregiverPhone = profile['caregiverPhone'] as String? ?? _caregiverPhone;
      _patientPhone = profile['patientPhone'] as String? ?? _patientPhone;
      _patientEmail = profile['patientEmail'] as String? ?? _patientEmail;
      _caregiverEmail = profile['caregiverEmail'] as String? ?? _caregiverEmail;
      smsAlertEnabled = profile['smsAlertEnabled'] as bool? ?? smsAlertEnabled;
      autoSmsOnConfirm =
          profile['autoSmsOnConfirm'] as bool? ?? autoSmsOnConfirm;

      _monitoringRole = MonitoringRoleX.fromWire(
        profile['monitoringRole'] as String? ?? _monitoringRole.wireValue,
      );
      _linkedParentDeviceId =
          profile['linkedParentDeviceId'] as String? ?? _linkedParentDeviceId;
      _linkedChildDeviceId =
          profile['linkedChildDeviceId'] as String? ?? _linkedChildDeviceId;

      final safeZone = profile['safeZone'];
      if (safeZone is Map) {
        final m = Map<String, dynamic>.from(safeZone);
        _safeZoneLat = (m['lat'] as num?)?.toDouble() ?? _safeZoneLat;
        _safeZoneLon = (m['lon'] as num?)?.toDouble() ?? _safeZoneLon;
        _safeZoneRadiusMeters =
            (m['radius'] as num?)?.toDouble() ?? _safeZoneRadiusMeters;
      }
    }

    // Load fall history from cloud
    final history = await FirestoreService.loadFallHistory().timeout(
      const Duration(seconds: 6),
      onTimeout: () => <FallEvent>[],
    );
    if (history.isNotEmpty) {
      fallHistory = history;
    }

    // Start listening for remote kids mode location updates
    _remoteKidsSub?.cancel();
    _remoteKidsSub = FirestoreService.kidsLocationStream().listen((list) {
      if (!_kidsModeEnabled || list.isEmpty) return;

      // If we are NOT connected via BLE, use cloud data for "Remote Tracking"
      if (!BleService.isConnected) {
        final last = list.first;
        final lat = (last['latitude'] as num).toDouble();
        final lon = (last['longitude'] as num).toDouble();
        final ts =
            (last['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

        // Only update if it's newer than our local data
        if (_lastKidsGpsUpdate == null || ts.isAfter(_lastKidsGpsUpdate!)) {
          _lastKidsLat = lat;
          _lastKidsLon = lon;
          _kidsModeGpsValid = true;
          _lastKidsGpsUpdate = ts;

          // Rebuild history from cloud if local is empty
          if (_kidsLocationHistory.isEmpty) {
            _kidsLocationHistory = list
                .take(100)
                .map(
                  (d) => (
                    lat: (d['latitude'] as num).toDouble(),
                    lon: (d['longitude'] as num).toDouble(),
                    timestamp:
                        (d['timestamp'] as Timestamp?)?.toDate() ??
                        DateTime.now(),
                  ),
                )
                .toList()
                .reversed
                .toList();
          }

          notifyListeners();
        }
      }
    });

    _syncMonitoringConfigToCloud();

    if (_kidsModeEnabled && _monitoringRole == MonitoringRole.child) {
      unawaited(_startPhoneLocationTracking());
    }

    notifyListeners();
  }

  // ── BLE Integration ──

  void _initBleCallbacks() {
    BleService.setConnectionCallback((connected, deviceName) {
      if (connected) {
        _bleReconnecting = false;

        // Ensure AppState knows *which* device is connected (id + name)
        final dev = BleService.connectedDevice;
        if (dev != null) {
          final rawId = dev.remoteId.str;
          final shortId = rawId.length > 6
              ? rawId.substring(rawId.length - 6)
              : rawId;
          final name = dev.platformName.isNotEmpty
              ? dev.platformName
              : (deviceName?.isNotEmpty == true ? deviceName! : 'BLE-$shortId');
          // Battery may be unavailable; we update again when polling fires.
          BleService.readBatteryLevel().then((batt) {
            setBleDevice(
              name: name,
              id: rawId,
              battery: batt >= 0 ? batt.toDouble() : bleDeviceBattery,
            );
          });

          BleService.inspectConnectedDevice().then((report) {
            smartwatchCapabilityReport = report;
            notifyListeners();
          });
        }

        // Start battery polling
        BleService.startBatteryPolling(
          onBattery: (level) => updateBleBattery(level.toDouble()),
        );

        // Subscribe to real-time sensor data stream
        BleService.subscribeSensorData(
          onData: (data) => _handleSensorData(data),
        );

        // Subscribe to binary fall alert notifications (redundant channel)
        BleService.subscribeFallDetection(
          onFallData: (data) => _handleFallDataFromArduino(data),
        );

        // Optional support for standard smartwatch health profiles.
        // This enables universal monitoring for non-ESP32 devices.
        BleService.subscribeUniversalVitals(
          onHeartRate: (hr) => _handleStandardHeartRate(hr),
          onSpO2: (val) => _handleStandardSpO2(val),
          onTemp: (val) => _handleStandardTemperature(val),
        );

        _monitoring = true;
        deviceState = 'Active';
      } else {
        if (BleService.autoReconnectEnabled &&
            BleService.reconnectAttempts > 0) {
          _bleReconnecting = true;
        }
        _monitoring = false;
        deviceState = 'IDLE';
        clearBleDevice();
      }
      notifyListeners();
    });
  }

  /// Auto-connect to the last known BLE device (silent, best-effort).
  /// Called once when the app opens.
  Future<void> tryAutoConnectToLastDevice() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;

    if (BleService.isConnected) return;

    final id = lastBleDeviceId;
    if (id == null || id.isEmpty) return;

    _bleReconnecting = true;
    notifyListeners();

    try {
      final ok = await BleService.autoConnectToDeviceId(id);
      if (!ok) {
        _bleReconnecting = false;
        notifyListeners();
      }
    } catch (_) {
      _bleReconnecting = false;
      notifyListeners();
    }
  }

  // ── Sensor snapshot throttle ──
  DateTime? _lastUiNotifyAt;
  DateTime? _lastCustomSensorAt;
  static const Duration _minUiNotifyInterval = Duration(milliseconds: 220);

  void _notifyUiThrottled() {
    final now = DateTime.now();
    if (_lastUiNotifyAt == null ||
        now.difference(_lastUiNotifyAt!) >= _minUiNotifyInterval) {
      _lastUiNotifyAt = now;
      notifyListeners();
    }
  }

  /// Handle real-time sensor data from the Arduino's string stream.
  /// Format: "HR:72,TILT:3.2,ACC:1.02,BATT:87,FALL:0"
  void _handleSensorData(SensorData data) {
    _lastCustomSensorAt = DateTime.now();
    bool uiChanged = false;

    final nextHeartRate = data.heartRate.toDouble();
    if ((nextHeartRate - heartRate).abs() >= 1.0) {
      heartRate = nextHeartRate;
      uiChanged = true;
    }

    if ((data.spo2 - spo2).abs() >= 0.5) {
      spo2 = data.spo2;
      uiChanged = true;
    }

    if ((data.tiltAngle - tiltAngle).abs() >= 0.3) {
      tiltAngle = data.tiltAngle;
      uiChanged = true;
    }

    if ((data.accelMag - accelMag).abs() >= 0.02) {
      accelMag = data.accelMag;
      uiChanged = true;
    }
    lastSensorUpdate = DateTime.now();

    // Add data point to medical analysis service
    MedicalAnalysisService.addDataPoint(
      MedicalDataPoint(
        timestamp: DateTime.now(),
        heartRate: heartRate,
        spO2: spo2,
        temperature: null, // Not available from basic sensor data
        accelMag: accelMag,
        battery: batteryLevel,
        latitude: null,
        longitude: null,
      ),
    );

    _persistLastSensorSnapshotThrottled();

    // -- Local TFLite fall classification --
    final tfliteProbability = TfliteFallDetectionService.instance
        .addSampleAndPredict(data: data);

    aiFallProbability =
        tfliteProbability ??
        TfliteFallDetectionService.fallbackHeuristic(
          accelMag: accelMag,
          tiltAngle: tiltAngle,
          heartRate: heartRate,
          spo2: spo2,
        );
    aiLabel = TfliteFallDetectionService.probabilityToLabel(aiFallProbability);

    _lastActivity = ActivityClassifierService.classify(
      accelMag: accelMag,
      gyroMag: data.gyroMag,
      heartRate: heartRate,
    );

    // Send immediate parent update for danger events (fall or abnormal vitals).
    final aiSaysFall =
        tfliteProbability != null &&
        TfliteFallDetectionService.instance.isFallByThreshold(
          tfliteProbability,
        );

    unawaited(
      _handleImmediateKidsSafetyUpdate(
        triggerType: 'immediate_sensor',
        fallDetected: data.fallFlag || aiSaysFall,
        gyroMag: data.gyroMag,
      ),
    );

    final inFalseAlarmCooldown = _isInFalseAlarmCooldown();

    // 1. Hardware Trigger
    if (data.fallFlag && !alertActive && !inFalseAlarmCooldown) {
      _triggerFallAlert();
      return;
    }

    // 2. Local AI Trigger (High Confidence)
    if (aiSaysFall && !alertActive && !inFalseAlarmCooldown) {
      debugPrint('AI triggered fall alert with confidence: $aiFallProbability');
      _triggerFallAlert();
      return;
    }

    // 3. Fallback Algorithm Trigger
    if (!alertActive && !inFalseAlarmCooldown) {
      final phoneFallDetected = _fallAlgorithm.processSensorData(data);
      if (phoneFallDetected) {
        _triggerFallAlert();
        return;
      }
    }

    if (uiChanged) {
      _notifyUiThrottled();
    }
  }

  DateTime? _lastLocalSnapshotSavedAt;
  void _persistLastSensorSnapshotThrottled() {
    final now = DateTime.now();
    if (_lastLocalSnapshotSavedAt != null &&
        now.difference(_lastLocalSnapshotSavedAt!).inMilliseconds < 900) {
      return;
    }
    _lastLocalSnapshotSavedAt = now;

    _saveDoublePref(AppConstants.prefLastSensorHr, heartRate);
    _saveDoublePref(AppConstants.prefLastSensorSpo2, spo2);
    _saveDoublePref(AppConstants.prefLastSensorTilt, tiltAngle);
    _saveDoublePref(AppConstants.prefLastSensorAcc, accelMag);
    _saveDoublePref(AppConstants.prefLastSensorBatt, batteryLevel);
    _saveIntPref(AppConstants.prefLastSensorAtMs, now.millisecondsSinceEpoch);
  }

  void _startKidsPeriodicSyncTimer() {
    _kidsPeriodicTimer?.cancel();
    _kidsPeriodicTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_sendPeriodicKidsSafetyUpdate());
    });
  }

  bool _canSyncKidsSafety() {
    return _firebaseReady &&
        _kidsModeEnabled &&
        _monitoringRole == MonitoringRole.child &&
        _deviceId.trim().isNotEmpty &&
        _linkedParentDeviceId.trim().isNotEmpty;
  }

  Future<void> _sendPeriodicKidsSafetyUpdate() async {
    if (!_canSyncKidsSafety()) return;

    final now = DateTime.now();
    if (_lastKidsPeriodicSyncAt != null &&
        now.difference(_lastKidsPeriodicSyncAt!) <
            KidsSafetySyncService.periodicInterval) {
      return;
    }

    final pos = await LocationService.getCurrentPosition();
    final geofence = KidsSafetySyncService.isGeofenceBreached(
      position: pos,
      safeLat: _safeZoneLat,
      safeLon: _safeZoneLon,
      safeRadiusMeters: _safeZoneRadiusMeters,
    );

    _geofenceBreached = geofence;

    final update = KidsSafetySyncService.buildUpdate(
      childDeviceId: _deviceId,
      triggerType: 'periodic',
      heartRate: heartRate,
      spo2: spo2,
      accelMag: accelMag,
      gyroMag: null,
      fallDetected: alertActive,
      geofenceBreached: geofence,
      position: pos,
    );

    _lastActivity = update.activity;
    _lastKidsPeriodicSyncAt = now;

    if (pos != null) {
      updateKidsGpsLocation(pos.latitude, pos.longitude, true);
      FirestoreService.saveKidsLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    }

    await KidsSafetySyncService.pushUpdate(
      update: update,
      parentDeviceId: _linkedParentDeviceId,
      immediate: geofence,
    );

    if (geofence) {
      _lastKidsImmediateAlertAt = now;
    }
  }

  Future<void> _handleImmediateKidsSafetyUpdate({
    required String triggerType,
    required bool fallDetected,
    required double? gyroMag,
  }) async {
    if (!_canSyncKidsSafety()) return;

    final abnormalHealth = HealthRulesService.isAbnormalVitals(
      heartRate: heartRate,
      spo2: spo2,
    );

    if (!fallDetected && !abnormalHealth) return;

    final now = DateTime.now();
    if (_lastKidsImmediateAlertAt != null &&
        now.difference(_lastKidsImmediateAlertAt!) <
            const Duration(seconds: 45)) {
      return;
    }

    final pos = await LocationService.getCurrentPosition();
    final geofence = KidsSafetySyncService.isGeofenceBreached(
      position: pos,
      safeLat: _safeZoneLat,
      safeLon: _safeZoneLon,
      safeRadiusMeters: _safeZoneRadiusMeters,
    );

    _geofenceBreached = geofence;

    final update = KidsSafetySyncService.buildUpdate(
      childDeviceId: _deviceId,
      triggerType: triggerType,
      heartRate: heartRate,
      spo2: spo2,
      accelMag: accelMag,
      gyroMag: gyroMag,
      fallDetected: fallDetected,
      geofenceBreached: geofence,
      position: pos,
    );

    _lastActivity = update.activity;
    _lastKidsImmediateAlertAt = now;

    if (pos != null) {
      updateKidsGpsLocation(pos.latitude, pos.longitude, true);
      FirestoreService.saveKidsLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    }

    await KidsSafetySyncService.pushUpdate(
      update: update,
      parentDeviceId: _linkedParentDeviceId,
      immediate: true,
    );
  }

  void _handleStandardHeartRate(int hr) {
    if (hr <= 0) return;

    // Avoid overriding ESP32 HR while custom sensor packets are fresh.
    final customFresh =
        _lastCustomSensorAt != null &&
        DateTime.now().difference(_lastCustomSensorAt!).inSeconds < 3;
    if (customFresh) return;

    if ((hr.toDouble() - heartRate).abs() >= 1.0) {
      heartRate = hr.toDouble();
      lastSensorUpdate = DateTime.now();

      // Update medical analysis
      MedicalAnalysisService.addDataPoint(
        MedicalDataPoint(
          timestamp: DateTime.now(),
          heartRate: heartRate,
          spO2: spo2,
          temperature: bodyTemperature,
          accelMag: accelMag,
          battery: batteryLevel,
        ),
      );

      _notifyUiThrottled();
    }
  }

  void _handleStandardSpO2(double val) {
    if (val <= 0) return;
    final customFresh =
        _lastCustomSensorAt != null &&
        DateTime.now().difference(_lastCustomSensorAt!).inSeconds < 3;
    if (customFresh) return;

    if ((val - spo2).abs() >= 0.5) {
      spo2 = val;
      lastSensorUpdate = DateTime.now();
      MedicalAnalysisService.addDataPoint(
        MedicalDataPoint(
          timestamp: DateTime.now(),
          heartRate: heartRate,
          spO2: spo2,
          temperature: bodyTemperature,
          accelMag: accelMag,
          battery: batteryLevel,
        ),
      );
      _notifyUiThrottled();
    }
  }

  void _handleStandardTemperature(double val) {
    if (val <= 0) return;

    // Most smartwatches with temp don't have custom ESP32 streams,
    // but we check anyway.
    final customFresh =
        _lastCustomSensorAt != null &&
        DateTime.now().difference(_lastCustomSensorAt!).inSeconds < 3;
    if (customFresh) return;

    if ((val - bodyTemperature).abs() >= 0.1) {
      bodyTemperature = val;
      lastSensorUpdate = DateTime.now();
      MedicalAnalysisService.addDataPoint(
        MedicalDataPoint(
          timestamp: DateTime.now(),
          heartRate: heartRate,
          spO2: spo2,
          temperature: bodyTemperature,
          accelMag: accelMag,
          battery: batteryLevel,
        ),
      );
      _notifyUiThrottled();
    }
  }

  bool _isInFalseAlarmCooldown() {
    if (_lastFalseAlarmAt == null) return false;
    return DateTime.now().difference(_lastFalseAlarmAt!) < _falseAlarmCooldown;
  }

  /// Handle binary fall alert from Arduino (redundant channel).
  /// Format: [fallFlag, hrHigh, hrLow, tiltAngle, accelMag*10]
  void _handleFallDataFromArduino(List<int> data) {
    if (data.isEmpty || data[0] != 1) return;
    if (alertActive) return; // Already alerting

    // Parse sensor data from binary payload
    if (data.length >= 5) {
      heartRate = ((data[1] << 8) | data[2]).toDouble();
      tiltAngle = data[3].toDouble();
      accelMag = data[4] / 10.0;
    }

    unawaited(
      _handleImmediateKidsSafetyUpdate(
        triggerType: 'immediate_fall_packet',
        fallDetected: true,
        gyroMag: null,
      ),
    );

    _triggerFallAlert();
  }

  void _triggerFallAlert() async {
    alertActive = true;
    deviceState = 'FALL_DETECTED';

    unawaited(
      _handleImmediateKidsSafetyUpdate(
        triggerType: 'immediate_fall_alert',
        fallDetected: true,
        gyroMag: null,
      ),
    );

    // Start/reset the 20-second cancellation window.
    _startAlertCountdown();
    notifyListeners();

    // Fetch GPS immediately
    final pos = await LocationService.getCurrentPosition();

    // If the user cancelled the alert while GPS was fetching, abort.
    if (!alertActive) return;

    if (pos != null) {
      lastGpsLocation = LocationService.formatPosition(pos);
      lastMapsUrl = LocationService.getMapsUrl(pos);
    }

    deviceState = 'ALERT_SENT';
    notifyListeners();
  }

  void _startAlertCountdown() {
    _alertCountdownTimer?.cancel();
    _alertSecondsRemaining = _alertCancelWindowSeconds;

    _alertCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!alertActive) {
        t.cancel();
        return;
      }

      _alertSecondsRemaining = (_alertSecondsRemaining - 1).clamp(0, 9999);
      notifyListeners();

      if (_alertSecondsRemaining <= 0) {
        t.cancel();
        unawaited(confirmFall(fromCountdown: true));
      }
    });
  }

  void setBleDevice({
    required String name,
    required String id,
    required double battery,
  }) {
    final prevId = bleDeviceId;
    final prevName = bleDeviceName;
    final prevBattery = bleDeviceBattery;
    bleDeviceName = name;
    bleDeviceId = id;
    lastBleDeviceId = id;
    lastBleDeviceName = name;
    bleDeviceBattery = battery;

    // Persist for auto-connect next time.
    _saveStringPref(AppConstants.prefLastBleDeviceId, id);
    _saveStringPref(AppConstants.prefLastBleDeviceName, name);
    if (battery >= 0) batteryLevel = battery;
    _bleReconnecting = false;
    if (prevId != bleDeviceId ||
        prevName != bleDeviceName ||
        (prevBattery - bleDeviceBattery).abs() >= 1.0) {
      notifyListeners();
    }
  }

  void clearBleDevice() {
    bleDeviceName = null;
    bleDeviceId = null;
    bleDeviceBattery = 0;
    smartwatchCapabilityReport = null;
    _fallAlgorithm.reset();
    notifyListeners();
  }

  void updateBleBattery(double battery) {
    if ((battery - bleDeviceBattery).abs() < 1.0) return;
    bleDeviceBattery = battery;
    batteryLevel = battery;
    notifyListeners();
  }

  // ── Theme ──

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    _saveBoolPref(AppConstants.prefDarkMode, isDarkMode);
    notifyListeners();
  }

  // ── Fall Detection ──

  void simulateFall() {
    heartRate = 128.0;
    tiltAngle = 72.1;
    accelMag = 3.15;
    _triggerFallAlert();
  }

  Future<void> confirmFall({bool fromCountdown = false}) async {
    if (!alertActive) return;

    // Stop any pending auto-confirm.
    _alertCountdownTimer?.cancel();
    _alertCountdownTimer = null;
    _alertSecondsRemaining = 0;

    // Get GPS for the record
    final pos = await LocationService.getCurrentPosition();
    String? gps;
    if (pos != null) {
      gps = LocationService.formatPosition(pos);
      lastGpsLocation = gps;
      lastMapsUrl = LocationService.getMapsUrl(pos);
    }

    // If the user cancelled while we were fetching GPS, do nothing.
    if (!alertActive) return;

    final event = FallEvent(
      time: DateTime.now(),
      heartRate: heartRate,
      tiltAngle: tiltAngle,
      accelMag: accelMag,
      status: 'CONFIRMED',
      gpsLocation: gps,
    );
    fallHistory.insert(0, event);

    // Add fall event to medical analysis
    MedicalAnalysisService.addFallEvent(event);

    if (_firebaseReady) FirestoreService.saveFallEvent(event);

    // Auto-send SMS when confirmed (manual or countdown) - only if BLE connected
    if (smsAlertEnabled && autoSmsOnConfirm && BleService.isConnected) {
      unawaited(sendSmsAlert());
    }

    resetAlert();
  }

  void cancelAlert() {
    // Immediately dismiss the alert UI — this must happen first.
    _alertCountdownTimer?.cancel();
    _alertCountdownTimer = null;
    _alertSecondsRemaining = 0;
    alertActive = false;
    deviceState = _monitoring ? 'Active' : 'IDLE';
    lastGpsLocation = null;
    lastMapsUrl = null;
    _lastFalseAlarmAt = DateTime.now();
    // Best-effort: tell the ESP32 to clear its fall state too.
    BleService.sendFallCancel();
    notifyListeners();

    // Fire-and-forget: log the false alarm after UI is already dismissed.
    final event = FallEvent(
      time: DateTime.now(),
      heartRate: heartRate,
      tiltAngle: tiltAngle,
      accelMag: accelMag,
      status: 'FALSE ALARM',
      gpsLocation: null,
    );
    fallHistory.insert(0, event);
    if (_firebaseReady) FirestoreService.saveFallEvent(event);
  }

  void resetAlert() {
    alertActive = false;
    deviceState = _monitoring ? 'Active' : 'IDLE';
    lastGpsLocation = null;
    lastMapsUrl = null;

    _alertCountdownTimer?.cancel();
    _alertCountdownTimer = null;
    _alertSecondsRemaining = 0;
    notifyListeners();
  }

  void clearHistory() {
    fallHistory.clear();
    if (_firebaseReady) FirestoreService.clearFallHistory();
    notifyListeners();
  }

  // ── SMS Methods ──

  void toggleSmsAlert() {
    smsAlertEnabled = !smsAlertEnabled;
    _saveBoolPref('sms_alert_enabled', smsAlertEnabled);
    _syncProfileToCloud();
    notifyListeners();
  }

  void toggleAutoSms() {
    autoSmsOnConfirm = !autoSmsOnConfirm;
    _saveBoolPref('auto_sms_on_confirm', autoSmsOnConfirm);
    _syncProfileToCloud();
    notifyListeners();
  }

  void _syncProfileToCloud() {
    if (!_firebaseReady) return;
    FirestoreService.saveProfile(
      patientName: patientName,
      patientPhone: patientPhone,
      patientEmail: patientEmail.isNotEmpty ? patientEmail : null,
      caregiverName: caregiverName,
      caregiverPhone: caregiverPhone,
      caregiverEmail: caregiverEmail.isNotEmpty ? caregiverEmail : null,
      smsAlertEnabled: smsAlertEnabled,
      autoSmsOnConfirm: autoSmsOnConfirm,
    );
    _syncMonitoringConfigToCloud();
  }

  void _syncMonitoringConfigToCloud() {
    if (!_firebaseReady) return;

    FirestoreService.saveMonitoringConfig(
      monitoringRole: _monitoringRole.wireValue,
      linkedParentDeviceId: _linkedParentDeviceId.isEmpty
          ? null
          : _linkedParentDeviceId,
      linkedChildDeviceId: _linkedChildDeviceId.isEmpty
          ? null
          : _linkedChildDeviceId,
      safeZoneLat: _safeZoneLat,
      safeZoneLon: _safeZoneLon,
      safeZoneRadius: _safeZoneRadiusMeters,
    );
  }

  Future<bool> sendSmsAlert() async {
    if (caregiverPhone.trim().isEmpty) {
      lastSmsError =
          'Please add a caregiver phone number in the Profile screen.';
      notifyListeners();
      return false;
    }

    // CHECK IF BLE IS CONNECTED - Only send SMS if BLE is active
    if (!BleService.isConnected) {
      lastSmsError = 'BLE device not connected. Cannot send SMS.';
      notifyListeners();
      return false;
    }

    _smsSending = true;
    lastSmsError = null;
    notifyListeners();

    final success = await SmsService.sendFallAlert(
      phoneNumber: caregiverPhone,
      patientName: patientName,
      heartRate: heartRate,
      tiltAngle: tiltAngle,
      fallTime: DateTime.now(),
      gpsLocation: lastGpsLocation,
      mapsUrl: lastMapsUrl,
      requireGps: true,
    );

    _smsSending = false;
    if (!success) {
      lastSmsError = 'Could not send SMS. Check device settings.';
    }
    notifyListeners();
    return success;
  }

  Future<bool> callCaregiver() async {
    return SmsService.callEmergency(phoneNumber: caregiverPhone);
  }

  // ── Cleanup ──

  @override
  void dispose() {
    _alertCountdownTimer?.cancel();
    _kidsPeriodicTimer?.cancel();
    _remoteKidsSub?.cancel();
    _phoneLocationSub?.cancel();
    TfliteFallDetectionService.instance.dispose();
    BleService.dispose();
    super.dispose();
  }
}

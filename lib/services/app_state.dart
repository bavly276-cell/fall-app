import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fall_event.dart';
import '../utils/constants.dart';
import 'ble_service.dart';
import 'sms_service.dart';
import 'location_service.dart';
import 'fall_detection_algorithm.dart';
import 'firestore_service.dart';

class AppState extends ChangeNotifier {
  // ── Theme ──
  bool isDarkMode = true;

  // ── Device State ──
  String deviceState = 'IDLE';
  double batteryLevel = 0;
  bool wifiConnected = false;
  bool wifiFallbackEnabled = true;
  String wifiSsid = '';
  String wifiPassword = '';
  String wifiServerUrl = '';
  double heartRate = 0.0;
  double spo2 = 0.0;
  double tiltAngle = 0.0;
  double accelMag = 1.0;
  bool alertActive = false;
  bool _monitoring = false;
  bool get isMonitoring => _monitoring;

  // ── Caregiver / Patient ──
  String _caregiverName = '';
  String _patientName = '';
  String _caregiverPhone = '';
  String _patientPhone = '';
  String _caregiverEmail = '';
  String _patientEmail = '';

  String? _patientPhotoBase64;

  bool _onboardingComplete = false;

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
  bool get isBleConnected => bleDeviceId != null;
  bool get isBleReconnecting => _bleReconnecting;

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
    _loadLocalPrefs();
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
      wifiFallbackEnabled =
          prefs.getBool('wifi_fallback_enabled') ?? wifiFallbackEnabled;
      wifiSsid = prefs.getString('wifi_ssid') ?? wifiSsid;
      wifiPassword = prefs.getString('wifi_password') ?? wifiPassword;
      wifiServerUrl = prefs.getString('wifi_server_url') ?? wifiServerUrl;
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

  /// Call after Firebase.initializeApp() completes.
  Future<void> initFirebase() async {
    _firebaseReady = true;

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
    }

    // Load fall history from cloud
    final history = await FirestoreService.loadFallHistory().timeout(
      const Duration(seconds: 6),
      onTimeout: () => <FallEvent>[],
    );
    if (history.isNotEmpty) {
      fallHistory = history;
    }

    notifyListeners();
  }

  // ── BLE Integration ──

  void _initBleCallbacks() {
    BleService.setConnectionCallback((connected, deviceName) {
      if (connected) {
        _bleReconnecting = false;

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

        // Optional support for standard smartwatch HR profile (0x180D/0x2A37).
        // ESP32 custom stream remains primary when active.
        BleService.subscribeStandardHeartRate(
          onHeartRate: (hr) => _handleStandardHeartRate(hr),
        );

        _monitoring = true;
        deviceState = 'MONITORING';
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

  // ── Sensor snapshot throttle ──
  DateTime? _lastSnapshotSync;
  DateTime? _lastUiNotifyAt;
  DateTime? _lastCustomSensorAt;
  Completer<bool?>? _pendingWifiStatus;
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

    if (data.wifiConnected != null) {
      if (wifiConnected != data.wifiConnected!) {
        wifiConnected = data.wifiConnected!;
        uiChanged = true;
      }
      if (_pendingWifiStatus != null && !_pendingWifiStatus!.isCompleted) {
        _pendingWifiStatus!.complete(data.wifiConnected!);
      }
    }
    lastSensorUpdate = DateTime.now();

    // Update battery from sensor stream
    if (data.battery >= 0) {
      final nextBattery = data.battery.toDouble();
      if ((nextBattery - batteryLevel).abs() >= 1.0) {
        batteryLevel = nextBattery;
        bleDeviceBattery = nextBattery;
        uiChanged = true;
      }
    }

    // Sync sensor snapshot to Firestore every 10 seconds
    if (_firebaseReady) {
      final now = DateTime.now();
      if (_lastSnapshotSync == null ||
          now.difference(_lastSnapshotSync!).inSeconds >= 10) {
        _lastSnapshotSync = now;
        FirestoreService.updateSensorSnapshot(
          heartRate: heartRate,
          spo2: spo2,
          tiltAngle: tiltAngle,
          accelMag: accelMag,
          battery: batteryLevel,
          deviceState: deviceState,
        );
      }
    }

    // Arduino sent FALL:1 flag in the sensor stream
    if (data.fallFlag && !alertActive) {
      _triggerFallAlert();
      return;
    }

    // Phone-side fall detection algorithm (redundant safety)
    if (!alertActive) {
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
      _notifyUiThrottled();
    }
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
    _triggerFallAlert();
  }

  void _triggerFallAlert() async {
    alertActive = true;
    deviceState = 'FALL_DETECTED';
    notifyListeners();

    // Fetch GPS immediately
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      lastGpsLocation = LocationService.formatPosition(pos);
      lastMapsUrl = LocationService.getMapsUrl(pos);
    }

    deviceState = 'ALERT_SENT';
    notifyListeners();

    // Auto-send SMS if enabled
    if (smsAlertEnabled && autoSmsOnConfirm) {
      sendSmsAlert();
    }
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
    bleDeviceBattery = battery;
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
    _fallAlgorithm.reset();
    notifyListeners();
  }

  void updateBleBattery(double battery) {
    if ((battery - bleDeviceBattery).abs() < 1.0) return;
    bleDeviceBattery = battery;
    batteryLevel = battery;
    notifyListeners();
  }

  // ── WiFi Settings ──

  void setWifiConnected(bool connected) {
    if (wifiConnected == connected) return;
    wifiConnected = connected;
    if (_pendingWifiStatus != null && !_pendingWifiStatus!.isCompleted) {
      _pendingWifiStatus!.complete(connected);
    }
    notifyListeners();
  }

  void toggleWifiFallback() {
    wifiFallbackEnabled = !wifiFallbackEnabled;
    _saveBoolPref('wifi_fallback_enabled', wifiFallbackEnabled);
    notifyListeners();
  }

  Future<void> saveWifiSettings({
    required String ssid,
    required String password,
    required String serverUrl,
  }) async {
    wifiSsid = ssid;
    wifiPassword = password;
    wifiServerUrl = serverUrl;
    await _saveStringPref('wifi_ssid', wifiSsid);
    await _saveStringPref('wifi_password', wifiPassword);
    await _saveStringPref('wifi_server_url', wifiServerUrl);
    notifyListeners();
  }

  Future<void> forgetWifiSettings() async {
    wifiSsid = '';
    wifiPassword = '';
    wifiConnected = false;
    await _saveStringPref('wifi_ssid', wifiSsid);
    await _saveStringPref('wifi_password', wifiPassword);
    notifyListeners();
  }

  Future<bool?> _awaitWifiStatusFromDevice({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _pendingWifiStatus = Completer<bool>();
    try {
      return await _pendingWifiStatus!.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      _pendingWifiStatus = null;
    }
  }

  /// Push currently saved WiFi settings to ESP32 over BLE.
  /// Returns true when payload is accepted by the BLE characteristic write.
  Future<bool> addWifiDeviceFromSavedSettings({
    bool verifyConnection = false,
  }) async {
    if (!isBleConnected) return false;
    if (wifiSsid.trim().isEmpty) return false;

    final sent = await BleService.sendWifiConfig(
      ssid: wifiSsid,
      password: wifiPassword,
      serverUrl: wifiServerUrl,
    );

    if (sent) {
      if (verifyConnection) {
        final status = await _awaitWifiStatusFromDevice();
        if (status == true) {
          wifiConnected = true;
        } else {
          await forgetWifiSettings();
          return false;
        }
      } else {
        // Device will report actual status in sensor stream (WIFI:0/1).
        // We optimistically show connected while waiting for telemetry refresh.
        wifiConnected = true;
      }
      notifyListeners();
    }

    return sent;
  }

  void disconnectWifiDevice() {
    wifiConnected = false;
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

  void confirmFall() async {
    // Get GPS for the record
    final pos = await LocationService.getCurrentPosition();
    String? gps;
    if (pos != null) {
      gps = LocationService.formatPosition(pos);
      lastMapsUrl = LocationService.getMapsUrl(pos);
    }

    final event = FallEvent(
      time: DateTime.now(),
      heartRate: heartRate,
      tiltAngle: tiltAngle,
      accelMag: accelMag,
      status: 'CONFIRMED',
      gpsLocation: gps,
    );
    fallHistory.insert(0, event);
    if (_firebaseReady) FirestoreService.saveFallEvent(event);

    // Auto-send SMS if enabled
    if (smsAlertEnabled && autoSmsOnConfirm) {
      sendSmsAlert();
    }
    resetAlert();
  }

  void cancelAlert() {
    final event = FallEvent(
      time: DateTime.now(),
      heartRate: heartRate,
      tiltAngle: tiltAngle,
      accelMag: accelMag,
      status: 'FALSE ALARM',
      gpsLocation: lastGpsLocation,
    );
    fallHistory.insert(0, event);
    if (_firebaseReady) FirestoreService.saveFallEvent(event);
    resetAlert();
  }

  void resetAlert() {
    alertActive = false;
    deviceState = _monitoring ? 'MONITORING' : 'IDLE';
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
  }

  Future<bool> sendSmsAlert() async {
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
    BleService.dispose();
    super.dispose();
  }
}

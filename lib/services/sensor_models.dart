/// Unified sensor data model that works across all platforms
library;
import 'dart:math';

class UnifiedSensorData {
  final String
  sourceType; // 'ESP32', 'AppleWatch', 'WearOS', 'Samsung', 'Generic'
  final String? deviceName;
  final double? heartRate;
  final double? spo2;
  final double? temperature;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  final double? latitude;
  final double? longitude;
  final int? battery;
  final DateTime timestamp;
  final Map<String, dynamic>? rawData;

  UnifiedSensorData({
    required this.sourceType,
    this.deviceName,
    this.heartRate,
    this.spo2,
    this.temperature,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.latitude,
    this.longitude,
    this.battery,
    DateTime? timestamp,
    this.rawData,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Acceleration magnitude (g-force)
  double get accelMagnitude {
    if (accelX == null || accelY == null || accelZ == null) return 0;
    return sqrt(accelX! * accelX! + accelY! * accelY! + accelZ! * accelZ!);
  }

  /// Gyro magnitude (deg/s)
  double get gyroMagnitude {
    if (gyroX == null || gyroY == null || gyroZ == null) return 0;
    return sqrt(gyroX! * gyroX! + gyroY! * gyroY! + gyroZ! * gyroZ!);
  }

  Map<String, dynamic> toJson() => {
    'sourceType': sourceType,
    'deviceName': deviceName,
    'heartRate': heartRate,
    'spo2': spo2,
    'temperature': temperature,
    'accelX': accelX,
    'accelY': accelY,
    'accelZ': accelZ,
    'gyroX': gyroX,
    'gyroY': gyroY,
    'gyroZ': gyroZ,
    'latitude': latitude,
    'longitude': longitude,
    'battery': battery,
    'timestamp': timestamp.toIso8601String(),
    'accelMagnitude': accelMagnitude,
    'gyroMagnitude': gyroMagnitude,
  };
}

/// Enum for sensor data source types
enum SensorSource {
  esp32('ESP32 BLE Device'),
  appleWatch('Apple Watch'),
  wearOs('Wear OS / Samsung'),
  huawei('Huawei Watch'),
  oraimo('Oraimo Watch'),
  x10Ultra('X10 Ultra Watch'),
  x8Ultra('X8 Ultra Watch'),
  fitbit('Fitbit'),
  garmin('Garmin'),
  xiaomi('Xiaomi / Mi Band'),
  realme('Realme Watch'),
  honor('Honor Watch'),
  oura('Oura Ring'),
  generic('Generic Smartwatch');

  final String displayName;
  const SensorSource(this.displayName);
}

/// Base interface for all sensor providers
abstract class SensorProvider {
  /// Get the source type identifier
  SensorSource get sourceType;

  /// Get display name
  String get displayName;

  /// Check if this provider is available on current platform
  Future<bool> isAvailable();

  /// Request necessary permissions
  Future<bool> requestPermissions();

  /// Start listening for sensor data
  Stream<UnifiedSensorData> startListening();

  /// Stop listening for sensor data
  Future<void> stopListening();

  /// Get current device info
  Future<Map<String, dynamic>?> getDeviceInfo();

  /// Check battery level
  Future<int?> getBatteryLevel();
}

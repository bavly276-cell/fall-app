import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  // Detection Thresholds (matching Arduino 3-stage algorithm)
  static const double impactThreshold = 3.0;
  static const double freefallThreshold = 0.4;
  static const double angleThreshold = 60.0;
  static const int alertLatencyMs = 500;
  static const double targetAccuracy = 0.90;
  static const double falseAlarmRate = 0.05;
  static const int hrStressThreshold = 100;

  // Default Sensor Values (no data yet)
  static const double defaultHeartRate = 0.0;
  static const double defaultTiltAngle = 0.0;
  static const double defaultAccelMag = 1.0;
  static const double defaultBatteryLevel = 0.0;

  // Simulated Fall Values
  static const double fallHeartRate = 128.0;
  static const double fallTiltAngle = 72.1;
  static const double fallAccelMag = 3.8;

  // Heart Rate Zones
  static const double hrNormalMax = 100.0;
  static const double hrElevatedMax = 120.0;

  // Battery Thresholds
  static const double batteryLowThreshold = 20.0;

  // Animation Durations
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animNormal = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 600);

  // Padding
  static const double paddingSm = 8.0;
  static const double paddingMd = 12.0;
  static const double paddingLg = 16.0;
  static const double paddingXl = 24.0;

  // SharedPreferences Keys
  static const String prefDarkMode = 'dark_mode';
  static const String prefPatientName = 'patient_name';
  static const String prefCaregiverName = 'caregiver_name';
  static const String prefCaregiverPhone = 'caregiver_phone';
  static const String prefProfilePhoto = 'profile_photo_base64';
  static const String prefOnboardingComplete = 'onboarding_complete';
  static const String prefFallHistory = 'fall_history';

  // Hardware Info
  static const String mcuName = 'ESP32-C3 Super Mini';
  static const String wifiModule = 'ESP32-C3 WiFi (built-in)';
  static const String hrSensor = 'MAX30102';
  static const String imuSensor = 'MPU6050';
  static const String bleModule = 'ESP32-C3 BLE (built-in)';
  static const String deviceId = 'ECU_FALL_SENSOR_01';
  static const String bleDeviceName = 'SafeWatch_ESP32C3';

  // BLE UUIDs (matching Arduino)
  static const String fallServiceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String fallCharUuid = '12345678-1234-1234-1234-123456789abd';
  static const String sensorCharUuid = '12345678-1234-1234-1234-123456789abe';
  static const String wifiConfigCharUuid =
      '12345678-1234-1234-1234-123456789abf';

  // Responsive Breakpoints
  static const double breakpointSm = 360;
  static const double breakpointMd = 600;
  static const double breakpointLg = 900;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

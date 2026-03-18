import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission management for all app features.
class PermissionManager {
  PermissionManager._();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Request all permissions needed by the app in one go.
  /// Returns a map of permission → granted status.
  static Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};

    if (!_isAndroid) {
      // Non-Android platforms do not support SMS/phone/BLE Android runtime permissions.
      return {
        'bluetoothScan': true,
        'bluetoothConnect': true,
        'location': true,
        'sms': true,
        'phone': true,
      };
    }

    // BLE permissions
    try {
      final bleStatuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      results['bluetoothScan'] =
          bleStatuses[Permission.bluetoothScan]?.isGranted ?? false;
      results['bluetoothConnect'] =
          bleStatuses[Permission.bluetoothConnect]?.isGranted ?? false;
    } catch (_) {
      results['bluetoothScan'] = false;
      results['bluetoothConnect'] = false;
    }

    // Location
    try {
      final locationStatus = await Permission.locationWhenInUse.request();
      results['location'] =
          locationStatus.isGranted || locationStatus.isLimited;
    } catch (_) {
      results['location'] = false;
    }

    // SMS
    try {
      final smsStatus = await Permission.sms.request();
      results['sms'] = smsStatus.isGranted;
    } catch (_) {
      results['sms'] = false;
    }

    // Phone
    try {
      final phoneStatus = await Permission.phone.request();
      results['phone'] = phoneStatus.isGranted;
    } catch (_) {
      results['phone'] = false;
    }

    debugPrint('Permission results: $results');
    return results;
  }

  /// Check if BLE permissions are granted.
  static Future<bool> hasBlePermissions() async {
    if (!_isAndroid) return true;
    final scan = await Permission.bluetoothScan.isGranted;
    final connect = await Permission.bluetoothConnect.isGranted;
    return scan && connect;
  }

  /// Check if location permission is granted.
  static Future<bool> hasLocationPermission() async {
    if (!_isAndroid) return true;
    return await Permission.locationWhenInUse.isGranted;
  }

  /// Check if SMS permission is granted.
  static Future<bool> hasSmsPermission() async {
    if (!_isAndroid) return true;
    return await Permission.sms.isGranted;
  }

  /// Request BLE-specific permissions only.
  static Future<bool> requestBlePermissions() async {
    if (!_isAndroid) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  /// Request location permission only.
  static Future<bool> requestLocationPermission() async {
    if (!_isAndroid) return true;
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted || status.isLimited;
  }

  /// Open app settings (e.g. if permissions permanently denied).
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission management for all app features.
class PermissionManager {
  PermissionManager._();

  // Many plugins (permission_handler, flutter_blue_plus, etc.) can throw if
  // permission requests overlap. Serialize all permission_handler requests.
  static Future<void> _permissionQueue = Future<void>.value();

  static Future<T> _runSerialized<T>(Future<T> Function() action) {
    final previous = _permissionQueue;
    final completer = Completer<void>();
    _permissionQueue = previous.whenComplete(() => completer.future);

    return previous.then((_) async {
      try {
        return await action();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Request all permissions needed by the app in one go.
  /// Returns a map of permission → granted status.
  static Future<Map<String, bool>> requestAllPermissions() async {
    return _runSerialized(() async {
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
    });
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
    return _runSerialized(() async {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    });
  }

  /// Request location permission only.
  static Future<bool> requestLocationPermission() async {
    if (!_isAndroid) return true;
    return _runSerialized(() async {
      final status = await Permission.locationWhenInUse.request();
      return status.isGranted || status.isLimited;
    });
  }

  /// Request SMS permission only (serialized to avoid plugin conflicts).
  static Future<bool> requestSmsPermission() async {
    if (!_isAndroid) return true;
    return _runSerialized(() async {
      // Check if already granted first
      if (await Permission.sms.isGranted) return true;

      final status = await Permission.sms.request();
      if (status.isGranted) return true;

      // If permanently denied, open app settings so user can enable manually
      if (status.isPermanentlyDenied) {
        debugPrint('SMS permission permanently denied — opening settings');
        await openAppSettings();
      }

      return false;
    });
  }

  /// Open app settings (e.g. if permissions permanently denied).
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

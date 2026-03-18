import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// GPS location service for embedding coordinates in fall alerts.
class LocationService {
  LocationService._();

  static Position? _lastPosition;

  /// The last known GPS position.
  static Position? get lastPosition => _lastPosition;

  /// Request location permissions. Returns true if granted.
  static Future<bool> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted || status.isLimited;
  }

  /// Check if location services are enabled on the device.
  static Future<bool> isLocationEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('Location service check failed: $e');
      return false;
    }
  }

  /// Get the current GPS position with error handling.
  /// Returns null if location cannot be determined.
  static Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        debugPrint('Location permission denied');
        return _lastPosition;
      }

      final serviceEnabled = await isLocationEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled');
        return _lastPosition;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _lastPosition = position;
      return position;
    } catch (e) {
      debugPrint('GPS position error: $e');
      return _lastPosition;
    }
  }

  /// Format a Position into a readable string.
  static String formatPosition(Position? position) {
    if (position == null) return 'Location unavailable';
    return '${position.latitude.toStringAsFixed(6)}, '
        '${position.longitude.toStringAsFixed(6)}';
  }

  /// Generate a Google Maps URL for the given position.
  static String? getMapsUrl(Position? position) {
    if (position == null) return null;
    return 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
  }
}

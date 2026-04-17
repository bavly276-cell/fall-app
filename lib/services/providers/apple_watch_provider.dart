import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../sensor_models.dart';

/// Apple Watch Provider - Specialized for watchOS devices via HealthKit
/// Uses platform channels to communicate with native Swift code
class AppleWatchProvider extends SensorProvider {
  static const platform = MethodChannel('com.safebrace/healthkit');
  static const eventChannel = EventChannel('com.safebrace/healthkit_sensors');

  StreamSubscription? _eventSubscription;
  final _dataController = StreamController<UnifiedSensorData>.broadcast();

  AppleWatchProvider() {
    if (!Platform.isIOS) {
      throw Exception('AppleWatchProvider only works on iOS');
    }
    debugPrint('AppleWatchProvider initialized');
  }

  @override
  SensorSource get sourceType => SensorSource.appleWatch;

  @override
  String get displayName => 'Apple Watch';

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final available =
          await platform.invokeMethod<bool>('isHealthKitAvailable') ?? false;
      return available;
    } catch (e) {
      debugPrint('Error checking HealthKit availability: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      final permissions = [
        'HKQuantityTypeIdentifierHeartRate',
        'HKQuantityTypeIdentifierOxygenSaturation',
        'HKQuantityTypeIdentifierBodyTemperature',
        'HKQuantityTypeIdentifierStepCount',
        'HKWorkoutTypeIdentifier',
      ];

      final granted =
          await platform.invokeMethod<bool>('requestHealthKitPermissions', {
            'permissions': permissions,
          }) ??
          false;

      if (granted) {
        debugPrint('HealthKit permissions granted');
      }
      return granted;
    } catch (e) {
      debugPrint('Error requesting HealthKit permissions: $e');
      return false;
    }
  }

  @override
  Stream<UnifiedSensorData> startListening() {
    _subscribeToHealthUpdates();
    return _dataController.stream;
  }

  @override
  Future<void> stopListening() async {
    try {
      await platform.invokeMethod('stopHealthUpdates');
      await _eventSubscription?.cancel();
      await _dataController.close();
      debugPrint('Apple Watch health monitoring stopped');
    } catch (e) {
      debugPrint('Error stopping health updates: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      final result = await platform.invokeMethod<Map>('getDeviceInfo');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return {
      'deviceName': 'Apple Watch',
      'platform': 'watchOS',
      'sourceType': sourceType.name,
    };
  }

  @override
  Future<int?> getBatteryLevel() async {
    try {
      final battery = await platform.invokeMethod<int>('getBatteryLevel');
      return battery;
    } catch (e) {
      debugPrint('Error getting battery level: $e');
      return null;
    }
  }

  void _subscribeToHealthUpdates() {
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        _processHealthEvent(event);
      },
      onError: (error) {
        debugPrint('Health stream error: $error');
      },
      onDone: () {
        debugPrint('Health stream closed');
      },
    );
  }

  void _processHealthEvent(dynamic event) {
    try {
      if (event is Map) {
        final sensorData = UnifiedSensorData(
          sourceType: sourceType.name,
          deviceName: 'Apple Watch',
          heartRate: (event['heartRate'] as num?)?.toDouble(),
          spo2: (event['oxygenSaturation'] as num?)?.toDouble(),
          temperature: (event['bodyTemperature'] as num?)?.toDouble(),
          battery: event['battery'] as int?,
          timestamp: event['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(event['timestamp'] as int)
              : DateTime.now(),
          rawData: Map<String, dynamic>.from(event),
        );
        _dataController.add(sensorData);
        debugPrint(
          'Health data received: HR=${sensorData.heartRate}, SpO2=${sensorData.spo2}',
        );
      }
    } catch (e) {
      debugPrint('Error processing health event: $e');
    }
  }

  /// Request background delivery for critical health metrics
  Future<bool> enableBackgroundUpdates() async {
    try {
      final enabled =
          await platform.invokeMethod<bool>('enableBackgroundUpdates') ?? false;
      return enabled;
    } catch (e) {
      debugPrint('Error enabling background updates: $e');
      return false;
    }
  }

  /// Fetch recent health samples for a specific data type
  Future<List<Map<String, dynamic>>> getRecentSamples({
    required String dataType,
    Duration duration = const Duration(hours: 1),
  }) async {
    try {
      final result = await platform.invokeMethod<List>('getRecentSamples', {
        'dataType': dataType,
        'minutesBack': duration.inMinutes,
      });
      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      debugPrint('Error fetching recent samples: $e');
      return [];
    }
  }
}

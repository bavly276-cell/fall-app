import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../sensor_models.dart';

/// Wear OS Provider - Specialized for Android Wear, Samsung Watch, and compatible smartwatches
/// Uses platform channels to communicate with native Android code
class WearOsProvider extends SensorProvider {
  static const platform = MethodChannel('com.safebrace/wearos');
  static const eventChannel = EventChannel('com.safebrace/wearos_sensors');

  StreamSubscription? _eventSubscription;
  final _dataController = StreamController<UnifiedSensorData>.broadcast();

  String? _connectedDeviceName;

  WearOsProvider() {
    if (!Platform.isAndroid) {
      throw Exception('WearOsProvider only works on Android');
    }
    debugPrint('WearOsProvider initialized');
  }

  @override
  SensorSource get sourceType => SensorSource.wearOs;

  @override
  String get displayName => 'Android Wear / Samsung Watch';

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final available =
          await platform.invokeMethod<bool>('isWearOsAvailable') ?? false;
      return available;
    } catch (e) {
      debugPrint('Error checking Wear OS availability: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      final granted =
          await platform.invokeMethod<bool>('requestWearPermissions') ?? false;
      if (granted) {
        debugPrint('Wear OS permissions granted');
      }
      return granted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Stream<UnifiedSensorData> startListening() {
    _subscribeToSensorUpdates();
    return _dataController.stream;
  }

  @override
  Future<void> stopListening() async {
    try {
      await platform.invokeMethod('stopSensorUpdates');
      await _eventSubscription?.cancel();
      await _dataController.close();
      debugPrint('Wear OS sensor updates stopped');
    } catch (e) {
      debugPrint('Error stopping sensor updates: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      final result = await platform.invokeMethod<Map>('getConnectedDeviceInfo');
      if (result != null) {
        _connectedDeviceName = result['deviceName'] as String?;
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return null;
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

  void _subscribeToSensorUpdates() {
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        _processSensorEvent(event);
      },
      onError: (error) {
        debugPrint('Sensor stream error: $error');
      },
      onDone: () {
        debugPrint('Sensor stream closed');
      },
    );
  }

  void _processSensorEvent(dynamic event) {
    try {
      if (event is Map) {
        final sensorData = UnifiedSensorData(
          sourceType: sourceType.name,
          deviceName: _connectedDeviceName ?? 'Android Watch',
          heartRate: (event['heartRate'] as num?)?.toDouble(),
          spo2: (event['spo2'] as num?)?.toDouble(),
          temperature: (event['temperature'] as num?)?.toDouble(),
          accelX: (event['accelX'] as num?)?.toDouble(),
          accelY: (event['accelY'] as num?)?.toDouble(),
          accelZ: (event['accelZ'] as num?)?.toDouble(),
          gyroX: (event['gyroX'] as num?)?.toDouble(),
          gyroY: (event['gyroY'] as num?)?.toDouble(),
          gyroZ: (event['gyroZ'] as num?)?.toDouble(),
          battery: event['battery'] as int?,
          timestamp: event['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(event['timestamp'] as int)
              : DateTime.now(),
          rawData: Map<String, dynamic>.from(event),
        );
        _dataController.add(sensorData);
      }
    } catch (e) {
      debugPrint('Error processing sensor event: $e');
    }
  }

  /// Get list of paired Wear OS devices
  Future<List<String>> getAvailableDevices() async {
    try {
      final result = await platform.invokeMethod<List>('getAvailableDevices');
      return List<String>.from(result ?? []);
    } catch (e) {
      debugPrint('Error getting available devices: $e');
      return [];
    }
  }

  /// Connect to a specific Wear OS device
  Future<bool> connectToDevice(String deviceName) async {
    try {
      final connected =
          await platform.invokeMethod<bool>('connectToDevice', {
            'deviceName': deviceName,
          }) ??
          false;
      return connected;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      return false;
    }
  }

  /// Disconnect from current device
  Future<bool> disconnectDevice() async {
    try {
      final disconnected =
          await platform.invokeMethod<bool>('disconnectDevice') ?? false;
      return disconnected;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
      return false;
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'sensor_models.dart';

/// Unified Smartwatch Sensor Service
/// Manages connections to multiple smartwatch platforms and provides
/// a single unified stream of sensor data regardless of source
class UnifiedSensorService extends ChangeNotifier {
  UnifiedSensorService._();
  static final UnifiedSensorService _instance = UnifiedSensorService._();
  factory UnifiedSensorService() => _instance;

  // Currently active provider
  SensorProvider? _activeProvider;

  // Unified sensor data stream
  final _sensorDataController = StreamController<UnifiedSensorData>.broadcast();
  Stream<UnifiedSensorData> get sensorDataStream =>
      _sensorDataController.stream;

  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _activeDeviceName;
  String? get activeDeviceName => _activeDeviceName;

  SensorSource? _activeSource;
  SensorSource? get activeSource => _activeSource;

  /// Get list of available sensor sources on this platform
  Future<List<SensorSource>> getAvailableSources() async {
    final available = <SensorSource>[];

    for (final source in SensorSource.values) {
      final provider = _getProviderForSource(source);
      if (provider != null && await provider.isAvailable()) {
        available.add(source);
      }
    }

    return available;
  }

  /// Get provider for a specific sensor source
  SensorProvider? _getProviderForSource(SensorSource source) {
    // TODO: Implement platform-specific providers
    // For now, this will be extended to support each platform
    switch (source) {
      case SensorSource.esp32:
        // Already handled by BleService
        return null;
      case SensorSource.appleWatch:
        // Will use HealthKitProvider (iOS only)
        return null;
      case SensorSource.wearOs:
        // Will use WearOsProvider (Android only)
        return null;
      case SensorSource.huawei:
      case SensorSource.oraimo:
      case SensorSource.x10Ultra:
      case SensorSource.x8Ultra:
      case SensorSource.xiaomi:
      case SensorSource.realme:
      case SensorSource.honor:
        // Vendor-specific providers can be added later
        return null;
      case SensorSource.fitbit:
      case SensorSource.garmin:
      case SensorSource.oura:
      case SensorSource.generic:
        // Will use HealthProvider via health package
        return null;
    }
  }

  /// Connect to a specific sensor source
  Future<bool> connectToSource(SensorSource source) async {
    try {
      // Stop current provider if any
      if (_activeProvider != null) {
        await _activeProvider!.stopListening();
      }

      _activeProvider = _getProviderForSource(source);
      if (_activeProvider == null) {
        debugPrint('No provider available for $source');
        return false;
      }

      // Request permissions
      if (!await _activeProvider!.requestPermissions()) {
        debugPrint('Permissions denied for $source');
        return false;
      }

      // Get device info
      final deviceInfo = await _activeProvider!.getDeviceInfo();
      _activeDeviceName = deviceInfo?['deviceName'] as String?;
      _activeSource = source;

      // Start listening to sensor data
      _activeProvider!.startListening().listen(
        (data) {
          _sensorDataController.add(data);
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Sensor data error: $error');
          _isConnected = false;
          notifyListeners();
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
      );

      _isConnected = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to connect to $source: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from current source
  Future<void> disconnect() async {
    if (_activeProvider != null) {
      await _activeProvider!.stopListening();
    }
    _isConnected = false;
    _activeProvider = null;
    _activeSource = null;
    _activeDeviceName = null;
    notifyListeners();
  }

  /// Get current battery level
  Future<int?> getBatteryLevel() async {
    if (_activeProvider == null) return null;
    return _activeProvider!.getBatteryLevel();
  }

  /// List all connected devices for the current source
  /// This will be overridden in platform-specific implementations
  Future<List<Map<String, String>>> getScanResults() async {
    return [];
  }

  @override
  void dispose() {
    _sensorDataController.close();
    super.dispose();
  }
}

final unifiedSensorService = UnifiedSensorService();

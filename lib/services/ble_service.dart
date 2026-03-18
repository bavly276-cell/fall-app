import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fall_detection_algorithm.dart';

/// Callback type for connection state changes.
typedef BleConnectionCallback =
    void Function(bool connected, String? deviceName);

/// Callback for real-time parsed sensor data.
typedef BleSensorDataCallback = void Function(SensorData data);
typedef BleHeartRateCallback = void Function(int heartRate);

/// Production BLE service with scanning, connecting, battery reading,
/// real-time sensor data streaming, fall detection notifications,
/// auto-reconnection on disconnect, and persistent state monitoring.
class BleService {
  BleService._();

  static BluetoothDevice? _connectedDevice;
  static StreamSubscription<BluetoothConnectionState>? _connectionSub;
  static StreamSubscription<List<int>>? _fallNotifySub;
  static StreamSubscription<List<int>>? _sensorNotifySub;
  static StreamSubscription<List<int>>? _hrNotifySub;
  static BleConnectionCallback? _onConnectionChanged;
  static BleSensorDataCallback? _onSensorData;
  static BleHeartRateCallback? _onHeartRate;
  static Timer? _batteryPollTimer;
  static Timer? _reconnectTimer;
  static bool _autoReconnectEnabled = true;
  static int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static bool _intentionalDisconnect = false;
  static List<BluetoothService>? _cachedServices;

  // Custom Fall Detection Service UUIDs (matching Arduino)
  static const String fallServiceUuid = '12345678-1234-1234-1234-123456789abc';
  static const String fallCharUuid = '12345678-1234-1234-1234-123456789abd';
  static const String sensorCharUuid = '12345678-1234-1234-1234-123456789abe';
  static const String wifiConfigCharUuid =
      '12345678-1234-1234-1234-123456789abf';

  // Standard BLE UUIDs
  static const String batteryServiceUuid = '180f';
  static const String batteryCharUuid = '2a19';
  static const String heartRateServiceUuid = '180d';
  static const String heartRateMeasurementCharUuid = '2a37';

  static BluetoothDevice? get connectedDevice => _connectedDevice;
  static bool get isConnected => _connectedDevice != null;
  static bool get autoReconnectEnabled => _autoReconnectEnabled;
  static int get reconnectAttempts => _reconnectAttempts;

  /// Register a callback for connection state changes.
  static void setConnectionCallback(BleConnectionCallback? cb) {
    _onConnectionChanged = cb;
  }

  /// Register a callback for real-time sensor data from the Arduino.
  static void setSensorDataCallback(BleSensorDataCallback? cb) {
    _onSensorData = cb;
  }

  /// Register callback for standard BLE Heart Rate profile devices.
  static void setHeartRateCallback(BleHeartRateCallback? cb) {
    _onHeartRate = cb;
  }

  /// Enable or disable auto-reconnect.
  static void setAutoReconnect(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;
    }
  }

  /// Request all required BLE/location permissions.
  static Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  /// Check if Bluetooth adapter is on.
  static Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('BLE adapter check failed: $e');
      return false;
    }
  }

  /// Stream of adapter state changes.
  static Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// Start scanning for BLE devices.
  static Stream<List<ScanResult>> scanDevices({
    Duration timeout = const Duration(seconds: 12),
  }) {
    FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);
    return FlutterBluePlus.scanResults;
  }

  /// Stop scanning.
  static Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Stop scan error: $e');
    }
  }

  /// Whether currently scanning.
  static Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Connect to a BLE device. Returns true on success.
  static Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // Disconnect existing device first
      if (_connectedDevice != null) {
        _intentionalDisconnect = true;
        await disconnect();
      }

      _intentionalDisconnect = false;
      _reconnectAttempts = 0;
      _cachedServices = null;

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = device;

      // Discover and cache services immediately
      _cachedServices = await device.discoverServices();
      debugPrint('BLE: Discovered ${_cachedServices!.length} services');

      // Monitor connection state for real-time disconnect detection
      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        debugPrint('BLE state: $state for ${device.platformName}');
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      debugPrint(
        'BLE: Connected to ${device.platformName} [${device.remoteId}]',
      );
      _onConnectionChanged?.call(true, device.platformName);
      return true;
    } catch (e) {
      debugPrint('BLE connect failed: $e');
      _connectedDevice = null;
      _cachedServices = null;
      return false;
    }
  }

  static void _handleDisconnect() {
    final deviceName = _connectedDevice?.platformName;
    final device = _connectedDevice;
    debugPrint('BLE: Device disconnected ($deviceName)');

    _fallNotifySub?.cancel();
    _sensorNotifySub?.cancel();
    _hrNotifySub?.cancel();
    _batteryPollTimer?.cancel();
    _connectionSub?.cancel();
    _connectedDevice = null;
    _cachedServices = null;

    _onConnectionChanged?.call(false, deviceName);

    // Auto-reconnect if enabled and disconnect wasn't intentional
    if (_autoReconnectEnabled &&
        !_intentionalDisconnect &&
        device != null &&
        _reconnectAttempts < _maxReconnectAttempts) {
      _startAutoReconnect(device);
    }
  }

  /// Auto-reconnect with exponential backoff.
  static void _startAutoReconnect(BluetoothDevice device) {
    _reconnectTimer?.cancel();

    // Exponential backoff: 2s, 4s, 8s, 16s, 30s max
    final delaySeconds = (2 << _reconnectAttempts).clamp(2, 30);
    _reconnectAttempts++;
    debugPrint(
      'BLE: Auto-reconnect attempt $_reconnectAttempts in ${delaySeconds}s',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_connectedDevice != null || _intentionalDisconnect) return;

      final btOn = await isBluetoothOn();
      if (!btOn) {
        debugPrint('BLE: Bluetooth off, skipping reconnect');
        if (_reconnectAttempts < _maxReconnectAttempts) {
          _startAutoReconnect(device);
        }
        return;
      }

      debugPrint('BLE: Attempting reconnect to ${device.platformName}...');
      final success = await connectToDevice(device);
      if (!success && _reconnectAttempts < _maxReconnectAttempts) {
        _startAutoReconnect(device);
      }
    });
  }

  /// Intentionally disconnect from the current device.
  static Future<void> disconnect() async {
    try {
      _intentionalDisconnect = true;
      _reconnectTimer?.cancel();
      _fallNotifySub?.cancel();
      _sensorNotifySub?.cancel();
      _hrNotifySub?.cancel();
      _batteryPollTimer?.cancel();
      _connectionSub?.cancel();
      _reconnectAttempts = 0;
      final device = _connectedDevice;
      final deviceName = device?.platformName;
      _connectedDevice = null;
      _cachedServices = null;
      if (device != null) {
        await device.disconnect().timeout(const Duration(seconds: 5));
      }
      _onConnectionChanged?.call(false, deviceName);
    } catch (e) {
      debugPrint('BLE disconnect error: $e');
      _onConnectionChanged?.call(false, null);
    }
  }

  /// Discover services on the connected device (uses cache if available).
  static Future<List<BluetoothService>> discoverServices() async {
    if (_connectedDevice == null) return [];
    if (_cachedServices != null) return _cachedServices!;
    try {
      _cachedServices = await _connectedDevice!.discoverServices();
      return _cachedServices!;
    } catch (e) {
      debugPrint('Service discovery failed: $e');
      return [];
    }
  }

  /// Read battery level (0-100) from standard BLE Battery Service.
  /// Returns -1 if not available.
  static Future<int> readBatteryLevel() async {
    if (_connectedDevice == null) return -1;
    try {
      final services = await discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          batteryServiceUuid,
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(batteryCharUuid)) {
              final value = await char.read();
              if (value.isNotEmpty) {
                return value[0].clamp(0, 100);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Battery read failed: $e');
    }
    return -1;
  }

  /// Subscribe to the real-time sensor data stream from Arduino.
  /// Data format: "HR:72,TILT:3.2,ACC:1.02,BATT:87,FALL:0"
  static Future<void> subscribeSensorData({
    required void Function(SensorData data) onData,
  }) async {
    if (_connectedDevice == null) return;
    try {
      final services = await discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          fallServiceUuid.toLowerCase(),
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              sensorCharUuid.toLowerCase(),
            )) {
              await char.setNotifyValue(true);
              _sensorNotifySub?.cancel();
              _sensorNotifySub = char.onValueReceived.listen((bytes) {
                if (bytes.isEmpty) return;
                final raw = utf8.decode(bytes, allowMalformed: true);
                final parsed = SensorData.parse(raw);
                if (parsed != null) {
                  onData(parsed);
                  _onSensorData?.call(parsed);
                }
              });
              debugPrint('BLE: Subscribed to sensor data stream');
              return;
            }
          }
        }
      }
      debugPrint('BLE: Sensor data characteristic not found');
    } catch (e) {
      debugPrint('Sensor data subscribe failed: $e');
    }
  }

  /// Subscribe to fall detection notifications from Arduino.
  /// Binary format: [fallFlag, hrHigh, hrLow, tiltAngle, accelMag*10]
  static Future<void> subscribeFallDetection({
    required void Function(List<int> data) onFallData,
  }) async {
    if (_connectedDevice == null) return;
    try {
      final services = await discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          fallServiceUuid.toLowerCase(),
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              fallCharUuid.toLowerCase(),
            )) {
              await char.setNotifyValue(true);
              _fallNotifySub?.cancel();
              _fallNotifySub = char.onValueReceived.listen(onFallData);
              debugPrint('BLE: Subscribed to fall alert notifications');
              return;
            }
          }
        }
      }
      debugPrint('BLE: Fall detection characteristic not found');
    } catch (e) {
      debugPrint('Fall notification subscribe failed: $e');
    }
  }

  /// Subscribe to standard BLE Heart Rate Measurement (0x2A37).
  /// Works with many smartwatches and chest straps.
  static Future<void> subscribeStandardHeartRate({
    required void Function(int heartRate) onHeartRate,
  }) async {
    if (_connectedDevice == null) return;
    try {
      final services = await discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          heartRateServiceUuid,
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              heartRateMeasurementCharUuid,
            )) {
              await char.setNotifyValue(true);
              _hrNotifySub?.cancel();
              _hrNotifySub = char.onValueReceived.listen((bytes) {
                final hr = _parseHeartRateMeasurement(bytes);
                if (hr != null && hr > 0) {
                  onHeartRate(hr);
                  _onHeartRate?.call(hr);
                }
              });
              debugPrint('BLE: Subscribed to standard heart-rate measurement');
              return;
            }
          }
        }
      }
      debugPrint('BLE: Standard heart-rate characteristic not found');
    } catch (e) {
      debugPrint('Standard HR subscribe failed: $e');
    }
  }

  static int? _parseHeartRateMeasurement(List<int> bytes) {
    if (bytes.length < 2) return null;
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) != 0;
    if (isUint16) {
      if (bytes.length < 3) return null;
      return bytes[1] | (bytes[2] << 8);
    }
    return bytes[1];
  }

  /// Push WiFi settings to ESP32 over BLE writable characteristic.
  /// Message format: "SSID=...;PASS=...;URL=..."
  static Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    required String serverUrl,
  }) async {
    if (_connectedDevice == null) return false;

    try {
      final services = await discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          fallServiceUuid.toLowerCase(),
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              wifiConfigCharUuid.toLowerCase(),
            )) {
              final payload = 'SSID=$ssid;PASS=$password;URL=$serverUrl';
              await char.write(utf8.encode(payload), withoutResponse: false);
              debugPrint('BLE: WiFi config sent to device');
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('BLE WiFi config send failed: $e');
    }

    return false;
  }

  /// Start polling battery level every [interval].
  static void startBatteryPolling({
    Duration interval = const Duration(seconds: 30),
    required void Function(int level) onBattery,
  }) {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(interval, (_) async {
      if (_connectedDevice == null) {
        _batteryPollTimer?.cancel();
        return;
      }
      final level = await readBatteryLevel();
      if (level >= 0) {
        onBattery(level);
      }
    });
  }

  /// Get the RSSI of the connected device.
  static Future<int> readRssi() async {
    if (_connectedDevice == null) return -100;
    try {
      return await _connectedDevice!.readRssi();
    } catch (e) {
      return -100;
    }
  }

  /// Clean up all resources.
  static void dispose() {
    _reconnectTimer?.cancel();
    _batteryPollTimer?.cancel();
    _fallNotifySub?.cancel();
    _sensorNotifySub?.cancel();
    _hrNotifySub?.cancel();
    _connectionSub?.cancel();
    _reconnectAttempts = 0;
    _cachedServices = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fall_detection_algorithm.dart';
import '../models/smartwatch_capability_report.dart';
import 'permission_manager.dart';

/// Callback type for connection state changes.
typedef BleConnectionCallback =
    void Function(bool connected, String? deviceName);

/// Callback for real-time parsed sensor data.
typedef BleSensorDataCallback = void Function(SensorData data);
typedef BleHeartRateCallback = void Function(int heartRate);
typedef BleGpsDataCallback =
    void Function(double? lat, double? lon, bool valid);
typedef BleTemperatureCallback = void Function(double temp);
typedef BleSpO2Callback = void Function(double spo2);

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
  static StreamSubscription<List<int>>? _spo2NotifySub;
  static StreamSubscription<List<int>>? _tempNotifySub;
  static StreamSubscription<List<int>>? _gpsNotifySub;
  static BleConnectionCallback? _onConnectionChanged;
  static BleSensorDataCallback? _onSensorData;
  static BleHeartRateCallback? _onHeartRate;
  static BleSpO2Callback? _onSpO2;
  static BleTemperatureCallback? _onTemp;
  static BleGpsDataCallback? _onGpsData;
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
  static const String gpsCharUuid =
      '12345678-1234-1234-1234-123456789af0';

  // Standard BLE UUIDs
  static const String batteryServiceUuid = '180f';
  static const String batteryCharUuid = '2a19';
  
  static const String heartRateServiceUuid = '180d';
  static const String heartRateMeasurementCharUuid = '2a37';

  static const String pulseOximeterServiceUuid = '1822';
  static const String spo2ContinuousCharUuid = '2a5f';
  static const String spo2SpotCharUuid = '2a5e';

  static const String healthThermometerServiceUuid = '1809';
  static const String temperatureMeasurementCharUuid = '2a1c';

  static BluetoothDevice? get connectedDevice => _connectedDevice;
  static bool get isConnected => _connectedDevice != null;
  static bool get autoReconnectEnabled => _autoReconnectEnabled;
  static int get reconnectAttempts => _reconnectAttempts;

  /// Attempt to auto-connect to a previously known device (by remoteId.str).
  ///
  /// This is used on app startup so the user doesn't need to scan each time.
  /// Returns true if connected.
  static Future<bool> autoConnectToDeviceId(
    String deviceId, {
    Duration scanTimeout = const Duration(seconds: 10),
    bool requestPermissionsIfNeeded = true,
  }) async {
    if (deviceId.trim().isEmpty) return false;

    // Already connected to this device in-process.
    if (_connectedDevice != null &&
        _connectedDevice!.remoteId.str == deviceId) {
      return true;
    }

    if (requestPermissionsIfNeeded) {
      final hasPerms = await requestPermissions();
      if (!hasPerms) return false;
    } else {
      final hasPerms = await hasRequiredPermissions();
      if (!hasPerms) return false;
    }

    final btOn = await isBluetoothOn();
    if (!btOn) return false;

    // Android improvement: if the device is already connected at the OS level,
    // fetch it directly (faster than scanning) and connect it to *this app*.
    try {
      final sys = await FlutterBluePlus.systemDevices([Guid(fallServiceUuid)]);
      for (final d in sys) {
        if (d.remoteId.str == deviceId) {
          debugPrint('BLE: Auto-connect found system device ${d.remoteId.str}');
          return await connectToDevice(d);
        }
      }
    } catch (e) {
      debugPrint('BLE auto-connect systemDevices failed: $e');
    }

    // Scan for the known device and connect once found.
    final completer = Completer<BluetoothDevice?>();
    StreamSubscription<List<ScanResult>>? sub;
    Timer? timer;

    void finish(BluetoothDevice? device) {
      if (completer.isCompleted) return;
      completer.complete(device);
      timer?.cancel();
      sub?.cancel();
      stopScan();
    }

    timer = Timer(scanTimeout, () => finish(null));

    try {
      sub = scanDevices(timeout: scanTimeout).listen((results) {
        for (final r in results) {
          if (r.device.remoteId.str == deviceId) {
            finish(r.device);
            return;
          }
        }
      });
    } catch (e) {
      debugPrint('BLE auto-connect scan failed: $e');
      finish(null);
    }

    final device = await completer.future;
    if (device == null) return false;
    return await connectToDevice(device);
  }

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

  /// Register callback for GPS data from the Arduino (NEW).
  static void setGpsDataCallback(BleGpsDataCallback? cb) {
    _onGpsData = cb;
  }

  /// Register callback for standard BLE Pulse Oximeter (SpO2).
  static void setSpO2Callback(BleSpO2Callback? cb) {
    _onSpO2 = cb;
  }

  /// Register callback for standard BLE Health Thermometer.
  static void setTemperatureCallback(BleTemperatureCallback? cb) {
    _onTemp = cb;
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
    try {
      return await PermissionManager.requestBlePermissions();
    } catch (e) {
      debugPrint('BLE permission request failed: $e');
      return false;
    }
  }

  /// Check if BLE/location permissions are already granted.
  static Future<bool> hasRequiredPermissions() async {
    try {
      final scan = await Permission.bluetoothScan.isGranted;
      final connect = await Permission.bluetoothConnect.isGranted;
      final loc = await Permission.locationWhenInUse.isGranted;
      return scan && connect && loc;
    } catch (e) {
      debugPrint('BLE permission check failed: $e');
      return false;
    }
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
    _spo2NotifySub?.cancel();
    _tempNotifySub?.cancel();
    _gpsNotifySub?.cancel();
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
      _spo2NotifySub?.cancel();
      _tempNotifySub?.cancel();
      _gpsNotifySub?.cancel();
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

  /// Inspect the connected device and infer which metrics it supports.
  static Future<SmartwatchCapabilityReport?> inspectConnectedDevice() async {
    if (_connectedDevice == null) return null;
    try {
      final services = await discoverServices();
      return SmartwatchCapabilityReport.fromServices(
        device: _connectedDevice!,
        services: services,
      );
    } catch (e) {
      debugPrint('Capability inspection failed: $e');
      return null;
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

  /// Subscribe to all standard health vitals available on the device.
  /// This enables a universal "Discovery" of HR, SpO2, and Temperature.
  static Future<void> subscribeUniversalVitals({
    void Function(int hr)? onHeartRate,
    void Function(double spo2)? onSpO2,
    void Function(double temp)? onTemp,
  }) async {
    if (_connectedDevice == null) return;
    try {
      final services = await discoverServices();
      for (final service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();

        // 1. Heart Rate
        if (serviceUuid.contains(heartRateServiceUuid)) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              heartRateMeasurementCharUuid,
            )) {
              await char.setNotifyValue(true);
              _hrNotifySub?.cancel();
              _hrNotifySub = char.onValueReceived.listen((bytes) {
                final hr = _parseHeartRateMeasurement(bytes);
                if (hr != null && hr > 0) {
                  onHeartRate?.call(hr);
                  _onHeartRate?.call(hr);
                }
              });
              debugPrint('Universal BLE: Listening to standard HR');
            }
          }
        }

        // 2. Pulse Oximeter (SpO2)
        if (serviceUuid.contains(pulseOximeterServiceUuid)) {
          for (final char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();
            if (charUuid.contains(spo2ContinuousCharUuid) ||
                charUuid.contains(spo2SpotCharUuid)) {
              await char.setNotifyValue(true);
              _spo2NotifySub?.cancel();
              _spo2NotifySub = char.onValueReceived.listen((bytes) {
                final val = _parseSpO2(bytes);
                if (val != null) {
                  onSpO2?.call(val);
                  _onSpO2?.call(val);
                }
              });
              debugPrint('Universal BLE: Listening to standard SpO2');
            }
          }
        }

        // 3. Health Thermometer (Temp)
        if (serviceUuid.contains(healthThermometerServiceUuid)) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              temperatureMeasurementCharUuid,
            )) {
              await char.setNotifyValue(true);
              _tempNotifySub?.cancel();
              _tempNotifySub = char.onValueReceived.listen((bytes) {
                final val = _parseTemp(bytes);
                if (val != null) {
                  onTemp?.call(val);
                  _onTemp?.call(val);
                }
              });
              debugPrint('Universal BLE: Listening to standard Temp');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Universal vitals subscription failed: $e');
    }
  }

  static double? _parseSpO2(List<int> bytes) {
    if (bytes.length < 2) return null;
    // Standard PLX Continuous Measurement: Flag(1), SpO2(2, SFLOAT), PR(2, SFLOAT)
    // For many simple devices, it's just raw percentage in byte 1 or 2
    try {
      final flags = bytes[0];
      int offset = 1;
      // Many fitness bands just output byte 1 as the SpO2 % for simplicity
      // but let's follow standard SFLOAT if bits match.
      if ((flags & 0x01) != 0) {
         // SpO2 is uint16/sfloat at offset 1
         final raw = bytes[offset] | (bytes[offset+1] << 8);
         return raw.toDouble();
      }
      return bytes[1].toDouble();
    } catch (_) {
      return null;
    }
  }

  static double? _parseTemp(List<int> bytes) {
    if (bytes.length < 5) return null;
    // Standard HTM: Flags(1), Temp(4, FLOAT/IEEE-11073)
    try {
      final flags = bytes[0]; // Bit 0: 0=C, 1=F
      // IEEE-11073 FLOAT (32-bit): exponent (8-bit signed) + mantissa (24-bit signed)
      // For now, assume a simpler byte mapping common in generic sensors
      final mantissa = bytes[1] | (bytes[2] << 8) | (bytes[3] << 16);
      int exponent = bytes[4];
      if (exponent > 127) exponent -= 256;
      
      double val = mantissa * pow(10, exponent).toDouble();
      if ((flags & 0x01) != 0) {
        // Convert F to C if needed
        val = (val - 32) * 5 / 9;
      }
      return val;
    } catch (_) {
      return null;
    }
  }

  /// Push WiFi settings to ESP32 over BLE writable characteristic.
  /// Message format: "SSID=...;PASS=...;URL=..."
  /// Send a remote cancel command for an active fall alert.
  /// The firmware listens on the fall characteristic for any
  /// write and resets its internal fall state when received.
  static Future<bool> sendFallCancel() async {
    if (_connectedDevice == null) return false;

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
              await char.write(const <int>[0x00], withoutResponse: true);
              debugPrint('BLE: Sent remote fall cancel command');
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('BLE fall cancel send failed: $e');
    }

    return false;
  }

  /// Push WiFi settings payload to device over BLE.
  /// Current firmware may ignore this if WiFi config characteristic is absent.
  static Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    required String serverUrl,
  }) async {
    if (_connectedDevice == null) return false;
    try {
      final services = await discoverServices();
      final payload = utf8.encode('SSID=$ssid;PASS=$password;URL=$serverUrl');

      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          fallServiceUuid.toLowerCase(),
        )) {
          for (final char in service.characteristics) {
            final props = char.properties;
            if (props.write || props.writeWithoutResponse) {
              await char.write(
                payload,
                withoutResponse: props.writeWithoutResponse,
              );
              debugPrint('BLE: WiFi config payload sent');
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('BLE sendWifiConfig failed: $e');
    }
    return false;
  }

  /// Subscribe to GPS data notifications from the Arduino (NEW).
  static Future<void> subscribeGpsData({
    required void Function(double? lat, double? lon, bool valid) onGpsData,
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
              gpsCharUuid.toLowerCase(),
            )) {
              await char.setNotifyValue(true);
              _gpsNotifySub?.cancel();
              _gpsNotifySub = char.onValueReceived.listen((data) {
                try {
                  final payload = String.fromCharCodes(data);
                  debugPrint('BLE GPS data: $payload');

                  double? lat;
                  double? lon;
                  bool valid = false;

                  if (payload.contains('VALID:1')) {
                    valid = true;
                    // Parse: "LAT:XXXXX.XXXXX,LON:XXXXX.XXXXX,VALID:1"
                    final latMatch = RegExp(
                      r'LAT:([-\d.]+)',
                    ).firstMatch(payload);
                    final lonMatch = RegExp(
                      r'LON:([-\d.]+)',
                    ).firstMatch(payload);

                    if (latMatch != null && lonMatch != null) {
                      lat = double.tryParse(latMatch.group(1) ?? '');
                      lon = double.tryParse(lonMatch.group(1) ?? '');
                    }
                  }

                  onGpsData(lat, lon, valid);
                  _onGpsData?.call(lat, lon, valid);
                } catch (e) {
                  debugPrint('GPS data parse error: $e');
                }
              });
              debugPrint('BLE: Subscribed to GPS data notifications');
              return;
            }
          }
        }
      }
      debugPrint('BLE: GPS characteristic not found');
    } catch (e) {
      debugPrint('GPS subscription failed: $e');
    }
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
    _spo2NotifySub?.cancel();
    _tempNotifySub?.cancel();
    _connectionSub?.cancel();
    _reconnectAttempts = 0;
    _cachedServices = null;
  }
}

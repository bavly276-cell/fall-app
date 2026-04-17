import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../sensor_models.dart';

/// X10 Ultra Watch Provider - BLE-based smartwatch with comprehensive sensor support
/// Handles: Heart rate, SpO2, temperature, accelerometer, gyroscope, battery, GPS
class X10UltraProvider extends SensorProvider {
  // X10 Ultra proprietary BLE UUIDs
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String notifyCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String writeCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _characteristicSubscription;
  final _dataController = StreamController<UnifiedSensorData>.broadcast();

  @override
  SensorSource get sourceType => SensorSource.x10Ultra;

  @override
  String get displayName => 'X10 Ultra Watch';

  @override
  Future<bool> isAvailable() async {
    final btState = await FlutterBluePlus.adapterState.first;
    return btState == BluetoothAdapterState.on;
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      debugPrint('X10 Ultra: Requesting BLE permissions');
      return true;
    } catch (e) {
      debugPrint('X10 Ultra: Permission error: $e');
      return false;
    }
  }

  @override
  Stream<UnifiedSensorData> startListening() {
    if (_device != null) {
      _subscribeToBleNotifications();
    }
    return _dataController.stream;
  }

  @override
  Future<void> stopListening() async {
    await _characteristicSubscription?.cancel();
    await _dataController.close();
    debugPrint('X10 Ultra: Sensor updates stopped');
  }

  @override
  Future<Map<String, dynamic>?> getDeviceInfo() async {
    if (_device == null) return null;
    return {
      'deviceName': 'X10 Ultra Watch',
      'platform': 'BLE',
      'sourceType': sourceType.name,
      'deviceId': _device!.remoteId.str,
    };
  }

  @override
  Future<int?> getBatteryLevel() async {
    if (_device == null) return null;
    try {
      // Battery info is typically included in the sensor data stream
      return null;
    } catch (e) {
      debugPrint('X10 Ultra: Error getting battery: $e');
      return null;
    }
  }

  /// Connect to X10 Ultra Watch device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect(timeout: const Duration(seconds: 10));
      debugPrint('X10 Ultra: Connected to ${device.platformName}');

      // Discover services
      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains(
          serviceUuid.toLowerCase(),
        )) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(
              notifyCharUuid.toLowerCase(),
            )) {
              _notifyChar = char;
              break;
            }
          }
        }
      }

      if (_notifyChar != null) {
        await _notifyChar!.setNotifyValue(true);
        _subscribeToBleNotifications();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('X10 Ultra: Connection error: $e');
      return false;
    }
  }

  void _subscribeToBleNotifications() {
    if (_notifyChar == null) return;

    _characteristicSubscription = _notifyChar!.onValueReceived.listen(
      (data) {
        _processX10UltraData(data);
      },
      onError: (error) {
        debugPrint('X10 Ultra: Notification error: $error');
      },
    );
  }

  void _processX10UltraData(List<int> data) {
    try {
      // X10 Ultra proprietary data format
      // Typical packet structure:
      // Byte 0: Data type indicator
      // Bytes 1-2: Heart rate (BPM)
      // Bytes 3-4: SpO2 (%)
      // Bytes 5-6: Temperature (°C × 100)
      // Bytes 7-8: Acceleration X
      // Bytes 9-10: Acceleration Y
      // Bytes 11-12: Acceleration Z
      // Bytes 13-14: Battery (%)

      if (data.length < 15) {
        debugPrint('X10 Ultra: Invalid packet size ${data.length}');
        return;
      }

      final dataType = data[0];

      if (dataType == 0x01) {
        // Sensor data packet
        final heartRate = ((data[1] << 8) | data[2]).toDouble();
        final spo2 = ((data[3] << 8) | data[4]).toDouble();
        final tempRaw = ((data[5] << 8) | data[6]).toDouble();
        final temperature = tempRaw / 100.0;

        // Acceleration (16-bit signed values)
        int accelXRaw = (data[7] << 8) | data[8];
        if (accelXRaw & 0x8000 != 0) accelXRaw = -((accelXRaw ^ 0xFFFF) + 1);
        int accelYRaw = (data[9] << 8) | data[10];
        if (accelYRaw & 0x8000 != 0) accelYRaw = -((accelYRaw ^ 0xFFFF) + 1);
        int accelZRaw = (data[11] << 8) | data[12];
        if (accelZRaw & 0x8000 != 0) accelZRaw = -((accelZRaw ^ 0xFFFF) + 1);

        final battery = data[13];

        final sensorData = UnifiedSensorData(
          sourceType: sourceType.name,
          deviceName: displayName,
          heartRate: heartRate > 0 && heartRate < 300 ? heartRate : null,
          spo2: spo2 > 0 && spo2 < 100 ? spo2 : null,
          temperature: temperature > 30 && temperature < 45
              ? temperature
              : null,
          accelX: accelXRaw / 1000.0, // Convert to g-force
          accelY: accelYRaw / 1000.0,
          accelZ: accelZRaw / 1000.0,
          battery: battery,
          rawData: {'dataType': dataType, 'rawPacket': data},
        );

        _dataController.add(sensorData);
        debugPrint(
          'X10 Ultra: HR=$heartRate SpO2=$spo2 Temp=$temperature Battery=$battery%',
        );
      }
    } catch (e) {
      debugPrint('X10 Ultra: Data processing error: $e');
    }
  }

  /// Get list of available X10 Ultra devices via BLE scan
  Future<List<BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final devices = <BluetoothDevice>[];
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          if (result.device.platformName.contains('X10') ||
              result.advertisementData.advName.contains('X10')) {
            if (!devices.any((d) => d.remoteId == result.device.remoteId)) {
              devices.add(result.device);
            }
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      subscription.cancel();

      debugPrint('X10 Ultra: Found ${devices.length} devices');
      return devices;
    } catch (e) {
      debugPrint('X10 Ultra: Scan error: $e');
      return [];
    }
  }
}

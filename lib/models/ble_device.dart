import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Model representing a discovered or connected BLE device.
class BleDeviceInfo {
  final String name;
  final String id;
  final int rssi;
  final double batteryLevel;
  final bool isConnected;
  final BluetoothDevice? rawDevice;

  const BleDeviceInfo({
    required this.name,
    required this.id,
    this.rssi = -100,
    this.batteryLevel = 0,
    this.isConnected = false,
    this.rawDevice,
  });

  BleDeviceInfo copyWith({
    String? name,
    String? id,
    int? rssi,
    double? batteryLevel,
    bool? isConnected,
    BluetoothDevice? rawDevice,
  }) {
    return BleDeviceInfo(
      name: name ?? this.name,
      id: id ?? this.id,
      rssi: rssi ?? this.rssi,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isConnected: isConnected ?? this.isConnected,
      rawDevice: rawDevice ?? this.rawDevice,
    );
  }

  /// Create from a FlutterBluePlus ScanResult.
  factory BleDeviceInfo.fromScanResult(ScanResult result) {
    final id = result.device.remoteId.str;
    final shortId = id.length > 6 ? id.substring(id.length - 6) : id;
    return BleDeviceInfo(
      name: result.device.platformName.isNotEmpty
          ? result.device.platformName
          : 'BLE-$shortId',
      id: id,
      rssi: result.rssi,
      rawDevice: result.device,
    );
  }

  /// Signal strength category based on RSSI.
  SignalStrength get signalStrength {
    if (rssi >= -50) return SignalStrength.excellent;
    if (rssi >= -70) return SignalStrength.good;
    if (rssi >= -85) return SignalStrength.fair;
    return SignalStrength.weak;
  }
}

enum SignalStrength {
  excellent,
  good,
  fair,
  weak;

  String get label {
    switch (this) {
      case SignalStrength.excellent:
        return 'Excellent';
      case SignalStrength.good:
        return 'Good';
      case SignalStrength.fair:
        return 'Fair';
      case SignalStrength.weak:
        return 'Weak';
    }
  }
}

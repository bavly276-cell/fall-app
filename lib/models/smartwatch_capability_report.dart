import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum WatchSupportLevel { full, partial, hrOnly, unsupported }

class SmartwatchCapabilityReport {
  final String deviceName;
  final String deviceId;
  final List<String> serviceUuids;
  final List<String> characteristicUuids;
  final bool supportsHeartRate;
  final bool supportsBattery;
  final bool supportsSpO2;
  final bool supportsGps;
  final bool supportsFallAlerts;
  final bool supportsCustomSafeBraceStream;

  const SmartwatchCapabilityReport({
    required this.deviceName,
    required this.deviceId,
    required this.serviceUuids,
    required this.characteristicUuids,
    required this.supportsHeartRate,
    required this.supportsBattery,
    required this.supportsSpO2,
    required this.supportsGps,
    required this.supportsFallAlerts,
    required this.supportsCustomSafeBraceStream,
  });

  bool get hasAnyKnownMetric =>
      supportsHeartRate ||
      supportsBattery ||
      supportsSpO2 ||
      supportsGps ||
      supportsFallAlerts ||
      supportsCustomSafeBraceStream;

  bool get hasHeartRate => supportsHeartRate || supportsCustomSafeBraceStream;
  bool get hasSpO2 => supportsSpO2 || supportsCustomSafeBraceStream;
  bool get hasGps => supportsGps || supportsCustomSafeBraceStream;
  bool get hasFall => supportsFallAlerts || supportsCustomSafeBraceStream;

  WatchSupportLevel get supportLevel {
    if (hasHeartRate && hasSpO2 && hasGps && hasFall) {
      return WatchSupportLevel.full;
    }
    if (hasHeartRate && !hasSpO2 && !hasGps && !hasFall) {
      return WatchSupportLevel.hrOnly;
    }
    if (hasAnyKnownMetric) {
      return WatchSupportLevel.partial;
    }
    return WatchSupportLevel.unsupported;
  }

  String get supportLabel {
    switch (supportLevel) {
      case WatchSupportLevel.full:
        return 'Full Support';
      case WatchSupportLevel.partial:
        return 'Partial Support';
      case WatchSupportLevel.hrOnly:
        return 'HR Only';
      case WatchSupportLevel.unsupported:
        return 'Not Supported';
    }
  }

  String get recommendation {
    switch (supportLevel) {
      case WatchSupportLevel.full:
        return 'This device can feed all core metrics (HR, SpO2, GPS, fall) into SafeBrace.';
      case WatchSupportLevel.partial:
        return 'Some metrics are available. Missing metrics may require a vendor companion app or SDK bridge.';
      case WatchSupportLevel.hrOnly:
        return 'Only heart-rate stream is available. Use this as a basic monitor, not full fall-risk analytics.';
      case WatchSupportLevel.unsupported:
        return 'No usable health telemetry detected over BLE from this device.';
    }
  }

  List<String> get supportedMetrics {
    final metrics = <String>[];
    if (supportsHeartRate) metrics.add('Heart Rate');
    if (supportsBattery) metrics.add('Battery');
    if (supportsSpO2) metrics.add('SpO2');
    if (supportsGps) metrics.add('GPS');
    if (supportsFallAlerts) metrics.add('Fall Alert');
    if (supportsCustomSafeBraceStream) metrics.add('SafeBrace Stream');
    return metrics;
  }

  String get summary {
    if (supportedMetrics.isEmpty) {
      return 'No standard metrics detected';
    }
    return supportedMetrics.join(', ');
  }

  factory SmartwatchCapabilityReport.fromServices({
    required BluetoothDevice device,
    required List<BluetoothService> services,
  }) {
    final serviceUuids = <String>[];
    final characteristicUuids = <String>[];

    var supportsHeartRate = false;
    var supportsBattery = false;
    var supportsSpO2 = false;
    var supportsGps = false;
    var supportsFallAlerts = false;
    var supportsCustomSafeBraceStream = false;

    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      serviceUuids.add(serviceUuid);

      if (serviceUuid.contains('180d')) supportsHeartRate = true;
      if (serviceUuid.contains('180f')) supportsBattery = true;
      if (serviceUuid.contains('1822')) supportsSpO2 = true;
      if (serviceUuid.contains('1819')) supportsGps = true;
      if (serviceUuid.contains('12345678-1234-1234-1234-123456789abc')) {
        supportsCustomSafeBraceStream = true;
      }

      for (final char in service.characteristics) {
        final charUuid = char.uuid.toString().toLowerCase();
        characteristicUuids.add(charUuid);

        if (charUuid.contains('2a37')) supportsHeartRate = true;
        if (charUuid.contains('2a19')) supportsBattery = true;
        if (charUuid.contains('2a5e') ||
            charUuid.contains('2a5f') ||
            charUuid.contains('2a52')) {
          supportsSpO2 = true;
        }
        if (charUuid.contains('2a67') ||
            charUuid.contains('2a68') ||
            charUuid.contains('2a69')) {
          supportsGps = true;
        }
        if (charUuid.contains('12345678-1234-1234-1234-123456789abd')) {
          supportsFallAlerts = true;
        }
        if (charUuid.contains('12345678-1234-1234-1234-123456789abd') ||
            charUuid.contains('12345678-1234-1234-1234-123456789abe') ||
            charUuid.contains('12345678-1234-1234-1234-123456789af0')) {
          supportsCustomSafeBraceStream = true;
        }
      }
    }

    return SmartwatchCapabilityReport(
      deviceName: device.platformName.isNotEmpty
          ? device.platformName
          : device.remoteId.str,
      deviceId: device.remoteId.str,
      serviceUuids: serviceUuids.toSet().toList(),
      characteristicUuids: characteristicUuids.toSet().toList(),
      supportsHeartRate: supportsHeartRate,
      supportsBattery: supportsBattery,
      supportsSpO2: supportsSpO2,
      supportsGps: supportsGps,
      supportsFallAlerts: supportsFallAlerts,
      supportsCustomSafeBraceStream: supportsCustomSafeBraceStream,
    );
  }
}

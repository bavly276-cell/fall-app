import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Parsed sensor data from the Arduino BLE stream.
class SensorData {
  final int heartRate;
  final double spo2;
  final double tiltAngle;
  final double accelMag;
  final int battery;
  final bool fallFlag;
  final bool? wifiConnected;

  const SensorData({
    required this.heartRate,
    required this.spo2,
    required this.tiltAngle,
    required this.accelMag,
    required this.battery,
    required this.fallFlag,
    required this.wifiConnected,
  });

  /// Parse "HR:72,TILT:3.2,ACC:1.02,BATT:87,FALL:0" format.
  static SensorData? parse(String raw) {
    try {
      final parts = raw.split(',');
      final map = <String, String>{};
      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length == 2) {
          map[kv[0].trim()] = kv[1].trim();
        }
      }

      return SensorData(
        heartRate: int.tryParse(map['HR'] ?? '') ?? 0,
        spo2: double.tryParse(map['SPO2'] ?? '') ?? 0.0,
        tiltAngle: double.tryParse(map['TILT'] ?? '') ?? 0.0,
        accelMag: double.tryParse(map['ACC'] ?? '') ?? 1.0,
        battery: int.tryParse(map['BATT'] ?? '') ?? -1,
        fallFlag: (map['FALL'] ?? '0') == '1',
        wifiConnected: map.containsKey('WIFI')
            ? (map['WIFI'] ?? '0') == '1'
            : null,
      );
    } catch (e) {
      debugPrint('SensorData parse error: $e (raw: $raw)');
      return null;
    }
  }

  @override
  String toString() =>
      'SensorData(HR:$heartRate, SPO2:${spo2.toStringAsFixed(1)}, '
      'TILT:${tiltAngle.toStringAsFixed(1)}, '
      'ACC:${accelMag.toStringAsFixed(2)}, BATT:$battery, '
      'FALL:$fallFlag, WIFI:${wifiConnected ?? "?"})';
}

/// Phone-side fall detection algorithm that mirrors & supplements
/// the Arduino's 3-stage detection as a redundant safety layer.
///
/// Uses a sliding window of recent acceleration readings to detect:
///   1. Freefall phase (|a| < 0.4g)
///   2. Impact phase (|a| > 3.0g)
///   3. Post-impact orientation (tilt > 60°)
///   4. Heart rate stress confirmation (HR > 100 BPM)
class FallDetectionAlgorithm {
  // Thresholds (matching Arduino)
  static const double impactThreshold = 3.0;
  static const double freefallThreshold = 0.4;
  static const double angleThreshold = 60.0;
  static const int hrStressThreshold = 100;
  static const Duration debounceDuration = Duration(seconds: 5);
  static const Duration freefallWindow = Duration(milliseconds: 500);
  static const Duration postImpactWindow = Duration(seconds: 1);

  final _accelHistory = ListQueue<_AccelSample>(maxSize);
  static const int maxSize = 50;

  _FallPhase _phase = _FallPhase.idle;
  DateTime? _impactTime;
  DateTime? _lastFallTime;

  /// Process a new sensor reading. Returns true if a fall is detected.
  bool processSensorData(SensorData data) {
    final now = DateTime.now();

    // Arduino already detected a fall — trust it immediately
    if (data.fallFlag) {
      if (_canTrigger(now)) {
        _lastFallTime = now;
        _phase = _FallPhase.idle;
        debugPrint('FallAlgo: Arduino-side fall confirmed');
        return true;
      }
      return false;
    }

    // Record acceleration history
    _accelHistory.addLast(_AccelSample(data.accelMag, now));
    while (_accelHistory.length > maxSize) {
      _accelHistory.removeFirst();
    }

    switch (_phase) {
      case _FallPhase.idle:
        // Detect high-g impact
        if (data.accelMag > impactThreshold) {
          if (_hadFreefallRecently(now)) {
            _phase = _FallPhase.impactDetected;
            _impactTime = now;
            debugPrint('FallAlgo: Impact after freefall detected');
          }
        }
        break;

      case _FallPhase.impactDetected:
        if (_impactTime != null &&
            now.difference(_impactTime!) < postImpactWindow) {
          // Check if person is lying down
          if (data.tiltAngle > angleThreshold) {
            final hrConfirms =
                data.heartRate == 0 || data.heartRate > hrStressThreshold;
            if (hrConfirms && _canTrigger(now)) {
              _lastFallTime = now;
              _phase = _FallPhase.idle;
              debugPrint('FallAlgo: Phone-side fall CONFIRMED');
              return true;
            }
          }
        } else {
          // Timeout — person recovered
          _phase = _FallPhase.idle;
        }
        break;
    }

    return false;
  }

  bool _canTrigger(DateTime now) {
    if (_lastFallTime == null) return true;
    return now.difference(_lastFallTime!) > debounceDuration;
  }

  bool _hadFreefallRecently(DateTime now) {
    for (final sample in _accelHistory) {
      if (now.difference(sample.time) > freefallWindow) continue;
      if (sample.accel < freefallThreshold) return true;
    }
    return false;
  }

  void reset() {
    _phase = _FallPhase.idle;
    _impactTime = null;
    _accelHistory.clear();
  }
}

enum _FallPhase { idle, impactDetected }

class _AccelSample {
  final double accel;
  final DateTime time;
  const _AccelSample(this.accel, this.time);
}

/// Extension to track a limited-size queue.
extension _ListQueueCapped<T> on ListQueue<T> {
  // ignore: unused_element
  static ListQueue<T> capped<T>(int maxSize) => ListQueue<T>(maxSize);
}

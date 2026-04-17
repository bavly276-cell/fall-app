import 'package:flutter/foundation.dart';

/// Parsed sensor data from the Arduino BLE stream.
class SensorData {
  final int heartRate;
  final double spo2;
  final double tiltAngle;
  final double accelMag;
  final double? accX;
  final double? accY;
  final double? accZ;
  final double? gyroMag;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  final int battery;
  final bool fallFlag;
  final bool? wifiConnected;

  const SensorData({
    required this.heartRate,
    required this.spo2,
    required this.tiltAngle,
    required this.accelMag,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroMag,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
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

      double? parseAny(List<String> keys) {
        for (final key in keys) {
          final val = double.tryParse(map[key] ?? '');
          if (val != null) return val;
        }
        return null;
      }

      final parsedAccX = parseAny(['AX', 'ACCX', 'ACX']);
      final parsedAccY = parseAny(['AY', 'ACCY', 'ACY']);
      final parsedAccZ = parseAny(['AZ', 'ACCZ', 'ACZ']);

      final parsedGyroX = parseAny(['GX', 'GYROX']);
      final parsedGyroY = parseAny(['GY', 'GYROY']);
      final parsedGyroZ = parseAny(['GZ', 'GYROZ']);

      final parsedGyroMag =
          double.tryParse(map['GYRO'] ?? '') ??
          double.tryParse(map['GMAG'] ?? '');

      final computedGyroMag =
          (parsedGyroX != null && parsedGyroY != null && parsedGyroZ != null)
          ? ((parsedGyroX * parsedGyroX) +
                    (parsedGyroY * parsedGyroY) +
                    (parsedGyroZ * parsedGyroZ))
                .sqrtSafe()
          : null;

      return SensorData(
        heartRate: int.tryParse(map['HR'] ?? '') ?? 0,
        spo2: double.tryParse(map['SPO2'] ?? '') ?? 0.0,
        tiltAngle: double.tryParse(map['TILT'] ?? '') ?? 0.0,
        accelMag: double.tryParse(map['ACC'] ?? '') ?? 1.0,
        accX: parsedAccX,
        accY: parsedAccY,
        accZ: parsedAccZ,
        // Optional (only if firmware includes it). Accept either GYRO or GMAG,
        // otherwise derive from 3-axis gyroscope if present.
        gyroMag: parsedGyroMag ?? computedGyroMag,
        gyroX: parsedGyroX,
        gyroY: parsedGyroY,
        gyroZ: parsedGyroZ,
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
      'ACC:${accelMag.toStringAsFixed(2)}, '
      'AX:${accX?.toStringAsFixed(3) ?? "-"}, '
      'AY:${accY?.toStringAsFixed(3) ?? "-"}, '
      'AZ:${accZ?.toStringAsFixed(3) ?? "-"}, '
      'GYRO:${gyroMag?.toStringAsFixed(2) ?? "-"}, '
      'GX:${gyroX?.toStringAsFixed(3) ?? "-"}, '
      'GY:${gyroY?.toStringAsFixed(3) ?? "-"}, '
      'GZ:${gyroZ?.toStringAsFixed(3) ?? "-"}, '
      'BATT:$battery, '
      'FALL:$fallFlag, WIFI:${wifiConnected ?? "?"})';
}

extension on num {
  double sqrtSafe() {
    if (this <= 0) return 0.0;
    // Newton-Raphson, avoids importing dart:math in this file.
    double x = toDouble();
    double guess = x > 1 ? x : 1.0;
    for (int i = 0; i < 10; i++) {
      guess = 0.5 * (guess + x / guess);
    }
    return guess;
  }
}

/// Phone-side fall detection algorithm that mirrors & supplements
/// the firmware using a 5-state FSM:
/// NORMAL → FREE_FALL → IMPACT → STILLNESS_CHECK → ALERT
///
/// Uses SVM thresholds (in g) from the report:
/// - Freefall: < 0.5g
/// - Impact:   > 2.5g
///
/// Gyro magnitude confirmation is applied only if `gyroMag` is present.
class FallDetectionAlgorithm {
  static const double thFreefallG = 0.5;
  static const double thImpactG = 2.5;

  // Direct transition possible for high-energy falls (report)
  static const double thImpactDirectG = 3.0;

  // Free-fall must persist >0.5s (report)
  static const Duration freefallRequired = Duration(milliseconds: 500);

  // 2s stillness requirement (report) — gyro magnitude < 50 deg/s
  static const Duration stillnessRequired = Duration(seconds: 2);
  static const double stillAccelMinG = 0.80;
  static const double stillAccelMaxG = 1.20;
  // 50 deg/s = 0.8726646 rad/s
  static const double stillGyroMax = 0.8726646;

  static const Duration freefallToImpactWindow = Duration(milliseconds: 800);
  static const Duration impactConfirmWindow = Duration(milliseconds: 600);
  static const Duration stillnessTimeout = Duration(seconds: 5);
  static const Duration debounceDuration = Duration(seconds: 5);

  _FsmState _state = _FsmState.normal;
  DateTime? _freefallCandidateAt;
  DateTime? _freefallAt;
  DateTime? _impactAt;
  DateTime? _stillnessAt;
  DateTime? _lastTriggerAt;

  bool processSensorData(SensorData data) {
    final now = DateTime.now();

    // If firmware already flagged a fall, treat it as ALERT.
    if (data.fallFlag) {
      if (_canTrigger(now)) {
        _lastTriggerAt = now;
        _state = _FsmState.normal;
        return true;
      }
      return false;
    }

    switch (_state) {
      case _FsmState.normal:
        // Direct impact for high-energy falls
        if (data.accelMag > thImpactDirectG) {
          _state = _FsmState.stillnessCheck;
          _impactAt = now;
          _stillnessAt = null;
          break;
        }

        // Free-fall requires sustained low SVM >0.5s
        if (data.accelMag < thFreefallG) {
          _freefallCandidateAt ??= now;
          if (now.difference(_freefallCandidateAt!) >= freefallRequired) {
            _state = _FsmState.freeFall;
            _freefallAt = _freefallCandidateAt;
          }
        } else {
          _freefallCandidateAt = null;
        }
        break;

      case _FsmState.freeFall:
        if (_freefallAt == null ||
            now.difference(_freefallAt!) > freefallToImpactWindow) {
          _resetToNormal();
          break;
        }
        if (data.accelMag > thImpactG) {
          // Impact detected
          _state = _FsmState.impact;
          _impactAt = now;
        }
        break;

      case _FsmState.impact:
        // Transition immediately to STILLNESS_CHECK after impact.
        _state = _FsmState.stillnessCheck;
        _stillnessAt = null;
        break;

      case _FsmState.stillnessCheck:
        if (_impactAt == null ||
            now.difference(_impactAt!) > stillnessTimeout) {
          // Timer expired -> still trigger alert (report)
          if (_canTrigger(now)) {
            _lastTriggerAt = now;
            _resetToNormal();
            return true;
          }
          _resetToNormal();
          break;
        }

        final stillAccel =
            data.accelMag >= stillAccelMinG && data.accelMag <= stillAccelMaxG;
        final gyro = data.gyroMag;
        final stillGyro = gyro == null ? true : gyro <= stillGyroMax;
        final still = stillAccel && stillGyro;

        if (still) {
          _stillnessAt ??= now;
          if (now.difference(_stillnessAt!) >= stillnessRequired) {
            if (_canTrigger(now)) {
              _lastTriggerAt = now;
              _resetToNormal();
              return true;
            }
            _resetToNormal();
          }
        } else {
          _stillnessAt = null;
        }
        break;
    }

    return false;
  }

  bool _canTrigger(DateTime now) {
    if (_lastTriggerAt == null) return true;
    return now.difference(_lastTriggerAt!) >= debounceDuration;
  }

  void _resetToNormal() {
    _state = _FsmState.normal;
    _freefallCandidateAt = null;
    _freefallAt = null;
    _impactAt = null;
    _stillnessAt = null;
  }

  void reset() => _resetToNormal();
}

enum _FsmState { normal, freeFall, impact, stillnessCheck }

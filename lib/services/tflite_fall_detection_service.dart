import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteFallDetectionService {
  TfliteFallDetectionService._();

  static final TfliteFallDetectionService instance =
      TfliteFallDetectionService._();

  static const String _modelAsset = 'assets/models/fall_detector.tflite';
  static const int _windowSize = 60;
  static const Duration _minInferenceInterval = Duration(milliseconds: 350);

  Interpreter? _interpreter;
  bool _ready = false;
  DateTime? _lastInferenceAt;
  final List<List<double>> _window = <List<double>>[];

  bool get isReady => _ready;

  Future<void> initialize() async {
    if (_ready) return;

    try {
      final options = InterpreterOptions()..threads = 1;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
      _ready = true;
      debugPrint('TFLite fall model loaded ($_modelAsset)');
    } catch (e) {
      _ready = false;
      _interpreter = null;
      debugPrint('TFLite model load failed: $e');
    }
  }

  double? addSampleAndPredict({required double accelMag, double? gyroMag}) {
    final normalizedAccel = ((accelMag - 1.0).abs()).clamp(0.0, 4.0) / 4.0;
    final normalizedGyro = (gyroMag ?? 0.0).abs().clamp(0.0, 8.0) / 8.0;

    _window.add(<double>[normalizedAccel, normalizedGyro]);
    if (_window.length > _windowSize) {
      _window.removeAt(0);
    }

    if (!_ready || _interpreter == null || _window.length < _windowSize) {
      return null;
    }

    final now = DateTime.now();
    if (_lastInferenceAt != null &&
        now.difference(_lastInferenceAt!) < _minInferenceInterval) {
      return null;
    }
    _lastInferenceAt = now;

    try {
      final input = [
        List<List<double>>.generate(
          _windowSize,
          (i) => [_window[i][0], _window[i][1]],
        ),
      ];

      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _interpreter!.run(input, output);

      final probability = (output[0][0] as num).toDouble().clamp(0.0, 1.0);
      if (probability.isNaN || probability.isInfinite) {
        return null;
      }
      return probability;
    } catch (e) {
      debugPrint('TFLite inference failed: $e');
      return null;
    }
  }

  void reset() {
    _window.clear();
    _lastInferenceAt = null;
  }

  void dispose() {
    _window.clear();
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }

  static String probabilityToLabel(double probability) {
    final p = probability.clamp(0.0, 1.0);
    if (p >= 0.9) return 'Critical fall risk';
    if (p >= 0.75) return 'High fall probability';
    if (p >= 0.55) return 'Potential fall pattern';
    if (p >= 0.35) return 'Active movement';
    return 'Stable';
  }

  static double fallbackHeuristic({
    required double accelMag,
    required double tiltAngle,
    required double heartRate,
    required double spo2,
  }) {
    final impact = ((accelMag - 1.0).abs() / 3.5).clamp(0.0, 1.0);
    final tilt = (tiltAngle.abs() / 90.0).clamp(0.0, 1.0);
    final hr = (heartRate / 180.0).clamp(0.0, 1.0);
    final oxy = (1.0 - (spo2 / 100.0).clamp(0.0, 1.0));

    final score = (0.5 * impact) + (0.2 * tilt) + (0.2 * hr) + (0.1 * oxy);
    return min(max(score, 0.0), 1.0);
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'fall_detection_algorithm.dart';

class TfliteFallDetectionService {
  TfliteFallDetectionService._();

  static final TfliteFallDetectionService instance =
      TfliteFallDetectionService._();

  static const String _modelAsset = 'assets/models/fall_detector.tflite';
  static const String _metaAsset = 'assets/models/fall_detector_meta.json';
  static const int _featureCount = 6;

  int _windowSize = 64;
  Duration _minInferenceInterval = const Duration(milliseconds: 240);
  double _threshold = 0.7;

  List<double> _mean = const [0, 0, 1, 0, 0, 0];
  List<double> _std = const [1, 1, 1, 1, 1, 1];

  Interpreter? _interpreter;
  bool _ready = false;
  DateTime? _lastInferenceAt;
  final List<List<double>> _window = <List<double>>[];

  bool get isReady => _ready;

  Future<void> initialize() async {
    if (_ready) return;

    try {
      await _loadMetadata();

      final options = InterpreterOptions()..threads = 1;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
      _ready = true;
      debugPrint(
        'TFLite fall model loaded ($_modelAsset), window=$_windowSize, threshold=$_threshold',
      );
    } catch (e) {
      _ready = false;
      _interpreter = null;
      debugPrint('TFLite model load failed: $e');
    }
  }

  Future<void> _loadMetadata() async {
    try {
      final raw = await rootBundle.loadString(_metaAsset);
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;

      _windowSize = (jsonMap['window_size'] as num?)?.toInt() ?? _windowSize;
      final inferMs =
          (jsonMap['inference_interval_ms'] as num?)?.toInt() ??
          _minInferenceInterval.inMilliseconds;
      _minInferenceInterval = Duration(milliseconds: inferMs.clamp(50, 2000));

      _threshold =
          (jsonMap['threshold'] as num?)?.toDouble().clamp(0.05, 0.98) ??
          _threshold;

      final m = jsonMap['mean'];
      final s = jsonMap['std'];

      if (m is List &&
          s is List &&
          m.length == _featureCount &&
          s.length == _featureCount) {
        _mean = m.map((e) => (e as num).toDouble()).toList();
        _std = s.map((e) => max((e as num).toDouble().abs(), 1e-6)).toList();
      }
    } catch (_) {
      // Metadata is optional; service falls back to safe defaults.
    }
  }

  double? addSampleAndPredict({required SensorData data}) {
    final sample = _normalizeSample(_toRawFeatureVector(data));

    _window.add(sample);
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
      final input = [List<List<double>>.from(_window)];

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

  bool isFallByThreshold(double probability) {
    return probability >= _threshold;
  }

  List<double> _toRawFeatureVector(SensorData data) {
    // Prefer full 6-axis stream. If axes are missing, fall back to a safe
    // approximate projection that still keeps the runtime path functional.
    final ax = data.accX ?? data.accelMag;
    final ay = data.accY ?? 0.0;
    final az = data.accZ ?? 0.0;

    final gx = data.gyroX ?? data.gyroMag ?? 0.0;
    final gy = data.gyroY ?? 0.0;
    final gz = data.gyroZ ?? 0.0;

    return <double>[ax, ay, az, gx, gy, gz];
  }

  List<double> _normalizeSample(List<double> raw) {
    return List<double>.generate(_featureCount, (i) {
      final centered = raw[i] - _mean[i];
      return centered / _std[i];
    });
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

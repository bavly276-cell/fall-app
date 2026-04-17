import 'dart:math';

/// A lightweight Artificial Intelligence classifier for Fall Detection.
/// This implements a Single-Layer Perceptron (Neural Network) in pure Dart.
/// It operates locally and doesn't require an internet connection or API keys.
class AiFallDetector {
  AiFallDetector._();

  // "Expert-Calibrated" weights for the classification model.
  // In a production app, these would be loaded from a .tflite or .json file 
  // trained on a large dataset like SisFall.
  // Input vector index: [AccelMag, Tilt, HeartRate, SpO2, DeltaAccel, DeltaHR]
  static const List<double> _weights = [
    0.8,   // Accel Magnitude (highest weight for impact)
    0.6,   // Tilt Angle (high weight for post-impact posture)
    0.2,   // Heart Rate (secondary physiological factor)
    -0.1,  // SpO2 (negative weight: lower SpO2 increases fall probability)
    0.4,   // Delta Accel (sudden peak detection)
    0.3,   // Delta HR (stress response)
  ];

  static const double _bias = -1.5; // Controls the "sensitivity" threshold

  // History for calculating deltas
  static double _lastAccel = 1.0;
  static double _lastHR = 75.0;

  /// Predict the probability of a fall (0.0 to 1.0).
  static double predict(
    double accel, 
    double tilt, 
    double hr, 
    double spo2
  ) {
    // 1. Feature Engineering & Normalization
    final nAccel = (accel / 5.0).clamp(0.0, 1.0); // Normalizing 0-5g
    final nTilt = (tilt / 90.0).clamp(0.0, 1.0); // Normalizing 0-90 deg
    final nHR = (hr / 160.0).clamp(0.0, 1.0);    // Normalizing 60-160 bpm
    final nSPO2 = (spo2 / 100).clamp(0.0, 1.0);
    
    final dAccel = (accel - _lastAccel).abs() / 2.0;
    final dHR = (hr - _lastHR).abs() / 20.0;

    _lastAccel = accel;
    _lastHR = hr;

    final inputs = [nAccel, nTilt, nHR, nSPO2, dAccel, dHR];

    // 2. Linear Combination (The "Neuron" sum)
    double sum = _bias;
    for (int i = 0; i < inputs.length; i++) {
      sum += inputs[i] * _weights[i];
    }

    // 3. Activation Function (Sigmoid)
    // Formula: 1 / (1 + e^-x)
    return 1.0 / (1.0 + exp(-sum));
  }

  /// Get a human-readable interpretation of the confidence score.
  static String getLabel(double probability) {
    if (probability > 0.9) return 'Critical Risk Detected';
    if (probability > 0.7) return 'High Confidence Fall';
    if (probability > 0.5) return 'Potential Risk';
    if (probability > 0.2) return 'Active Movement';
    return 'Stable';
  }
}

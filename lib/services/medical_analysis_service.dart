import 'dart:math';
import '../models/fall_event.dart';

/// Medical data point for analysis
class MedicalDataPoint {
  final DateTime timestamp;
  final double? heartRate;
  final double? spO2;
  final double? temperature;
  final double? accelMag;
  final double? battery;
  final double? latitude;
  final double? longitude;
  bool isFallEvent = false;

  MedicalDataPoint({
    required this.timestamp,
    this.heartRate,
    this.spO2,
    this.temperature,
    this.accelMag,
    this.battery,
    this.latitude,
    this.longitude,
  });

  factory MedicalDataPoint.fromFallEvent(FallEvent event) {
    final point = MedicalDataPoint(
      timestamp: event.time,
      heartRate: event.heartRate,
      accelMag: event.accelMag,
    );
    point.isFallEvent = true;
    return point;
  }
}

/// Risk assessment result
class RiskAssessment {
  final double overallRiskScore; // 0-100
  final String riskLevel; // LOW, MODERATE, HIGH, CRITICAL
  final Map<String, double> componentScores;
  final List<String> riskFactors;
  final DateTime assessmentTime;

  RiskAssessment({
    required this.overallRiskScore,
    required this.riskLevel,
    required this.componentScores,
    required this.riskFactors,
    required this.assessmentTime,
  });
}

/// Trend analysis result
class TrendAnalysis {
  final String metric; // 'HR', 'SPO2', 'TEMP'
  final double currentValue;
  final double average;
  final double trend; // -1 to 1 (negative = declining, positive = improving)
  final String trendDirection; // 'IMPROVING', 'STABLE', 'DECLINING'
  final int dataPointCount;

  TrendAnalysis({
    required this.metric,
    required this.currentValue,
    required this.average,
    required this.trend,
    required this.trendDirection,
    required this.dataPointCount,
  });
}

/// Correlation finding
class Correlation {
  final String cause; // e.g., "High HR"
  final String result; // e.g., "Fall Risk"
  final double strength; // 0-1
  final int occurrences;
  final double probability; // likelihood of result given cause

  Correlation({
    required this.cause,
    required this.result,
    required this.strength,
    required this.occurrences,
    required this.probability,
  });
}

/// Pattern detected in medical data
class Pattern {
  final String name;
  final String description;
  final DateTime? nextExpectedOccurrence;
  final double confidence; // 0-1
  final List<MedicalDataPoint> examples;
  final Map<String, dynamic> characteristics;

  Pattern({
    required this.name,
    required this.description,
    this.nextExpectedOccurrence,
    required this.confidence,
    required this.examples,
    required this.characteristics,
  });
}

/// Scenario with cause and result
class CauseResultScenario {
  final String scenario;
  final List<String> causes;
  final String result;
  final double probability;
  final int historicalOccurrences;
  final DateTime? lastOccurrence;
  final String severity; // LOW, MEDIUM, HIGH

  CauseResultScenario({
    required this.scenario,
    required this.causes,
    required this.result,
    required this.probability,
    required this.historicalOccurrences,
    this.lastOccurrence,
    required this.severity,
  });
}

/// Comprehensive medical analysis service
class MedicalAnalysisService {
  static final List<MedicalDataPoint> _dataHistory = [];
  static final List<MedicalDataPoint> _fallHistory = [];

  // Normal ranges for vital signs
  static const double hrLowerNormal = 60;
  static const double hrUpperNormal = 100;
  static const double spo2Normal = 95;
  static const double tempNormal = 37.0;
  static const double accelThresholdHigh = 2.5;

  /// Add sensor data point to history
  static void addDataPoint(MedicalDataPoint point) {
    _dataHistory.add(point);
    // Keep only last 24 hours
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _dataHistory.removeWhere((p) => p.timestamp.isBefore(cutoff));
  }

  /// Add fall event to history
  static void addFallEvent(FallEvent event) {
    _fallHistory.add(MedicalDataPoint.fromFallEvent(event));
    // Keep only last 30 days
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    _fallHistory.removeWhere((p) => p.timestamp.isBefore(cutoff));
  }

  /// Calculate overall risk score (0-100)
  static RiskAssessment calculateRiskAssessment() {
    if (_dataHistory.isEmpty) {
      return RiskAssessment(
        overallRiskScore: 0,
        riskLevel: 'LOW',
        componentScores: {
          'heartRate': 0,
          'spO2': 0,
          'temperature': 0,
          'acceleration': 0,
          'battery': 0,
          'fallHistory': 0,
        },
        riskFactors: [],
        assessmentTime: DateTime.now(),
      );
    }

    final latest = _dataHistory.last;
    final componentScores = <String, double>{};
    final riskFactors = <String>[];

    // HR Risk Component (0-25 points)
    double hrRisk = 0;
    if (latest.heartRate != null) {
      final hr = latest.heartRate!;
      if (hr < 40 || hr > 140) {
        hrRisk = 25;
        riskFactors.add('Abnormal heart rate: ${hr.toStringAsFixed(0)} BPM');
      } else if (hr < 50 || hr > 120) {
        hrRisk = 15;
        riskFactors.add(
          'Heart rate out of normal range: ${hr.toStringAsFixed(0)} BPM',
        );
      } else if (hr < hrLowerNormal || hr > hrUpperNormal) {
        hrRisk = 8;
      }
    }
    componentScores['heartRate'] = hrRisk;

    // SpO2 Risk Component (0-30 points)
    double spo2Risk = 0;
    if (latest.spO2 != null) {
      final spo2 = latest.spO2!;
      if (spo2 < 90) {
        spo2Risk = 30;
        riskFactors.add('Critical SpO2 level: ${spo2.toStringAsFixed(1)}%');
      } else if (spo2 < 94) {
        spo2Risk = 20;
        riskFactors.add('Low SpO2: ${spo2.toStringAsFixed(1)}%');
      } else if (spo2 < spo2Normal) {
        spo2Risk = 10;
      }
    }
    componentScores['spO2'] = spo2Risk;

    // Temperature Risk Component (0-15 points)
    double tempRisk = 0;
    if (latest.temperature != null) {
      final temp = latest.temperature!;
      if (temp < 36 || temp > 39) {
        tempRisk = 15;
        riskFactors.add('Abnormal temperature: ${temp.toStringAsFixed(1)}°C');
      } else if (temp < 36.5 || temp > 38.5) {
        tempRisk = 8;
      }
    }
    componentScores['temperature'] = tempRisk;

    // Acceleration/Movement Risk Component (0-15 points)
    double accelRisk = 0;
    if (latest.accelMag != null) {
      final accel = latest.accelMag!;
      if (accel > accelThresholdHigh * 1.5) {
        accelRisk = 15;
        riskFactors.add(
          'High acceleration detected: ${accel.toStringAsFixed(2)}g',
        );
      } else if (accel > accelThresholdHigh) {
        accelRisk = 8;
      }
    }
    componentScores['acceleration'] = accelRisk;

    // Battery Risk Component (0-10 points)
    double batteryRisk = 0;
    if (latest.battery != null && latest.battery! < 15) {
      batteryRisk = 10;
      riskFactors.add('Low battery: ${latest.battery!.toStringAsFixed(0)}%');
    }
    componentScores['battery'] = batteryRisk;

    // Recent fall history impact (0-5 points bonus)
    double fallHistoryRisk = 0;
    if (_fallHistory.isNotEmpty) {
      final recentFalls = _fallHistory
          .where(
            (f) => f.timestamp.isAfter(
              DateTime.now().subtract(const Duration(days: 7)),
            ),
          )
          .length;
      fallHistoryRisk = min(5.0, recentFalls * 2.0);
      if (recentFalls > 0) {
        riskFactors.add('$recentFalls fall(s) in last 7 days');
      }
    }
    componentScores['fallHistory'] = fallHistoryRisk;

    final totalRisk =
        (hrRisk +
                spo2Risk +
                tempRisk +
                accelRisk +
                batteryRisk +
                fallHistoryRisk)
            .clamp(0, 100)
            .toDouble();

    String riskLevel;
    if (totalRisk < 20) {
      riskLevel = 'LOW';
    } else if (totalRisk < 40) {
      riskLevel = 'MODERATE';
    } else if (totalRisk < 70) {
      riskLevel = 'HIGH';
    } else {
      riskLevel = 'CRITICAL';
    }

    return RiskAssessment(
      overallRiskScore: totalRisk,
      riskLevel: riskLevel,
      componentScores: componentScores,
      riskFactors: riskFactors,
      assessmentTime: DateTime.now(),
    );
  }

  /// Analyze trend for a specific metric
  static TrendAnalysis analyzeTrend(String metric) {
    final relevant = _dataHistory.where((p) {
      switch (metric) {
        case 'HR':
          return p.heartRate != null;
        case 'SPO2':
          return p.spO2 != null;
        case 'TEMP':
          return p.temperature != null;
        default:
          return false;
      }
    }).toList();

    if (relevant.isEmpty) {
      return TrendAnalysis(
        metric: metric,
        currentValue: 0,
        average: 0,
        trend: 0,
        trendDirection: 'STABLE',
        dataPointCount: 0,
      );
    }

    final values = relevant.map((p) {
      switch (metric) {
        case 'HR':
          return p.heartRate!;
        case 'SPO2':
          return p.spO2!;
        case 'TEMP':
          return p.temperature!;
        default:
          return 0.0;
      }
    }).toList();

    final current = values.last;
    final average = values.reduce((a, b) => a + b) / values.length;

    // Calculate trend using linear regression
    double trend = 0;
    if (values.length > 1) {
      final xValues = List.generate(values.length, (i) => i.toDouble());
      final slope = _calculateLinearRegression(xValues, values);
      trend = (slope / current).clamp(-1, 1);
    }

    final trendDirection = trend < -0.05
        ? 'DECLINING'
        : trend > 0.05
        ? 'IMPROVING'
        : 'STABLE';

    return TrendAnalysis(
      metric: metric,
      currentValue: current,
      average: average,
      trend: trend,
      trendDirection: trendDirection,
      dataPointCount: values.length,
    );
  }

  /// Detect correlations between vitals and falls
  static List<Correlation> detectCorrelations() {
    if (_fallHistory.isEmpty || _dataHistory.length < 10) {
      return [];
    }

    final correlations = <Correlation>[];

    // Check HR-Fall correlation
    final preFailHRs = <double>[];
    for (final fall in _fallHistory) {
      final before = _dataHistory.where((p) {
        final diff = fall.timestamp.difference(p.timestamp).inMinutes.abs();
        return diff <= 5 && p.heartRate != null;
      });
      preFailHRs.addAll(before.map((p) => p.heartRate!));
    }

    if (preFailHRs.isNotEmpty) {
      final highHRFalls = preFailHRs.where((hr) => hr > 110).length;
      final probability = highHRFalls / preFailHRs.length;

      if (probability > 0.3) {
        correlations.add(
          Correlation(
            cause: 'High Heart Rate (>110 BPM)',
            result: 'Increased Fall Risk',
            strength: probability.clamp(0, 1),
            occurrences: highHRFalls,
            probability: probability,
          ),
        );
      }
    }

    // Check SpO2-Fall correlation
    final preFallSpO2s = <double>[];
    for (final fall in _fallHistory) {
      final before = _dataHistory.where((p) {
        final diff = fall.timestamp.difference(p.timestamp).inMinutes.abs();
        return diff <= 5 && p.spO2 != null;
      });
      preFallSpO2s.addAll(before.map((p) => p.spO2!));
    }

    if (preFallSpO2s.isNotEmpty) {
      final lowSpO2Falls = preFallSpO2s.where((spo2) => spo2 < 94).length;
      final probability = lowSpO2Falls / preFallSpO2s.length;

      if (probability > 0.2) {
        correlations.add(
          Correlation(
            cause: 'Low SpO2 (<94%)',
            result: 'Increased Fall Risk',
            strength: probability.clamp(0, 1),
            occurrences: lowSpO2Falls,
            probability: probability,
          ),
        );
      }
    }

    return correlations;
  }

  /// Detect patterns in medical data
  static List<Pattern> detectPatterns() {
    if (_dataHistory.length < 5) {
      return [];
    }

    final patterns = <Pattern>[];

    // Pattern 1: Tachycardia episodes
    final tachy = _dataHistory
        .where((p) => p.heartRate != null && p.heartRate! > 120)
        .toList();
    if (tachy.length >= 3) {
      patterns.add(
        Pattern(
          name: 'Tachycardia Episodes',
          description: 'Recurring periods of elevated heart rate (>120 BPM)',
          confidence: (tachy.length / _dataHistory.length).clamp(0, 1),
          examples: tachy.take(3).toList(),
          characteristics: {
            'frequency': tachy.length,
            'average_hr':
                tachy.map((p) => p.heartRate!).reduce((a, b) => a + b) /
                tachy.length,
          },
        ),
      );
    }

    // Pattern 2: Low oxygen saturation
    final lowO2 = _dataHistory
        .where((p) => p.spO2 != null && p.spO2! < 95)
        .toList();
    if (lowO2.length >= 3) {
      patterns.add(
        Pattern(
          name: 'Low Oxygen Saturation',
          description: 'Recurring periods of low SpO2 levels (<95%)',
          confidence: (lowO2.length / _dataHistory.length).clamp(0, 1),
          examples: lowO2.take(3).toList(),
          characteristics: {
            'frequency': lowO2.length,
            'average_spo2':
                lowO2.map((p) => p.spO2!).reduce((a, b) => a + b) /
                lowO2.length,
          },
        ),
      );
    }

    // Pattern 3: Temperature irregularities
    final tempAnomalies = _dataHistory
        .where(
          (p) =>
              p.temperature != null &&
              (p.temperature! < 36.5 || p.temperature! > 38.5),
        )
        .toList();
    if (tempAnomalies.length >= 3) {
      patterns.add(
        Pattern(
          name: 'Temperature Fluctuations',
          description: 'Irregular body temperature patterns',
          confidence: (tempAnomalies.length / _dataHistory.length).clamp(0, 1),
          examples: tempAnomalies.take(3).toList(),
          characteristics: {
            'frequency': tempAnomalies.length,
            'average_temp':
                tempAnomalies
                    .map((p) => p.temperature!)
                    .reduce((a, b) => a + b) /
                tempAnomalies.length,
          },
        ),
      );
    }

    // Pattern 4: High acceleration events
    final highAccel = _dataHistory
        .where((p) => p.accelMag != null && p.accelMag! > 2.0)
        .toList();
    if (highAccel.length >= 3) {
      patterns.add(
        Pattern(
          name: 'Frequent Movement Spikes',
          description: 'Recurring high acceleration/movement events',
          confidence: (highAccel.length / _dataHistory.length).clamp(0, 1),
          examples: highAccel.take(3).toList(),
          characteristics: {
            'frequency': highAccel.length,
            'average_accel':
                highAccel.map((p) => p.accelMag!).reduce((a, b) => a + b) /
                highAccel.length,
          },
        ),
      );
    }

    return patterns;
  }

  /// Generate cause-result scenarios
  static List<CauseResultScenario> generateScenarios() {
    final scenarios = <CauseResultScenario>[];
    final assessment = calculateRiskAssessment();
    final correlations = detectCorrelations();
    final patterns = detectPatterns();

    // Scenario 1: High HR + High Acceleration = Fall Risk
    if ((assessment.componentScores['heartRate'] ?? 0) > 10 &&
        (assessment.componentScores['acceleration'] ?? 0) > 10) {
      final hrCorr = correlations.where((c) => c.cause.contains('Heart Rate'));
      final probability = hrCorr.isNotEmpty ? hrCorr.first.probability : 0.3;
      scenarios.add(
        CauseResultScenario(
          scenario: 'Cardiac Stress with Movement',
          causes: [
            'Elevated Heart Rate (>110 BPM)',
            'Rapid Movement (High Acceleration)',
          ],
          result: 'Increased Fall Risk',
          probability: probability,
          historicalOccurrences: _fallHistory.length,
          lastOccurrence: _fallHistory.isNotEmpty
              ? _fallHistory.last.timestamp
              : null,
          severity: probability > 0.6 ? 'HIGH' : 'MEDIUM',
        ),
      );
    }

    // Scenario 2: Low SpO2 + Abnormal HR = Critical Risk
    if ((assessment.componentScores['spO2'] ?? 0) > 15 &&
        (assessment.componentScores['heartRate'] ?? 0) > 15) {
      scenarios.add(
        CauseResultScenario(
          scenario: 'Hypoxia with Tachycardia',
          causes: ['Low Oxygen Saturation (<94%)', 'Elevated Heart Rate'],
          result: 'Critical Fall Risk / Cardiac Event Risk',
          probability: 0.7,
          historicalOccurrences: _fallHistory.length,
          lastOccurrence: _fallHistory.isNotEmpty
              ? _fallHistory.last.timestamp
              : null,
          severity: 'HIGH',
        ),
      );
    }

    // Scenario 3: Fever + Dizziness = Fall Risk
    if ((assessment.componentScores['temperature'] ?? 0) > 8) {
      scenarios.add(
        CauseResultScenario(
          scenario: 'Fever with Abnormal Vitals',
          causes: [
            'Elevated Temperature (>38.5°C)',
            'Potential Infection/Illness',
          ],
          result: 'Increased Fall Risk',
          probability: 0.5,
          historicalOccurrences: _fallHistory.length,
          severity: 'MEDIUM',
        ),
      );
    }

    // Scenario 4: Low Battery + Fall History = Alert Risk
    if ((assessment.componentScores['battery'] ?? 0) > 5 &&
        (assessment.componentScores['fallHistory'] ?? 0) > 2) {
      scenarios.add(
        CauseResultScenario(
          scenario: 'Device Unavailability Risk',
          causes: ['Low Battery (<15%)', 'Recent Fall History'],
          result: 'Device Disconnection / No Emergency Alert',
          probability: 0.8,
          historicalOccurrences: _fallHistory.length,
          severity: 'HIGH',
        ),
      );
    }

    // Scenario 5: Pattern-based scenarios
    for (final pattern in patterns) {
      if (pattern.name == 'Tachycardia Episodes') {
        scenarios.add(
          CauseResultScenario(
            scenario: 'Recurring Tachycardia',
            causes: ['Recurring episodes of elevated HR >120 BPM'],
            result: 'Potential Cardiovascular Issue',
            probability: min(pattern.confidence * 0.8, 0.9),
            historicalOccurrences:
                pattern.characteristics['frequency'] as int? ?? 0,
            severity: 'MEDIUM',
          ),
        );
      }
    }

    return scenarios;
  }

  /// Generate comprehensive medical report
  static Map<String, dynamic> generateMedicalReport() {
    return {
      'timestamp': DateTime.now(),
      'risk_assessment': calculateRiskAssessment(),
      'trends': {
        'heart_rate': analyzeTrend('HR'),
        'oxygen_saturation': analyzeTrend('SPO2'),
        'temperature': analyzeTrend('TEMP'),
      },
      'correlations': detectCorrelations(),
      'patterns': detectPatterns(),
      'scenarios': generateScenarios(),
      'total_data_points': _dataHistory.length,
      'total_falls': _fallHistory.length,
    };
  }

  /// Helper: Calculate linear regression slope
  static double _calculateLinearRegression(List<double> x, List<double> y) {
    if (x.isEmpty || x.length != y.length) return 0;

    final n = x.length;
    final sumX = x.reduce((a, b) => a + b);
    final sumY = y.reduce((a, b) => a + b);
    final sumXY = List.generate(n, (i) => x[i] * y[i]).reduce((a, b) => a + b);
    final sumX2 = x.map((v) => v * v).reduce((a, b) => a + b);

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    return slope.isNaN || slope.isInfinite ? 0 : slope;
  }

  /// Clear all history
  static void clearHistory() {
    _dataHistory.clear();
    _fallHistory.clear();
  }

  /// Get data history for export
  static List<MedicalDataPoint> getDataHistory() => List.from(_dataHistory);

  /// Get fall history for export
  static List<MedicalDataPoint> getFallHistory() => List.from(_fallHistory);
}

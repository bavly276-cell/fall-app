import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fall_event.dart';
import 'medical_analysis_service.dart';

/// Medical Insights Provider - Continuously feeds data to analysis service
class MedicalInsightsProvider {
  static final MedicalInsightsProvider _instance =
      MedicalInsightsProvider._internal();
  static StreamSubscription<MedicalDataPoint>? _dataSubscription;
  static StreamSubscription<FallEvent>? _fallSubscription;

  factory MedicalInsightsProvider() {
    return _instance;
  }

  MedicalInsightsProvider._internal();

  /// Start monitoring health data streams
  static void startMonitoring({
    required Stream<MedicalDataPoint> dataStream,
    required Stream<FallEvent> fallStream,
  }) {
    // Listen to real-time sensor data
    _dataSubscription = dataStream.listen((dataPoint) {
      MedicalAnalysisService.addDataPoint(dataPoint);
    });

    // Listen to fall events
    _fallSubscription = fallStream.listen((fallEvent) {
      MedicalAnalysisService.addFallEvent(fallEvent);
    });

    debugPrint('Medical Insights Provider: Monitoring started');
  }

  /// Stop monitoring
  static void stopMonitoring() {
    _dataSubscription?.cancel();
    _fallSubscription?.cancel();
    debugPrint('Medical Insights Provider: Monitoring stopped');
  }

  /// Add a manual data point
  static void addDataPoint(MedicalDataPoint point) {
    MedicalAnalysisService.addDataPoint(point);
  }

  /// Add a manual fall event
  static void addFallEvent(FallEvent event) {
    MedicalAnalysisService.addFallEvent(event);
  }

  /// Get current risk assessment
  static RiskAssessment getRiskAssessment() {
    return MedicalAnalysisService.calculateRiskAssessment();
  }

  /// Get medical report
  static Map<String, dynamic> getMedicalReport() {
    return MedicalAnalysisService.generateMedicalReport();
  }

  /// Clear all data
  static void clearData() {
    MedicalAnalysisService.clearHistory();
    debugPrint('Medical Insights Provider: Data cleared');
  }
}

import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/fall_event.dart';

/// Service for exporting fall history to CSV files.
class FallHistoryService {
  FallHistoryService._();

  /// Export a list of FallEvents to a CSV file.
  /// Returns the file path on success, or null on failure.
  static Future<String?> exportToCsv(List<FallEvent> events) async {
    try {
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

      // CSV header row
      final List<List<dynamic>> rows = [
        [
          'Date/Time',
          'Heart Rate (BPM)',
          'Tilt Angle (°)',
          'Accel (g)',
          'Status',
          'GPS Location',
        ],
      ];

      // Data rows
      for (final event in events) {
        rows.add([
          dateFormat.format(event.time),
          event.heartRate.toInt(),
          event.tiltAngle.toStringAsFixed(1),
          event.accelMag.toStringAsFixed(2),
          event.status,
          event.gpsLocation ?? 'N/A',
        ]);
      }

      final csvString = const ListToCsvConverter().convert(rows);

      // Get the documents directory
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${directory.path}/fall_history_$timestamp.csv';

      final file = File(filePath);
      await file.writeAsString(csvString);

      debugPrint('CSV exported to: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('CSV export failed: $e');
      return null;
    }
  }
}

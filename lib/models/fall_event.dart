import 'package:intl/intl.dart';

class FallEvent {
  final DateTime time;
  final double heartRate;
  final double tiltAngle;
  final double accelMag;
  final String status;
  final String? gpsLocation;

  FallEvent({
    required this.time,
    required this.heartRate,
    required this.tiltAngle,
    this.accelMag = 0.0,
    required this.status,
    this.gpsLocation,
  });

  String get formattedTime => DateFormat('MMM dd, yyyy – hh:mm a').format(time);

  bool get isConfirmed => status == 'CONFIRMED';
}

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'location_service.dart';

class SmsService {
  SmsService._();

  static final Telephony _telephony = Telephony.instance;

  /// Sends an emergency SMS directly to the caregiver's phone number
  /// with GPS coordinates. On Android, sends via the telephony API
  /// (no user interaction needed). Falls back to opening the SMS app.
  static Future<bool> sendFallAlert({
    required String phoneNumber,
    required String patientName,
    required double heartRate,
    required double tiltAngle,
    required DateTime fallTime,
    String? gpsLocation,
    String? mapsUrl,
  }) async {
    final formattedTime = DateFormat('MMM dd, yyyy – hh:mm a').format(fallTime);

    // Fetch GPS if not provided
    String locationStr = gpsLocation ?? 'Unavailable';
    String? mapLink = mapsUrl;
    if (gpsLocation == null) {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        locationStr = LocationService.formatPosition(pos);
        mapLink = LocationService.getMapsUrl(pos);
      }
    }

    final message = StringBuffer();
    message.writeln('FALL ALERT');
    message.writeln('Patient: $patientName');
    message.writeln('Time: $formattedTime');
    message.writeln('Heart Rate: ${heartRate.toInt()} BPM');
    message.writeln('Tilt Angle: ${tiltAngle.toStringAsFixed(1)}°');
    message.writeln('GPS: $locationStr');
    if (mapLink != null) {
      message.writeln('Map: $mapLink');
    }
    message.writeln('');
    message.writeln('Immediate attention may be required!');
    message.write('- Fall Detection System (ECU SET 226)');

    final cleanNumber = phoneNumber.replaceAll(' ', '');
    final msgStr = message.toString();

    // Try direct SMS first (Android)
    try {
      final permGranted =
          await _telephony.requestPhoneAndSmsPermissions ?? false;
      if (permGranted) {
        await _telephony.sendSms(to: cleanNumber, message: msgStr);
        debugPrint('SMS sent directly to $cleanNumber');
        return true;
      }
    } catch (e) {
      debugPrint('Direct SMS failed: $e');
    }

    // Fallback: open SMS app
    return _openSmsApp(cleanNumber, msgStr);
  }

  static Future<bool> _openSmsApp(String phone, String message) async {
    final smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        return true;
      }
      await launchUrl(smsUri);
      return true;
    } catch (e) {
      debugPrint('SMS app launch failed: $e');
      return false;
    }
  }

  /// Opens the phone dialer with the caregiver's number.
  static Future<bool> callEmergency({required String phoneNumber}) async {
    final telUri = Uri(scheme: 'tel', path: phoneNumber.replaceAll(' ', ''));

    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Phone call launch failed: $e');
      return false;
    }
  }
}

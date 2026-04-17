import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'location_service.dart';
import 'permission_manager.dart';

class SmsService {
  SmsService._();

  static final Telephony _telephony = Telephony.instance;

  // Platform channel to call Android SmsManager directly
  static const MethodChannel _channel = MethodChannel('com.safebrace/sms');

  /// Sends an emergency SMS directly to the caregiver's phone number
  /// with GPS coordinates. Tries multiple methods to ensure delivery.
  /// SMS will only be sent if GPS location is successfully obtained.
  static Future<bool> sendFallAlert({
    required String phoneNumber,
    required String patientName,
    required double heartRate,
    required double tiltAngle,
    required DateTime fallTime,
    String? gpsLocation,
    String? mapsUrl,
    bool allowLaunchFallback = true,
    bool requireGps = true,
  }) async {
    final formattedTime = DateFormat('MMM dd, yyyy – hh:mm a').format(fallTime);

    // Fetch GPS if not provided - REQUIRED before sending SMS
    String locationStr = gpsLocation ?? 'Unavailable';
    String? mapLink = mapsUrl;
    bool gpsObtained = gpsLocation != null;

    if (gpsLocation == null) {
      try {
        final pos = await LocationService.getCurrentPosition();
        if (pos != null) {
          locationStr = LocationService.formatPosition(pos);
          mapLink = LocationService.getMapsUrl(pos);
          gpsObtained = true;
        }
      } catch (e) {
        debugPrint('GPS lookup failed for SMS: $e');
      }
    }

    // If GPS is required but not obtained, cancel SMS send
    if (requireGps && !gpsObtained) {
      debugPrint('SMS cancelled: GPS location required but unavailable');
      return false;
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

    // Ensure SMS permission is granted (Android only). If this fails,
    // we will still fall back to opening the SMS app.
    bool hasPermission = await PermissionManager.requestSmsPermission();
    if (!hasPermission) {
      try {
        final permFuture = _telephony.requestPhoneAndSmsPermissions;
        hasPermission = (await permFuture) ?? false;
      } catch (e) {
        debugPrint('telephony permission request failed: $e');
      }
    }

    if (hasPermission) {
      // Method 1: Native Android SmsManager via platform channel (most reliable)
      try {
        final result = await _channel.invokeMethod('sendSms', {
          'phone': cleanNumber,
          'message': msgStr,
        });
        if (result == true) {
          debugPrint('SMS sent via native SmsManager to $cleanNumber');
          return true;
        }
      } catch (e) {
        debugPrint('Native SmsManager failed: $e');
      }

      // Method 2: Telephony plugin
      try {
        await _telephony.sendSms(to: cleanNumber, message: msgStr);
        debugPrint('SMS sent via telephony plugin to $cleanNumber');
        return true;
      } catch (e) {
        debugPrint('Telephony plugin sendSms failed: $e');
      }
    } else {
      debugPrint('SMS permission not granted');
    }

    // Method 3: Open SMS app with message pre-filled (last resort)
    if (allowLaunchFallback) {
      return _openSmsApp(cleanNumber, msgStr);
    }
    return false;
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

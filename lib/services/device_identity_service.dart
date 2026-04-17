import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  DeviceIdentityService._();

  static const String _prefDeviceId = 'app_device_id';
  static const Uuid _uuid = Uuid();

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefDeviceId);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final next = _uuid.v4();
    await prefs.setString(_prefDeviceId, next);
    return next;
  }
}

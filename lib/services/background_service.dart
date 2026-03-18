import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Background service that keeps the BLE connection & fall monitoring active
/// even when the app is minimized. Uses a persistent Android foreground
/// notification so the OS doesn't kill the process.
class BackgroundMonitorService {
  BackgroundMonitorService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Initialize and configure the background service.
  /// Call once in main() before runApp().
  static Future<void> initialize() async {
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: false,
        foregroundServiceNotificationId: 226,
        initialNotificationTitle: 'Fall Detection Active',
        initialNotificationContent: 'Monitoring for falls in background',
        foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
      ),
    );
  }

  /// Start background monitoring.
  static Future<void> start() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      debugPrint('BackgroundService: Started');
    }
  }

  /// Stop background monitoring.
  static Future<void> stop() async {
    _service.invoke('stop');
    debugPrint('BackgroundService: Stopped');
  }

  /// Check if service is running.
  static Future<bool> isRunning() => _service.isRunning();

  /// Update the notification with current status.
  static void updateNotification({
    required String title,
    required String content,
  }) {
    _service.invoke('update', {'title': title, 'content': content});
  }
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}

/// Service entry point (runs in isolate on Android)
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) {
      service.stopSelf();
    });

    service.on('update').listen((data) {
      if (data != null) {
        service.setForegroundNotificationInfo(
          title: data['title'] ?? 'Fall Detection Active',
          content: data['content'] ?? 'Monitoring...',
        );
      }
    });

    // Keep-alive timer: update notification periodically
    Timer.periodic(const Duration(seconds: 30), (_) {
      service.setForegroundNotificationInfo(
        title: 'Fall Detection Active',
        content: 'Monitoring for falls...',
      );
    });
  }
}

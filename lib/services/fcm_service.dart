import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class FcmService {
  FcmService._();

  static bool _initialized = false;
  static final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get tapStream => _tapController.stream;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('FCM permission setup failed: $e');
    }

    await syncToken();

    messaging.onTokenRefresh.listen((token) async {
      await syncToken(token: token);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.data}');
      if (message.data.isNotEmpty) {
        _tapController.add(message.data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      _tapController.add(data);
      unawaited(_openMapsIfAvailable(data));
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null && initialMessage.data.isNotEmpty) {
      final data = initialMessage.data;
      _tapController.add(data);
      unawaited(_openMapsIfAvailable(data));
    }
  }

  static Future<void> syncToken({String? token}) async {
    try {
      final nextToken = token ?? await FirebaseMessaging.instance.getToken();
      if (nextToken == null || nextToken.isEmpty) return;
      await FirestoreService.saveMessagingToken(nextToken);
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }

  static Future<void> _openMapsIfAvailable(Map<String, dynamic> data) async {
    final mapsUrl = (data['mapsUrl'] ?? data['maps_url'] ?? '').toString();
    if (mapsUrl.isEmpty) return;

    final uri = Uri.tryParse(mapsUrl);
    if (uri == null) return;

    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static void dispose() {
    _tapController.close();
  }
}

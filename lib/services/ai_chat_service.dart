import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_state.dart';

class AiChatService {
  // Backend proxy URL — set this to your deployed backend
  // For local development: http://localhost:3000
  // For production: https://your-backend-url.com
  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  bool get isConfigured => _backendUrl.isNotEmpty;

  static const String _systemPrompt = '''
You are a helpful health & safety assistant embedded in a Fall Detection app.

The app monitors elderly or at-risk patients using an Arduino Nano 33 BLE Sense
wearable sensor that streams heart rate, tilt angle, and acceleration data in real
time over Bluetooth Low Energy.

Your capabilities:
• Answer questions about fall prevention, post-fall care, and when to seek emergency help.
• Explain the sensor readings (heart rate, tilt angle, acceleration magnitude).
• Give general wellness tips for elderly care.
• Help troubleshoot Bluetooth connectivity or device issues.
• Explain how the fall detection algorithm works (impact detection, free-fall
  phase, and post-impact orientation check).

Important rules:
• You are NOT a doctor. Always recommend consulting a healthcare professional for
  medical decisions.
• Keep answers concise and easy to understand.
• Be empathetic and reassuring — users may be stressed during or after a fall event.
• If asked about things unrelated to health, safety, or the app, politely redirect.
''';

  /// Build a context string so the AI knows the current device state.
  String _buildContext(AppState state) {
    final parts = <String>[];

    if (state.isBleConnected) {
      parts.add('Device: connected (${state.bleDeviceName ?? "Arduino"})');
      parts.add('Heart rate: ${state.heartRate.toStringAsFixed(0)} bpm');
      if (state.spo2 > 0) {
        parts.add('SpO2: ${state.spo2.toStringAsFixed(1)}%');
      }
      parts.add('Tilt angle: ${state.tiltAngle.toStringAsFixed(1)}°');
      parts.add('Accel magnitude: ${state.accelMag.toStringAsFixed(2)} g');
      if (state.batteryLevel >= 0) {
        parts.add('Battery: ${state.batteryLevel.toStringAsFixed(0)}%');
      }
    } else {
      parts.add('Device: not connected');
    }

    parts.add('Alert active: ${state.alertActive}');
    parts.add(
      'Total confirmed falls: '
      '${state.fallHistory.where((e) => e.status == "CONFIRMED").length}',
    );

    return '[Current device state]\n${parts.join('\n')}';
  }

  /// Send a user message via the backend proxy.
  Future<String> sendMessage(String userMessage, AppState state) async {
    if (_backendUrl.isEmpty) {
      return _offlineFactResponse(userMessage, state);
    }

    return _sendViaBackend(userMessage, state);
  }

  Future<String> _sendViaBackend(String userMessage, AppState state) async {
    final contextBlock = _buildContext(state);
    final prompt = '$contextBlock\n\nUser: $userMessage';

    final uri = Uri.parse('$_backendUrl/api/chat');

    final body = jsonEncode({
      'message': prompt,
      'systemPrompt': _systemPrompt,
      'model': 'llama-3.1-8b-instant',
    });

    try {
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Backend request failed: ${response.statusCode} ${response.body}',
        );
        return 'Backend error (${response.statusCode}). '
            'Please check backend URL and internet connection.';
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['success'] != true) {
        final error = decoded['error'] ?? 'Unknown error';
        return 'AI service error: $error';
      }

      final reply = decoded['reply'];
      if (reply is String && reply.trim().isNotEmpty) {
        return reply.trim();
      }

      return 'Sorry, I could not generate a response.';
    } catch (e) {
      debugPrint('Backend request error: $e');
      return _offlineFactResponse(userMessage, state);
    }
  }

  String _offlineFactResponse(String userMessage, AppState state) {
    final q = userMessage.toLowerCase();
    final connected = state.isBleConnected ? 'Connected' : 'Not connected';
    final hr = state.heartRate.toStringAsFixed(0);
    final tilt = state.tiltAngle.toStringAsFixed(1);
    final acc = state.accelMag.toStringAsFixed(2);
    final spo2 = state.spo2 > 0 ? '${state.spo2.toStringAsFixed(1)}%' : '/';
    final battery = state.batteryLevel > 0
        ? '${state.batteryLevel.toStringAsFixed(0)}%'
        : '/';

    if (q.contains('status') || q.contains('device') || q.contains('sensor')) {
      return 'Current device status:\n'
          '- BLE: $connected\n'
          '- Heart rate: $hr bpm\n'
          '- SpO2: $spo2\n'
          '- Tilt angle: $tilt deg\n'
          '- Acceleration: $acc g\n'
          '- Battery: $battery\n\n'
          'These are direct app readings (not medical diagnosis).';
    }

    if (q.contains('fall') || q.contains('detected') || q.contains('alert')) {
      return 'Fact-based fall guidance:\n'
          '1. If the person is unconscious, has severe pain, bleeding, chest pain, or breathing trouble, call emergency services now.\n'
          '2. Do not move the person if head/neck/spine injury is suspected.\n'
          '3. If safe, keep them warm and monitor breathing until help arrives.\n'
          '4. Confirm or cancel the app alert based on real condition.';
    }

    if (q.contains('heart') || q.contains('bpm')) {
      return 'Heart-rate fact from device: $hr bpm.\n'
          'General reference for adults at rest is often around 60-100 bpm, but individual ranges vary. '
          'Use symptoms and clinician advice for decisions.';
    }

    if (q.contains('bluetooth') || q.contains('connect')) {
      return 'BLE troubleshooting steps:\n'
          '1. Keep phone near device.\n'
          '2. Ensure Bluetooth is ON.\n'
          '3. Rescan in the Bluetooth Devices screen.\n'
          '4. If stuck, tap Disconnect then reconnect.\n'
          '5. Check battery and permissions.';
    }

    return 'I am running in offline factual mode (no cloud AI key). '
        'Ask about: device status, fall response, heart rate, or Bluetooth troubleshooting.';
  }

  /// Reset conversation history.
  void resetChat() {
    // No server-side chat session to reset when using Groq via HTTP.
  }
}

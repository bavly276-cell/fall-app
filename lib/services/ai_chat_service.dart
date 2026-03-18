import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'app_state.dart';

class AiChatService {
  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  bool get isConfigured => _apiKey.isNotEmpty;

  GenerativeModel? _model;
  ChatSession? _chat;

  AiChatService() {
    if (_apiKey.isEmpty) {
      return;
    }

    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 1024,
      ),
      systemInstruction: Content.system(_systemPrompt),
    );
    _chat = _model!.startChat();
  }

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

  /// Send a user message and stream back the AI response.
  Future<String> sendMessage(String userMessage, AppState state) async {
    if (_chat == null) {
      return _offlineFactResponse(userMessage, state);
    }

    final contextBlock = _buildContext(state);
    final prompt = '$contextBlock\n\nUser: $userMessage';

    try {
      final response = await _chat!.sendMessage(Content.text(prompt));
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      debugPrint('Gemini request failed: $e');
      final lower = e.toString().toLowerCase();
      final quotaOrRateIssue =
          lower.contains('quota') ||
          lower.contains('rate limit') ||
          lower.contains('429') ||
          lower.contains('resource_exhausted');

      if (quotaOrRateIssue) {
        return 'Gemini quota is currently unavailable for this key. '
            'I switched to offline assistance mode for now.\n\n'
            '${_offlineFactResponse(userMessage, state)}';
      }

      return 'AI service unavailable right now. Please verify GEMINI_API_KEY and internet connection.';
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

    return 'I am running in offline factual mode (no Gemini key). '
        'Ask about: device status, fall response, heart rate, or Bluetooth troubleshooting.';
  }

  /// Reset conversation history.
  void resetChat() {
    if (_model != null) {
      _chat = _model!.startChat();
    }
  }
}

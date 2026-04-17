import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import 'app_state.dart';
import 'medical_analysis_service.dart';

const String _defaultGeminiModel = 'gemini-flash-lite-latest';
const List<String> _fallbackGeminiModels = <String>[
  'gemini-flash-lite-latest',
  'gemini-2.5-flash-lite',
  'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-1.5-flash',
  'gemini-1.5-flash-latest',
];

class AiChatService {
  late final String _apiKey;
  late final String _modelName;
  GenerativeModel? _model;
  ChatSession? _chatSession;

  AiChatService() {
    // Try to read from environment first (favored for security), fallback to placeholders
    _apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    _modelName = const String.fromEnvironment(
      'AI_MODEL',
      defaultValue: _defaultGeminiModel,
    );

    if (isConfigured) {
      _model = _buildModel(_modelName);
    }
  }

  bool get _looksLikePlaceholder =>
      _apiKey == 'YOUR_GEMINI_API_KEY_HERE' ||
      _apiKey == 'YOUR_GEMINI_API_KEY' ||
      _apiKey == 'YOUR_API_KEY';

  bool get _looksLikeOpenAiKey => _apiKey.startsWith('sk-');

  bool get isConfigured =>
      _apiKey.isNotEmpty &&
      !_looksLikePlaceholder &&
      !_looksLikeOpenAiKey &&
      !isDemoMode;

  bool get isDemoMode => _apiKey == 'DEMO';

  String get statusLabel {
    if (isDemoMode) return 'AI Simulation (No Key)';
    if (_looksLikeOpenAiKey) return 'Invalid key type (Gemini key required)';
    if (!isConfigured) return 'Offline mode';
    return 'Gemini AI active';
  }

  GenerativeModel _buildModel(String name) {
    return GenerativeModel(
      model: name,
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 1024,
      ),
    );
  }

  static const String _systemPrompt = '''
You are "SafeWatch AI", an advanced, deep-learning based medical & safety assistant embedded in a Fall Detection app.
Your objective is to help caregivers and patients understand sensor data, recognize health risks, and troubleshoot the hardware.

CONTEXTUAL AWARENESS:
The app uses an ESP32-C3 wearable with MPU6050 (motion) and MAX30102 (heart/SpO2).
You will be provided with real-time "Sensor Data Context" and a "Medical Analysis Report".

YOUR CAPABILITIES:
1. SENSOR ANALYSIS: Explain what current Heart Rate, SpO2, and Accel readings mean.
2. RISK ASSESSMENT: Interpret the Medical Analysis Report (Low/Moderate/High risk).
3. TROUBLESHOOTING: Help with Bluetooth connectivity or sensor placement issues.
4. GENERAL HEALTH: Discuss geriatric care, fall prevention, and post-fall safety.

CRITICAL RULES:
- IMPORTANT: You are NOT a doctor. Always include a disclaimer for serious medical issues.
- If a fall was recently detected, prioritize emergency guidance (CAB - Circulation, Airway, Breathing).
- Be empathetic, professional, and clear. Avoid overly technical jargon unless asked.
- Keep responses concise but information-rich.
''';

  /// Build a context string combining raw sensor data and deep medical analysis.
  String _buildRichContext(AppState state) {
    final parts = <String>[];

    // Part 1: Raw Sensor State
    parts.add('--- RAW SENSOR DATA ---');
    if (state.isBleConnected) {
      parts.add('Device: Connected (${state.bleDeviceName})');
      parts.add('Heart Rate: ${state.heartRate.toStringAsFixed(0)} BPM');
      parts.add(
        'SpO2: ${state.spo2 > 0 ? "${state.spo2.toStringAsFixed(1)}%" : "Unknown"}',
      );
      parts.add('Tilt: ${state.tiltAngle.toStringAsFixed(1)}°');
      parts.add('Accel: ${state.accelMag.toStringAsFixed(2)}g');
      parts.add('Battery: ${state.batteryLevel.toStringAsFixed(0)}%');
    } else {
      parts.add('Device: Disconnected');
    }

    // Part 2: Deep Medical Analysis (The "AI" part)
    parts.add('\n--- MEDICAL ANALYSIS REPORT ---');
    final analysis = MedicalAnalysisService.generateMedicalReport();
    final risk = analysis['risk_assessment'] as RiskAssessment;

    parts.add(
      'Risk Level: ${risk.riskLevel} (Score: ${risk.overallRiskScore}/100)',
    );
    if (risk.riskFactors.isNotEmpty) {
      parts.add('Risk Factors: ${risk.riskFactors.join(", ")}');
    }

    final trends = analysis['trends'] as Map<String, TrendAnalysis>;
    parts.add('HR Trend: ${trends['heart_rate']?.trendDirection ?? "Stable"}');
    parts.add(
      'SpO2 Trend: ${trends['oxygen_saturation']?.trendDirection ?? "Stable"}',
    );

    final correlations = analysis['correlations'] as List<Correlation>;
    if (correlations.isNotEmpty) {
      parts.add(
        'Correlations Found: ${correlations.map((c) => "${c.cause} -> ${c.result}").join("; ")}',
      );
    }

    return parts.join('\n');
  }

  /// Send a user message to Gemini (or simulated engine).
  Future<String> sendMessage(String userMessage, AppState state) async {
    if (isDemoMode) {
      return _generateSimulatedResponse(userMessage, state);
    }

    if (_looksLikeOpenAiKey) {
      return 'Your configured key looks like an OpenAI key, but this chat uses Gemini.\n\n'
          'Please set GEMINI_API_KEY in your dart-define file, then relaunch the app with --dart-define-from-file.';
    }

    if (!isConfigured) {
      return _offlineFactResponse(userMessage, state);
    }

    try {
      _model ??= _buildModel(_modelName);

      // Initialize chat session if it doesn't exist
      _chatSession ??= _model!.startChat(
        history: [
          Content.text(_systemPrompt),
          Content.model([
            TextPart('Understood. I am SafeWatch AI, ready to assist.'),
          ]),
        ],
      );

      final context = _buildRichContext(state);
      final fullPrompt =
          '''
[CURRENT DATA CONTEXT]
$context

[USER QUESTION]
$userMessage
''';

      final response = await _chatSession!
          .sendMessage(Content.text(fullPrompt))
          .timeout(const Duration(seconds: 20));
      final text = response.text;

      if (text == null || text.isEmpty) {
        return 'I received an empty response. Please try again.';
      }

      return text;
    } catch (e) {
      // Reset session after transport/model errors to avoid sticky broken state.
      _chatSession = null;
      if (_isTransientAiError(e)) {
        final retry = await _retryTransientError(userMessage, state);
        if (retry != null) return retry;
      }
      if (_isLikelyModelNameError(e)) {
        final retry = await _retryWithFallbackModel(userMessage, state);
        if (retry != null) return retry;
      }
      debugPrint('Gemini request failed after retries: $e');
      final fallback = await _generateSimulatedResponse(userMessage, state);
      return fallback;
    }
  }

  bool _isLikelyModelNameError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('404') ||
        msg.contains('not found') ||
        msg.contains('unsupported model');
  }

  bool _isTransientAiError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('503') ||
        msg.contains('429') ||
        msg.contains('unavailable') ||
        msg.contains('high demand') ||
        msg.contains('rate limit') ||
        msg.contains('resource exhausted') ||
        msg.contains('deadline exceeded') ||
        msg.contains('timeout');
  }

  Future<String?> _retryTransientError(
    String userMessage,
    AppState state,
  ) async {
    final candidateModels = <String>[
      _modelName,
      ..._fallbackGeminiModels.where((m) => m != _modelName),
    ];

    for (final model in candidateModels) {
      for (final delayMs in const <int>[600, 1400]) {
        try {
          _model = _buildModel(model);
          _chatSession = _model!.startChat(
            history: [
              Content.text(_systemPrompt),
              Content.model([
                TextPart('Understood. I am SafeWatch AI, ready to assist.'),
              ]),
            ],
          );

          final context = _buildRichContext(state);
          final fullPrompt =
              '''
[CURRENT DATA CONTEXT]
$context

[USER QUESTION]
$userMessage
''';

          final response = await _chatSession!
              .sendMessage(Content.text(fullPrompt))
              .timeout(const Duration(seconds: 20));
          final text = response.text;
          if (text != null && text.isNotEmpty) {
            return text;
          }
        } catch (e) {
          if (!_isTransientAiError(e) && !_isLikelyModelNameError(e)) {
            break;
          }
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    return null;
  }

  Future<String?> _retryWithFallbackModel(
    String userMessage,
    AppState state,
  ) async {
    for (final model in _fallbackGeminiModels) {
      if (model == _modelName) continue;
      try {
        _model = _buildModel(model);
        _chatSession = _model!.startChat(
          history: [
            Content.text(_systemPrompt),
            Content.model([
              TextPart('Understood. I am SafeWatch AI, ready to assist.'),
            ]),
          ],
        );

        final context = _buildRichContext(state);
        final fullPrompt =
            '''
[CURRENT DATA CONTEXT]
$context

[USER QUESTION]
$userMessage
''';

        final response = await _chatSession!
            .sendMessage(Content.text(fullPrompt))
            .timeout(const Duration(seconds: 20));
        final text = response.text;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      } catch (_) {
        // Try the next known-good model.
      }
    }
    return null;
  }

  /// Generates a state-aware smart response without calling an external API.
  Future<String> _generateSimulatedResponse(
    String userMessage,
    AppState state,
  ) async {
    // Artificial delay to feel like "Deep Learning"
    await Future.delayed(const Duration(milliseconds: 1500));

    final q = userMessage.toLowerCase();
    final analysis = MedicalAnalysisService.generateMedicalReport();
    final risk = analysis['risk_assessment'] as RiskAssessment;
    final hr = state.heartRate.toStringAsFixed(0);
    final spo2 = state.spo2.toStringAsFixed(1);

    final usingConfiguredKey = isConfigured;
    String greeting = usingConfiguredKey
        ? 'SafeWatch AI cloud service is temporarily busy. I can still provide local analysis from your app data.'
        : "I am SafeWatch AI (Simulation Mode). I have analyzed your medical report.";
    String medicalContext =
        "Your current Risk Level is **${risk.riskLevel}** (${risk.overallRiskScore.toStringAsFixed(1)}/100).";

    if (q.contains('status') ||
        q.contains('health') ||
        q.contains('report') ||
        q.contains('analyze')) {
      String factors = risk.riskFactors.isNotEmpty
          ? "\n\n**Identified Risk Factors:**\n- ${risk.riskFactors.join('\n- ')}"
          : "\n\nVital signs are currently within acceptable limits.";

      final recommendation = risk.overallRiskScore > 40
          ? "Your baseline risk is elevated. Avoid stairs and ensure your caregiver is notified."
          : "Continue regular activity. Sensors are monitoring correctly.";

      return "$greeting\n\n$medicalContext\n"
          "**Live Vitals:**\n"
          "- Heart Rate: $hr BPM\n"
          "- Oxygen (SpO2): $spo2%\n"
          "- Motion Stability: ${state.tiltAngle < 30 ? 'Stable' : 'Tilted'}\n"
          "$factors\n\n"
          "**Recommendation:** $recommendation";
    }

    if (q.contains('fall') || q.contains('happen')) {
      return "$greeting\n\nI see you are asking about fall safety. "
          "My analysis shows **${analysis['total_falls']} total falls** in your history. "
          "If you feel dizzy right now, please sit down immediately. "
          "Should a fall occur, I will automatically trigger a 20-second countdown before alerting your caregiver.";
    }

    if (q.contains('spo2') ||
        q.contains('oxygen') ||
        q.contains('hr') ||
        q.contains('heart')) {
      final trends = analysis['trends'] as Map<String, TrendAnalysis>;
      final hrTrend = trends['heart_rate']?.trendDirection ?? 'Stable';
      return "$greeting\n\nAnalyzing vital trends...\n"
          "- Heart Rate is currently **$hr BPM** ($hrTrend trend).\n"
          "- Oxygen Saturation is **$spo2%**.\n\n"
          "Current data suggests your cardiovascular system is responding normally to your environment. "
          "Remember, I am an AI, not a clinician. Consult a doctor for diagnostic advice.";
    }

    if (usingConfiguredKey) {
      return "$greeting\n\nI've processed your message using local on-device analysis because Gemini is currently overloaded. "
          'Please try again in a few seconds for a live cloud response.';
    }

    return "$greeting\n\nI've processed your message but I'm currently running in **Simulation Mode** without an active API key. "
        "I can still provide deep analysis of your health report, device status, or fall history. "
        "\n\nTo unlock my full conversational abilities, please add a `GEMINI_API_KEY` to your configuration.";
  }

  Future<String> _offlineFactResponse(
    String userMessage,
    AppState state,
  ) async {
    return _generateSimulatedResponse(userMessage, state);
  }

  void resetChat() {
    _chatSession = null;
  }
}

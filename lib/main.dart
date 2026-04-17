import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/startup_clock_screen.dart';
import 'services/app_state.dart';
import 'services/background_service.dart';
import 'utils/theme.dart';
import 'widgets/app_lifecycle_service_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const FallDetectionApp(),
    ),
  );

  // Keep startup fast: do remote/service initialization after first frame.
  unawaited(_bootstrapServices(appState));
}

Future<void> _bootstrapServices(AppState appState) async {
  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Background service only works on Android/iOS
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await BackgroundMonitorService.initialize().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('Background service init failed: $e');
    }
  }

  // Load cloud data if Firebase is ready
  if (Firebase.apps.isNotEmpty) {
    try {
      await appState.initFirebase().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Firestore sync failed: $e');
    }
  }
}

class FallDetectionApp extends StatelessWidget {
  const FallDetectionApp({super.key});

  static final ThemeData _lightTheme = AppTheme.lightTheme();
  static final ThemeData _darkTheme = AppTheme.darkTheme();

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, s) => s.isDarkMode,
      builder: (context, isDarkMode, _) {
        return MaterialApp(
          title: 'Safe Brace',
          debugShowCheckedModeBanner: false,
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          themeAnimationDuration: const Duration(milliseconds: 220),
          themeAnimationCurve: Curves.easeInOut,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: const AppLifecycleServiceBridge(child: StartupClockScreen()),
        );
      },
    );
  }
}

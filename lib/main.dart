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

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'SafeWatch Fall Detection',
      debugShowCheckedModeBanner: false,
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 1),
      themeAnimationCurve: Curves.linear,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: const StartupClockScreen(),
    );
  }
}

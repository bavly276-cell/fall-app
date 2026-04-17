import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'home_screen.dart';
import 'patient_onboarding_screen.dart';

class StartupClockScreen extends StatefulWidget {
  const StartupClockScreen({super.key});

  @override
  State<StartupClockScreen> createState() => _StartupClockScreenState();
}

class _StartupClockScreenState extends State<StartupClockScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _introController;
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _routeTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      final firstRun =
          !appState.onboardingComplete ||
          appState.patientName == 'Patient Name' ||
          appState.patientPhone.isEmpty;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              firstRun ? const PatientOnboardingScreen() : const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: fade, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    _logoController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withAlpha(40),
              theme.colorScheme.surface,
              theme.colorScheme.secondary.withAlpha(28),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _introController,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(
                  parent: _introController,
                  curve: Curves.easeOutBack,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, _) {
                      final t = _logoController.value;
                      final wave = math.sin(t * 2 * math.pi);
                      final pulse = (0.55 + 0.45 * math.sin(t * 2 * math.pi))
                          .abs();
                      final heartbeat = (0.6 + 0.4 * math.sin(t * 4 * math.pi))
                          .abs();

                      return SizedBox(
                        width: 240,
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 220,
                              height: 78,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(44),
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary.withAlpha(55),
                                    theme.colorScheme.primary.withAlpha(26),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              child: Transform.rotate(
                                angle: 0.03 * wave,
                                child: _bandLoop(theme, flipped: false),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              child: Transform.rotate(
                                angle: -0.03 * wave,
                                child: _bandLoop(theme, flipped: true),
                              ),
                            ),
                            Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary.withAlpha(
                                  (48 + 90 * pulse).toInt(),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withAlpha(
                                      (55 + 70 * pulse).toInt(),
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 94,
                              height: 94,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withAlpha(
                                    140,
                                  ),
                                  width: 2,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.watch,
                                    size: 28,
                                    color: theme.colorScheme.primary,
                                  ),
                                  Positioned(
                                    bottom: 20,
                                    child: SizedBox(
                                      width: 44,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: LinearProgressIndicator(
                                          value: 0.2 + 0.75 * heartbeat,
                                          minHeight: 5,
                                          backgroundColor: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                theme.colorScheme.primary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'ECU',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bandLoop(ThemeData theme, {required bool flipped}) {
    final transform = Matrix4.identity();
    if (flipped) {
      transform.scale(-1.0, 1.0, 1.0);
    }

    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: Container(
        width: 68,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.primary.withAlpha(110),
            width: 1.6,
          ),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surfaceContainerHighest,
              theme.colorScheme.surface,
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/permission_manager.dart';
import '../services/ble_service.dart';
import '../services/firestore_service.dart';
import '../widgets/alert_card.dart';
import '../widgets/heart_rate_widget.dart';
import '../widgets/device_status_widget.dart';
import '../widgets/app_bottom_nav.dart';
import 'device_scan_screen.dart';
import 'kids_tracking_screen.dart';
import 'medical_analytics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final List<Animation<double>> _fadeAnims;
  late final List<Animation<Offset>> _slideAnims;

  static const int _itemCount = 9;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnims = List.generate(_itemCount, (i) {
      final start = i * 0.12;
      final end = (start + 0.35).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      );
    });

    _slideAnims = List.generate(_itemCount, (i) {
      final start = i * 0.12;
      final end = (start + 0.35).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.12),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _staggerController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        await PermissionManager.requestAllPermissions();

        // Best-effort: auto-connect to last known ESP32 on app open.
        // Run after permission prompts to avoid overlapping permission requests.
        if (!mounted) return;
        await context.read<AppState>().tryAutoConnectToLastDevice();

        // Setup GPS callback for kids mode (NEW)
        if (!mounted) return;
        final appState = context.read<AppState>();
        BleService.setGpsDataCallback((lat, lon, valid) {
          appState.updateKidsGpsLocation(lat, lon, valid);

          // Auto-save to Firebase if kids mode enabled
          if (valid && lat != null && lon != null && appState.kidsModeEnabled) {
            FirestoreService.saveKidsLocation(latitude: lat, longitude: lon);
          }
        });
      }());
    });
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  Widget _animatedItem(int index, Widget child) {
    if (index < 0 ||
        index >= _fadeAnims.length ||
        index >= _slideAnims.length) {
      return child;
    }
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(position: _slideAnims[index], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final alertActive = context.select<AppState, bool>((s) => s.alertActive);
    final isBleConnected = context.select<AppState, bool>(
      (s) => s.isBleConnected,
    );
    final isBleReconnecting = context.select<AppState, bool>(
      (s) => s.isBleReconnecting,
    );
    final confirmedFalls = context.select<AppState, int>(
      (s) => s.fallHistory.where((e) => e.status == 'CONFIRMED').length,
    );
    final falseAlarms = context.select<AppState, int>(
      (s) => s.fallHistory.where((e) => e.status == 'FALSE ALARM').length,
    );
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final heroGradient = LinearGradient(
      colors: [theme.colorScheme.tertiary, theme.colorScheme.primary],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Safe Brace',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: isDarkMode ? 'Light mode' : 'Dark mode',
            icon: Icon(
              isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () {
              appState.toggleTheme();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _animatedItem(
              0,
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: heroGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.health_and_safety_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safe Brace',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Realtime fall + vital monitoring',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Alert card
            AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              child: alertActive
                  ? const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: AlertCard(),
                    )
                  : const SizedBox.shrink(),
            ),

            // Connect Device Button (when no device connected)
            if (!isBleConnected && !isBleReconnecting)
              _animatedItem(
                1,
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeviceScanScreen(),
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.surfaceContainerHigh
                              : theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.outline.withAlpha(120),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.bluetooth_searching_rounded,
                                color: theme.colorScheme.tertiary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connect Your Device',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap to scan for your ESP32 wearable',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Device status
            _animatedItem(
              2,
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: DeviceStatusWidget(),
              ),
            ),

            // Heart rate
            _animatedItem(
              3,
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: HeartRateWidget(),
              ),
            ),

            // AI Brain Status (NEW)
            _animatedItem(
              4,
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Consumer<AppState>(
                  builder: (context, appState, _) {
                    final prob = appState.aiFallProbability;
                    final label = appState.aiLabel;
                    Color color;
                    if (prob > 0.8) {
                      color = Colors.red;
                    } else if (prob > 0.5) {
                      color = Colors.orange;
                    } else {
                      color = Colors.blue;
                    }

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withAlpha(30),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.psychology_rounded,
                                color: color,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'SafeWatch AI Brain',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${(prob * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: prob,
                                      backgroundColor: color.withAlpha(30),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        color,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Kids Mode Card (NEW)
            _animatedItem(
              5,
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Consumer<AppState>(
                  builder: (context, appState, _) {
                    final kidsModeOn = appState.kidsModeEnabled;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: kidsModeOn
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const KidsTrackingScreen(),
                                ),
                              )
                            : null,
                        child: Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: kidsModeOn
                                  ? LinearGradient(
                                      colors: [
                                        Colors.purple.withOpacity(0.1),
                                        Colors.pink.withOpacity(0.05),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kidsModeOn
                                        ? Colors.purple.withAlpha(40)
                                        : Colors.grey.withAlpha(20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.location_history,
                                    color: kidsModeOn
                                        ? Colors.purple
                                        : Colors.grey,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Kids Mode',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        kidsModeOn
                                            ? 'Live GPS tracking enabled'
                                            : 'Enable to track location',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: kidsModeOn,
                                  onChanged: (val) {
                                    if (val) {
                                      appState.enableKidsMode();
                                      // Request GPS subscription
                                      if (BleService.isConnected) {
                                        BleService.subscribeGpsData(
                                          onGpsData: (lat, lon, valid) {
                                            appState.updateKidsGpsLocation(
                                              lat,
                                              lon,
                                              valid,
                                            );
                                            if (valid &&
                                                lat != null &&
                                                lon != null) {
                                              FirestoreService.saveKidsLocation(
                                                latitude: lat,
                                                longitude: lon,
                                              );
                                            }
                                          },
                                        );
                                      }
                                    } else {
                                      appState.disableKidsMode();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Medical Analytics Card (NEW)
            _animatedItem(
              6,
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MedicalAnalyticsScreen(),
                      ),
                    ),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              Colors.teal.withOpacity(0.1),
                              Colors.cyan.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.teal.withAlpha(40),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.analytics_rounded,
                                color: Colors.teal,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Medical Analytics',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Risk analysis & health trends',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Stats row
            _animatedItem(
              7,
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        icon: Icons.warning_rounded,
                        value: confirmedFalls,
                        label: 'Total Falls',
                        color: Colors.red,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _statCard(
                        icon: Icons.info_outline_rounded,
                        value: falseAlarms,
                        label: 'False Alarms',
                        color: Colors.orange,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Simulate button
            _animatedItem(
              8,
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => appState.simulateFall(),
                  icon: const Icon(Icons.warning_rounded, size: 22),
                  label: const Text(
                    'SIMULATE FALL EVENT',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _statCard({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                value.toString(),
                key: ValueKey(value),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

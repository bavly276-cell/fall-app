import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class HeartRateWidget extends StatelessWidget {
  const HeartRateWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final theme = Theme.of(context);
    final hr = state.heartRate;
    final hasData = state.isBleConnected && hr > 0;

    Color hrColor = !hasData
        ? theme.colorScheme.onSurfaceVariant
        : hr < 100
        ? Colors.teal
        : hr < 120
        ? theme.colorScheme.tertiary
        : theme.colorScheme.error;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hrColor.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.favorite_rounded, color: hrColor, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      hasData ? '${hr.toInt()} BPM' : '-- BPM',
                      key: ValueKey(hasData ? hr.toInt() : -1),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: hrColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasData
                        ? 'Heart Rate (MAX30102)'
                        : state.isBleConnected
                        ? 'Waiting for heart rate data...'
                        : 'Connect device to monitor',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _sensorChip(
                  'Tilt',
                  state.isBleConnected
                      ? '${state.tiltAngle.toStringAsFixed(1)}°'
                      : '--',
                  theme,
                ),
                const SizedBox(height: 6),
                _sensorChip(
                  '|a|',
                  state.isBleConnected
                      ? '${state.accelMag.toStringAsFixed(2)}g'
                      : '--',
                  theme,
                ),
                const SizedBox(height: 6),
                _sensorChip(
                  'SpO2',
                  state.isBleConnected && state.spo2 > 0
                      ? '${state.spo2.toStringAsFixed(1)}%'
                      : '--',
                  theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorChip(String label, String value, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

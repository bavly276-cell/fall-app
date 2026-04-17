import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class AlertCard extends StatelessWidget {
  const AlertCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final theme = Theme.of(context);
    if (!state.alertActive) return const SizedBox.shrink();

    final secondsLeft = context.select<AppState, int>(
      (s) => s.alertSecondsRemaining,
    );

    return Card(
      color: theme.colorScheme.errorContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Text(
                  'FALL DETECTED!',
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Consumer<AppState>(
              builder: (context, state, _) => Column(
                children: [
                  Text(
                    'HR: ${state.heartRate.toInt()} BPM  |  Tilt: ${state.tiltAngle.toStringAsFixed(1)}°  |  Accel: ${state.accelMag.toStringAsFixed(2)}g',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer.withAlpha(200),
                      fontSize: 13,
                    ),
                  ),
                  if (state.lastGpsLocation != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: theme.colorScheme.onErrorContainer.withAlpha(
                            170,
                          ),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            state.lastGpsLocation!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer
                                  .withAlpha(170),
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (secondsLeft > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  (state.smsAlertEnabled && state.autoSmsOnConfirm)
                      ? 'Auto-SMS will be sent in ${secondsLeft}s unless cancelled'
                      : 'Auto-confirming in ${secondsLeft}s unless cancelled',
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer.withAlpha(170),
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Confirm / False Alarm buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () => state.confirmFall(),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                    onPressed: () => state.cancelAlert(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text(
                      'False Alarm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // SMS & Call emergency buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: state.smsSending
                        ? null
                        : () async {
                            final success = await state.sendSmsAlert();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'SMS alert sent'
                                        : state.lastSmsError ?? 'SMS failed',
                                  ),
                                  backgroundColor: success
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              );
                            }
                          },
                    icon: state.smsSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sms, size: 18),
                    label: const Text('Send SMS'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () async {
                      final success = await state.callCaregiver();
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open phone dialer'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Call'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

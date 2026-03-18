import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'connection_status.dart';

class DeviceStatusWidget extends StatelessWidget {
  const DeviceStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    Color stateColor;
    switch (state.deviceState) {
      case 'ALERT_SENT':
        stateColor = theme.colorScheme.error;
        break;
      case 'FALL_DETECTED':
        stateColor = theme.colorScheme.tertiary;
        break;
      case 'MONITORING':
        stateColor = Colors.teal;
        break;
      default:
        stateColor = Colors.grey;
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Device Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                const ConnectionStatusWidget(),
              ],
            ),

            // Connected device info
            if (state.isBleConnected) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(60),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.developer_board_rounded,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.bleDeviceName ?? 'ESP32 Device',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reconnecting indicator
            if (state.isBleReconnecting) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withAlpha(60)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Auto-reconnecting to device...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statusItem(
                  Icons.sensors_rounded,
                  state.deviceState,
                  stateColor,
                  theme,
                ),
                _statusItem(
                  Icons.bluetooth_rounded,
                  state.isBleConnected ? 'Live' : 'No Device',
                  state.isBleConnected ? Colors.blue : Colors.grey,
                  theme,
                ),
                _statusItem(
                  Icons.wifi_rounded,
                  state.wifiConnected ? 'Connected' : 'Offline',
                  state.wifiConnected ? Colors.teal : Colors.grey,
                  theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(
    IconData icon,
    String label,
    Color color,
    ThemeData theme,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

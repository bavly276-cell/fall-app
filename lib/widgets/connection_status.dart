import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

/// Compact BLE connection status indicator widget.
class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    final bool connected = state.isBleConnected;
    final bool reconnecting = state.isBleReconnecting;

    Color bgColor;
    Color borderColor;
    IconData icon;
    String label;

    if (connected) {
      bgColor = Colors.green.withAlpha(30);
      borderColor = Colors.green;
      icon = Icons.bluetooth_connected;
      label = 'Connected';
    } else if (reconnecting) {
      bgColor = Colors.orange.withAlpha(30);
      borderColor = Colors.orange;
      icon = Icons.bluetooth_searching;
      label = 'Reconnecting...';
    } else {
      bgColor = Colors.grey.withAlpha(30);
      borderColor = Colors.grey;
      icon = Icons.bluetooth_disabled;
      label = 'Disconnected';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reconnecting)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: borderColor,
              ),
            )
          else
            Icon(icon, size: 14, color: borderColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: borderColor,
            ),
          ),
          if (connected && state.bleDeviceName != null) ...[
            const SizedBox(width: 6),
            Container(width: 1, height: 12, color: borderColor.withAlpha(60)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                state.bleDeviceName!,
                style: TextStyle(fontSize: 10, color: borderColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

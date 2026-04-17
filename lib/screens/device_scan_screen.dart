import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../models/ble_device.dart';
import '../services/ble_service.dart';
import '../services/app_state.dart';
import '../widgets/app_bottom_nav.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen>
    with SingleTickerProviderStateMixin {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _connecting = false;
  String? _connectingDeviceId;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });
    _startScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    BleService.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    final hasPerms = await BleService.requestPermissions();
    if (!hasPerms) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final btOn = await BleService.isBluetoothOn();
    if (!btOn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Bluetooth'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _scanResults = []);
    _scanSub?.cancel();
    _scanSub = BleService.scanDevices().listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    });
  }

  Future<void> _connectToDevice(ScanResult result) async {
    setState(() {
      _connecting = true;
      _connectingDeviceId = result.device.remoteId.str;
    });

    await BleService.stopScan();
    final success = await BleService.connectToDevice(result.device);

    if (!mounted) return;

    if (success) {
      final battery = await BleService.readBatteryLevel();
      if (!mounted) return;

      final appState = Provider.of<AppState>(context, listen: false);
      final rawId = result.device.remoteId.str;
      final shortId = rawId.length > 6
          ? rawId.substring(rawId.length - 6)
          : rawId;
      final displayName = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : 'BLE-$shortId';
      appState.setBleDevice(
        name: displayName,
        id: rawId,
        battery: battery >= 0 ? battery.toDouble() : 0,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to $displayName'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection failed. Make sure the device is in range.'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _connecting = false;
        _connectingDeviceId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Devices'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan',
              onPressed: _startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          if (appState.isBleConnected)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth_connected,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appState.bleDeviceName ?? 'ESP32 Device',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          appState.bleDeviceBattery > 0
                              ? 'Battery: ${appState.bleDeviceBattery.toInt()}%'
                              : 'Battery: N/A',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () async {
                      appState.clearBleDevice();
                      try {
                        await BleService.disconnect();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('BLE disconnected'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Disconnect requested. Device will update shortly.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.sync, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Auto-reconnect',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                Switch(
                  value: BleService.autoReconnectEnabled,
                  onChanged: (val) {
                    BleService.setAutoReconnect(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: _isScanning
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FadeTransition(
                                opacity: _pulseController,
                                child: const Icon(
                                  Icons.bluetooth_searching,
                                  size: 64,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text('Scanning for devices...'),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_disabled,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No devices found',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _startScan,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Scan Again'),
                              ),
                            ],
                          ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final device = BleDeviceInfo.fromScanResult(result);
                      final isConnecting =
                          _connecting && _connectingDeviceId == device.id;
                      final isCurrentlyConnected =
                          appState.bleDeviceId == device.id;

                      IconData signalIcon;
                      Color signalColor;
                      switch (device.signalStrength) {
                        case SignalStrength.excellent:
                          signalIcon = Icons.signal_cellular_4_bar;
                          signalColor = Colors.green;
                          break;
                        case SignalStrength.good:
                          signalIcon = Icons.signal_cellular_alt;
                          signalColor = Colors.lightGreen;
                          break;
                        case SignalStrength.fair:
                          signalIcon = Icons.signal_cellular_alt_2_bar;
                          signalColor = Colors.orange;
                          break;
                        case SignalStrength.weak:
                          signalIcon = Icons.signal_cellular_alt_1_bar;
                          signalColor = Colors.red;
                          break;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isCurrentlyConnected
                                ? Colors.green
                                : theme.colorScheme.primaryContainer,
                            child: Icon(
                              isCurrentlyConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth,
                              color: isCurrentlyConnected
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            device.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                device.id,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    signalIcon,
                                    size: 14,
                                    color: signalColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${device.rssi} dBm (${device.signalStrength.label})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: signalColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: isCurrentlyConnected
                              ? Chip(
                                  label: const Text(
                                    'Connected',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: Colors.green,
                                  side: BorderSide.none,
                                )
                              : isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _connecting
                                      ? null
                                      : () => _connectToDevice(result),
                                  child: const Text('Connect'),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../services/app_state.dart';
import '../services/wifi_scan_service.dart';
import '../widgets/app_bottom_nav.dart';

class WifiDeviceScanScreen extends StatefulWidget {
  const WifiDeviceScanScreen({super.key});

  @override
  State<WifiDeviceScanScreen> createState() => _WifiDeviceScanScreenState();
}

class _WifiDeviceScanScreenState extends State<WifiDeviceScanScreen>
    with SingleTickerProviderStateMixin {
  List<WiFiAccessPoint> _results = [];
  bool _scanning = false;
  String? _addingBssid;
  Timer? _autoRefreshTimer;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startAutoScan();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startAutoScan() async {
    await _scanOnce();
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _scanOnce();
    });
  }

  Future<void> _scanOnce() async {
    if (!mounted) return;
    setState(() => _scanning = true);

    final started = await WifiScanService.startScan();
    if (!started) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WiFi scan unavailable. Enable WiFi and Location.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    final results = await WifiScanService.getResults();

    if (!mounted) return;
    setState(() {
      _results = results.where((ap) => ap.ssid.trim().isNotEmpty).toList()
        ..sort((a, b) => b.level.compareTo(a.level));
      _scanning = false;
    });
  }

  Future<void> _addWifiDevice(WiFiAccessPoint ap) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final passController = TextEditingController(
      text: ap.ssid == appState.wifiSsid ? appState.wifiPassword : '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${ap.ssid}'),
        content: TextField(
          controller: passController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'WiFi Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final password = passController.text;
    final secured = _isSecuredNetwork(ap.capabilities);
    if (secured && password.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password required for this secured WiFi network.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final passwordError = _validateWifiPassword(
      capabilities: ap.capabilities,
      password: password,
    );
    if (passwordError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordError), backgroundColor: Colors.orange),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _addingBssid = ap.bssid);

    await appState.saveWifiSettings(
      ssid: ap.ssid,
      password: password,
      serverUrl: appState.wifiServerUrl,
    );

    bool pushed = false;
    if (appState.isBleConnected) {
      pushed = await appState.addWifiDeviceFromSavedSettings(
        verifyConnection: true,
      );
    }

    if (!mounted) return;
    setState(() => _addingBssid = null);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pushed
              ? 'WiFi verified and connected on ESP32'
              : appState.isBleConnected
              ? 'WiFi credentials invalid or network unreachable. Entry was forgotten.'
              : 'WiFi saved. Connect BLE to verify and push to ESP32',
        ),
        backgroundColor: pushed
            ? Colors.green
            : appState.isBleConnected
            ? Colors.red
            : Colors.orange,
      ),
    );
  }

  bool _isSecuredNetwork(String capabilities) {
    final caps = capabilities.toUpperCase();
    return caps.contains('WEP') ||
        caps.contains('WPA') ||
        caps.contains('PSK') ||
        caps.contains('SAE') ||
        caps.contains('EAP');
  }

  String? _validateWifiPassword({
    required String capabilities,
    required String password,
  }) {
    final caps = capabilities.toUpperCase();
    final trimmed = password.trim();

    if (!_isSecuredNetwork(capabilities)) return null;

    if (caps.contains('WPA') || caps.contains('PSK') || caps.contains('SAE')) {
      if (trimmed.length < 8 || trimmed.length > 63) {
        return 'Password looks invalid. WPA/WPA2 passwords must be 8-63 characters.';
      }
      return null;
    }

    if (caps.contains('WEP')) {
      const validLengths = <int>{5, 10, 13, 26, 16, 32};
      if (!validLengths.contains(trimmed.length)) {
        return 'Password looks invalid for WEP network.';
      }
      return null;
    }

    if (trimmed.isEmpty) {
      return 'Password is required for this secured WiFi network.';
    }

    return null;
  }

  Future<void> _forgetAddedWifi() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.wifiSsid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget WiFi'),
        content: Text('Forget ${appState.wifiSsid}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await appState.forgetWifiSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('WiFi network forgotten'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Devices'),
        actions: [
          if (_scanning)
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
              tooltip: 'Rescan',
              onPressed: _scanOnce,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  appState.wifiConnected ? Icons.wifi : Icons.wifi_off,
                  color: appState.wifiConnected ? Colors.teal : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appState.wifiSsid.isNotEmpty
                        ? 'Current: ${appState.wifiSsid}'
                        : 'No WiFi device added yet',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(appState.wifiConnected ? 'Connected' : 'Offline'),
                  backgroundColor: appState.wifiConnected
                      ? Colors.teal.withAlpha(30)
                      : Colors.grey.withAlpha(30),
                ),
                if (appState.wifiSsid.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Forget WiFi',
                    onPressed: _forgetAddedWifi,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: _scanning
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FadeTransition(
                                opacity: _pulseController,
                                child: const Icon(
                                  Icons.wifi_find,
                                  size: 64,
                                  color: Colors.teal,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text('Scanning WiFi devices...'),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No WiFi networks found',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _scanOnce,
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
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final ap = _results[index];
                      final isCurrent = appState.wifiSsid == ap.ssid;
                      final isAdding = _addingBssid == ap.bssid;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isCurrent
                                ? Colors.teal
                                : theme.colorScheme.primaryContainer,
                            child: Icon(
                              isCurrent ? Icons.wifi : Icons.wifi_rounded,
                              color: isCurrent
                                  ? Colors.white
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            ap.ssid,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${ap.level} dBm  •  ${ap.capabilities}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: isCurrent
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: const Text(
                                        'Added',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                      backgroundColor: Colors.teal,
                                      side: BorderSide.none,
                                    ),
                                    IconButton(
                                      tooltip: 'Forget WiFi',
                                      onPressed: _forgetAddedWifi,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                )
                              : isAdding
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: () => _addWifiDevice(ap),
                                  child: const Text('Add'),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/ble_service.dart';
import '../services/permission_manager.dart';
import '../services/background_service.dart';
import '../services/firestore_service.dart';
import '../widgets/app_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _autoReconnect = BleService.autoReconnectEnabled;
  bool _backgroundRunning = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkBackgroundService();
  }

  Future<void> _checkBackgroundService() async {
    final running = await BackgroundMonitorService.isRunning();
    if (mounted) setState(() => _backgroundRunning = running);
  }

  Future<void> _changePatientPhoto(AppState state) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final base64 = base64Encode(bytes);
    await state.setPatientPhotoBase64(base64);
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar
          Center(
            child: GestureDetector(
              onTap: () => _changePatientPhoto(state),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF1565C0),
                    backgroundImage: state.patientPhotoBase64 != null
                        ? MemoryImage(base64Decode(state.patientPhotoBase64!))
                        : null,
                    child: state.patientPhotoBase64 == null
                        ? const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.edit,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Patient Info
          _infoCard('Patient Information', [
            _editableRow(
              context,
              Icons.person,
              'Name',
              state.patientName,
              (val) => state.patientName = val,
            ),
            _editableRow(
              context,
              Icons.email,
              'Email',
              state.patientEmail.isNotEmpty ? state.patientEmail : 'Not set',
              (val) => state.patientEmail = val,
            ),
            _editableRow(
              context,
              Icons.phone_android,
              'Phone',
              state.patientPhone.isNotEmpty ? state.patientPhone : 'Not set',
              (val) => state.patientPhone = val,
            ),
          ]),
          const SizedBox(height: 12),

          // Caregiver Info
          _infoCard('Caregiver Information', [
            _editableRow(
              context,
              Icons.local_hospital,
              'Name',
              state.caregiverName,
              (val) => state.caregiverName = val,
            ),
            _editableRow(
              context,
              Icons.phone,
              'Phone',
              state.caregiverPhone,
              (val) => state.caregiverPhone = val,
            ),
            _editableRow(
              context,
              Icons.email,
              'Email',
              state.caregiverEmail.isNotEmpty
                  ? state.caregiverEmail
                  : 'Not set',
              (val) => state.caregiverEmail = val,
            ),
          ]),
          const SizedBox(height: 12),

          // Cloud Sync
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Cloud Sync',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        state.firebaseReady
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        color: state.firebaseReady ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.firebaseReady ? 'Connected' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: state.firebaseReady
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text(
                    'Fall events and profile are synced to Firebase Firestore in real-time.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: state.firebaseReady
                          ? () async {
                              await FirestoreService.saveProfile(
                                patientName: state.patientName,
                                caregiverName: state.caregiverName,
                                caregiverPhone: state.caregiverPhone,
                                smsAlertEnabled: state.smsAlertEnabled,
                                autoSmsOnConfirm: state.autoSmsOnConfirm,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile synced to cloud'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          : null,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Sync Profile Now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SMS Alert Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SMS Alert Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.sms),
                    title: const Text('SMS Alerts'),
                    subtitle: const Text(
                      'Send SMS with GPS to caregiver on fall',
                    ),
                    value: state.smsAlertEnabled,
                    onChanged: (_) => state.toggleSmsAlert(),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.send),
                    title: const Text('Auto-Send on Confirm'),
                    subtitle: const Text(
                      'Automatically send SMS when fall is confirmed',
                    ),
                    value: state.autoSmsOnConfirm,
                    onChanged: state.smsAlertEnabled
                        ? (_) => state.toggleAutoSms()
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
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
                          icon: const Icon(Icons.sms),
                          label: const Text('Test SMS'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => state.callCaregiver(),
                          icon: const Icon(Icons.phone),
                          label: const Text('Test Call'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bluetooth Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bluetooth Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.sync),
                    title: const Text('Auto-Reconnect'),
                    subtitle: const Text(
                      'Automatically reconnect when device disconnects',
                    ),
                    value: _autoReconnect,
                    onChanged: (val) {
                      BleService.setAutoReconnect(val);
                      setState(() => _autoReconnect = val);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.nights_stay),
                    title: const Text('Background Monitoring'),
                    subtitle: const Text(
                      'Keep monitoring active when app is minimized',
                    ),
                    value: _backgroundRunning,
                    onChanged: (val) async {
                      if (val) {
                        await BackgroundMonitorService.start();
                      } else {
                        await BackgroundMonitorService.stop();
                      }
                      setState(() => _backgroundRunning = val);
                    },
                  ),
                  _infoRow(
                    Icons.bluetooth,
                    'Connected',
                    state.isBleConnected
                        ? (state.bleDeviceName ?? 'Unknown')
                        : 'None',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // WiFi Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WiFi Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.wifi),
                    title: const Text('WiFi Fallback Alerts'),
                    subtitle: const Text(
                      'Use cloud/WiFi path when BLE is out of range',
                    ),
                    value: state.wifiFallbackEnabled,
                    onChanged: (_) => state.toggleWifiFallback(),
                  ),
                  _infoRow(
                    Icons.wifi_tethering,
                    'Status',
                    state.wifiConnected ? 'Connected' : 'Not Connected',
                  ),
                  _infoRow(
                    Icons.router,
                    'SSID',
                    state.wifiSsid.isNotEmpty ? state.wifiSsid : 'Not set',
                  ),
                  _infoRow(
                    Icons.link,
                    'Server',
                    state.wifiServerUrl.isNotEmpty
                        ? state.wifiServerUrl
                        : 'Not set',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showWifiDialog(context, state),
                          icon: const Icon(Icons.settings_input_antenna),
                          label: const Text('Configure'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: state.isBleConnected
                              ? () async {
                                  final ok = await state
                                      .addWifiDeviceFromSavedSettings(
                                        verifyConnection: true,
                                      );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'WiFi verified and connected on ESP32'
                                            : 'Invalid WiFi credentials or network unreachable. Entry was forgotten.',
                                      ),
                                      backgroundColor: ok
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.add_link),
                          label: const Text('Add Device'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: state.wifiConnected
                          ? () {
                              state.disconnectWifiDevice();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('WiFi device disconnected'),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.wifi_off),
                      label: const Text('Disconnect WiFi Device'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: state.wifiSsid.isNotEmpty
                          ? () async {
                              await state.forgetWifiSettings();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved WiFi forgotten'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Forget Saved WiFi'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Permissions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Permissions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final results =
                            await PermissionManager.requestAllPermissions();
                        if (context.mounted) {
                          final granted = results.values.where((v) => v).length;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$granted/${results.length} permissions granted',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.security),
                      label: const Text('Request All Permissions'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => PermissionManager.openSettings(),
                      icon: const Icon(Icons.settings),
                      label: const Text('Open App Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Detection Settings
          _infoCard('Detection Settings (3-Stage Algorithm)', [
            _infoRow(Icons.speed, 'Impact Threshold', '3.0g'),
            _infoRow(Icons.arrow_downward, 'Freefall Threshold', '<0.4g'),
            _infoRow(Icons.rotate_right, 'Angle Threshold', '60°'),
            _infoRow(Icons.favorite, 'HR Stress', '>100 BPM'),
            _infoRow(Icons.timer, 'Alert Latency', '<500ms'),
            _infoRow(Icons.check_circle, 'Target Accuracy', '>90%'),
            _infoRow(Icons.warning_amber, 'False Alarm Rate', '<5%'),
            _infoRow(Icons.security, 'Redundancy', 'Arduino + Phone'),
          ]),
          const SizedBox(height: 12),

          // Hardware Info
          _infoCard('Hardware Components', [
            _infoRow(Icons.memory, 'MCU', 'ESP32-C3 Super Mini'),
            _infoRow(Icons.favorite, 'HR Sensor', 'MAX30102'),
            _infoRow(Icons.sensors, 'IMU', 'MPU6050'),
            _infoRow(Icons.bluetooth, 'BLE', 'ESP32-C3 (built-in)'),
            _infoRow(Icons.wifi, 'WiFi', 'ESP32-C3 (built-in)'),
          ]),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 5),
    );
  }

  Widget _infoCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _editableRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showEditDialog(context, label, value, onChanged),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String label,
    String currentValue,
    ValueChanged<String> onChanged,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Enter $label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) {
                onChanged(trimmed);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showWifiDialog(BuildContext context, AppState state) {
    final ssidController = TextEditingController(text: state.wifiSsid);
    final passwordController = TextEditingController(text: state.wifiPassword);
    final serverController = TextEditingController(text: state.wifiServerUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WiFi Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ssidController,
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID',
                  hintText: 'Home_WiFi',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'WiFi Password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: serverController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://example.com/fall-events',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await state.saveWifiSettings(
                ssid: ssidController.text.trim(),
                password: passwordController.text,
                serverUrl: serverController.text.trim(),
              );

              var pushedToDevice = false;
              if (state.isBleConnected && state.wifiSsid.isNotEmpty) {
                pushedToDevice = await state.addWifiDeviceFromSavedSettings(
                  verifyConnection: true,
                );
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      pushedToDevice
                          ? 'WiFi settings saved, verified, and sent to device'
                          : state.isBleConnected
                          ? 'WiFi settings were invalid for ESP32 and were forgotten'
                          : 'WiFi settings saved',
                    ),
                    backgroundColor: pushedToDevice
                        ? Colors.green
                        : state.isBleConnected
                        ? Colors.red
                        : Colors.green,
                  ),
                );
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

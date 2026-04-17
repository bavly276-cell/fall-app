import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/ble_service.dart';
import '../services/permission_manager.dart';
import '../services/background_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
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

          // Kids Safety Monitoring Role + Pairing
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kids Safety Monitoring',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _infoRow(Icons.badge, 'This Device ID', state.deviceId),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: state.deviceId),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device ID copied')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy Device ID'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<MonitoringRole>(
                    value: state.monitoringRole,
                    items: const [
                      DropdownMenuItem(
                        value: MonitoringRole.child,
                        child: Text('Child Device (send updates)'),
                      ),
                      DropdownMenuItem(
                        value: MonitoringRole.parent,
                        child: Text('Parent Device (monitor child)'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.swap_horiz_rounded),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        state.setMonitoringRole(value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  if (state.monitoringRole == MonitoringRole.child)
                    _editableRow(
                      context,
                      Icons.phone_iphone_rounded,
                      'Linked Parent Device ID',
                      state.linkedParentDeviceId,
                      (val) => state.setLinkedParentDeviceId(val),
                    ),
                  if (state.monitoringRole == MonitoringRole.parent)
                    _editableRow(
                      context,
                      Icons.child_care_rounded,
                      'Linked Child Device ID',
                      state.linkedChildDeviceId,
                      (val) => state.setLinkedChildDeviceId(val),
                    ),
                  if (state.monitoringRole == MonitoringRole.child)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _infoRow(
                          Icons.gps_fixed,
                          'Safe Zone',
                          (state.safeZoneLat != null &&
                                  state.safeZoneLon != null)
                              ? '${state.safeZoneLat!.toStringAsFixed(5)}, ${state.safeZoneLon!.toStringAsFixed(5)}'
                              : 'Not set',
                        ),
                        _infoRow(
                          Icons.radio_button_checked,
                          'Safe Radius',
                          '${state.safeZoneRadiusMeters.toStringAsFixed(0)} m',
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final pos =
                                      await LocationService.getCurrentPosition();
                                  if (pos == null) return;
                                  await state.setSafeZone(
                                    latitude: pos.latitude,
                                    longitude: pos.longitude,
                                    radiusMeters: state.safeZoneRadiusMeters,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Safe zone saved'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.my_location_rounded),
                                label: const Text('Set Current as Safe Zone'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: state.safeZoneRadiusMeters.clamp(
                            100.0,
                            2000.0,
                          ),
                          min: 100,
                          max: 2000,
                          divisions: 19,
                          label:
                              '${state.safeZoneRadiusMeters.toStringAsFixed(0)} m',
                          onChanged: (value) {
                            final lat = state.safeZoneLat;
                            final lon = state.safeZoneLon;
                            if (lat == null || lon == null) return;
                            state.setSafeZone(
                              latitude: lat,
                              longitude: lon,
                              radiusMeters: value,
                            );
                          },
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => state.clearSafeZone(),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Clear Safe Zone'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
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
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
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
}

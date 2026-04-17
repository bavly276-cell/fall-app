import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/safety_update.dart';
import '../services/app_state.dart';
import '../services/firestore_service.dart';

class ParentMonitoringScreen extends StatelessWidget {
  const ParentMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final childId = appState.linkedChildDeviceId.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Parent Monitor')),
      body: childId.isEmpty
          ? _buildMissingChildMessage(context)
          : StreamBuilder<SafetyUpdate?>(
              stream: FirestoreService.streamLatestSafetySnapshot(childId),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: Text('No child updates yet.'));
                }
                return _buildContent(context, data);
              },
            ),
    );
  }

  Widget _buildMissingChildMessage(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No child device linked yet.\nOpen Profile and set Linked Child Device ID.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SafetyUpdate update) {
    final lat = update.latitude;
    final lon = update.longitude;
    final hasLocation = lat != null && lon != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: update.isDanger
                ? Colors.red.withAlpha(24)
                : Colors.green.withAlpha(24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: update.isDanger ? Colors.red : Colors.green,
            ),
          ),
          child: Row(
            children: [
              Icon(
                update.isDanger ? Icons.warning_rounded : Icons.check_circle,
                color: update.isDanger ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  update.isDanger
                      ? 'DANGER: ${update.alertReason}'
                      : 'NORMAL: ${update.alertReason}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest Health Data',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _row(
                  'Heart Rate',
                  '${update.heartRate.toStringAsFixed(0)} bpm',
                ),
                _row('SpO2', '${update.spo2.toStringAsFixed(1)} %'),
                _row('Activity', update.activity),
                _row('Fall', update.fallDetected ? 'Detected' : 'No'),
                _row('Trigger', update.triggerType),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (hasLocation)
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(lat, lon),
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('child_location'),
                    position: LatLng(lat, lon),
                    infoWindow: const InfoWindow(title: 'Child location'),
                  ),
                },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Location unavailable in latest update.'),
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: update.mapsUrl.isEmpty
              ? null
              : () async {
                  final uri = Uri.parse(update.mapsUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
          icon: const Icon(Icons.map_rounded),
          label: const Text('Open in Google Maps'),
        ),
      ],
    );
  }

  Widget _row(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

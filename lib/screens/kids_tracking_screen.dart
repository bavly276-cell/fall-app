import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../services/ble_service.dart';

/// Kids Mode Live GPS Tracking Screen
/// Displays real-time location of the bracelet wearer on a map
/// and shows location history with timestamps
class KidsTrackingScreen extends StatefulWidget {
  const KidsTrackingScreen({super.key});

  @override
  State<KidsTrackingScreen> createState() => _KidsTrackingScreenState();
}

class _KidsTrackingScreenState extends State<KidsTrackingScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  ({double lat, double lon})? _resolveCoordinates(AppState appState) {
    if (appState.lastKidsLat != null && appState.lastKidsLon != null) {
      return (lat: appState.lastKidsLat!, lon: appState.lastKidsLon!);
    }
    if (appState.kidsLocationHistory.isNotEmpty) {
      final latest = appState.kidsLocationHistory.last;
      return (lat: latest.lat, lon: latest.lon);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _ensureGpsFeed();
    _updateMapMarkers();
  }

  void _ensureGpsFeed() {
    final appState = context.read<AppState>();
    if (!appState.kidsModeEnabled) return;

    if (BleService.isConnected) {
      BleService.subscribeGpsData(
        onGpsData: (lat, lon, valid) {
          if (!mounted) return;
          appState.updateKidsGpsLocation(lat, lon, valid);
          _updateMapMarkers();
        },
      );
    }
  }

  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    final appState = context.read<AppState>();
    final coords = _resolveCoordinates(appState);

    // Add current location marker
    if (coords != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(coords.lat, coords.lon),
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Add location history polyline
    if (appState.kidsLocationHistory.isNotEmpty) {
      final points = appState.kidsLocationHistory
          .map((loc) => LatLng(loc.lat, loc.lon))
          .toList();

      _polylines.add(
        Polyline(
          polylineId: const PolylineId('location_history'),
          color: Colors.blue.withAlpha(128),
          points: points,
          width: 3,
        ),
      );

      // Only the current location marker is needed as per user preference.
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;

    final appState = context.read<AppState>();
    final coords = _resolveCoordinates(appState);

    if (coords != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(coords.lat, coords.lon), zoom: 16),
        ),
      );
    }
  }

  Widget _buildWaitingGpsState(AppState appState) {
    final isBle = BleService.isConnected;
    final firmwareMissingGps =
        isBle &&
        appState.smartwatchCapabilityReport != null &&
        !appState.smartwatchCapabilityReport!.hasGps;

    String message;
    if (firmwareMissingGps) {
      message =
          'Connected device firmware does not expose GPS over BLE.\n'
          'Flash a GPS-enabled firmware build and reconnect.';
    } else if (isBle) {
      message = 'Waiting for ESP GPS signal...';
    } else if (appState.firebaseReady) {
      message =
          'No ESP GPS points synced yet. Reconnect bracelet and try again.';
    } else {
      message = 'Connecting ESP GPS sync...';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gps_not_fixed, size: 64, color: Colors.grey[500]),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                _ensureGpsFeed();
                _updateMapMarkers();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry GPS'),
            ),
          ],
        ),
      ),
    );
  }

  String _getGpsStatusText(AppState appState, bool isBle) {
    if (!appState.kidsModeGpsValid) {
      return isBle
          ? 'ESP BLE: Waiting for signal...'
          : 'ESP Sync: No data found';
    }

    if (appState.lastKidsGpsUpdate == null) {
      return 'No data available';
    }

    final now = DateTime.now();
    final diff = now.difference(appState.lastKidsGpsUpdate!);

    String timeAgo;
    if (diff.inSeconds < 60) {
      timeAgo = '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else {
      timeAgo = DateFormat('MMM d').format(appState.lastKidsGpsUpdate!);
    }

    return '${isBle ? 'ESP BLE' : 'ESP Sync'}: ${diff.inSeconds < 10 ? 'Live' : 'Last updated $timeAgo'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kids Tracking'), elevation: 0),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          if (!appState.kidsModeEnabled) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'Kids Mode is not enabled',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      appState.enableKidsMode();
                    },
                    child: const Text('Enable Kids Mode'),
                  ),
                ],
              ),
            );
          }

          final coords = _resolveCoordinates(appState);

          if (coords == null) {
            return _buildWaitingGpsState(appState);
          }

          final isBle = BleService.isConnected;
          final statusText = _getGpsStatusText(appState, isBle);

          return Column(
            children: [
              // GPS Status and coordinates
              Container(
                decoration: BoxDecoration(
                  color: appState.kidsModeGpsValid
                      ? Colors.green.withAlpha(20)
                      : Colors.orange.withAlpha(20),
                  border: Border(
                    bottom: BorderSide(
                      color:
                          (appState.kidsModeGpsValid
                                  ? Colors.green
                                  : Colors.orange)
                              .withAlpha(40),
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBle ? Icons.bluetooth : Icons.cloud_done_rounded,
                          color: appState.kidsModeGpsValid
                              ? Colors.green
                              : Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: appState.kidsModeGpsValid
                                  ? Colors.green[800]
                                  : Colors.orange[800],
                            ),
                          ),
                        ),
                        if (!isBle)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ESP SYNC',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lat: ${coords.lat.toStringAsFixed(6)}\n'
                      'Lon: ${coords.lon.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (appState.kidsLocationHistory.isNotEmpty)
                      Text(
                        'Location history: ${appState.kidsLocationHistory.length} points',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              // Google Map
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: _onMapCreated,
                      initialCameraPosition: CameraPosition(
                        target: LatLng(coords.lat, coords.lon),
                        zoom: 16,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      // ESP-only mode: don't show phone GPS location on map.
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                    ),
                    // Refresh button
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton(
                        mini: true,
                        onPressed: () {
                          _ensureGpsFeed();
                          _updateMapMarkers();
                        },
                        child: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
              ),
              // Location History ListView
              if (appState.kidsLocationHistory.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Location History',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: appState.kidsLocationHistory.length,
                          itemBuilder: (context, index) {
                            final location =
                                appState.kidsLocationHistory[index];
                            final timeStr = DateFormat(
                              'HH:mm:ss',
                            ).format(location.timestamp);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${location.lat.toStringAsFixed(4)}\n'
                                        '${location.lon.toStringAsFixed(4)}',
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

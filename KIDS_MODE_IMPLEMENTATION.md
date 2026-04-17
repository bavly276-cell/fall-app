# Kids Mode Implementation with Live GPS Tracking

## Overview
This document describes the comprehensive implementation of **Kids Mode** with live GPS tracking to the SafeBrace fall detection system. The feature enables real-time location monitoring of bracelet wearers through:
- ESP32 firmware GPS support
- Bluetooth Low Energy (BLE) GPS data transmission
- Flutter app with live map visualization
- Firebase Firestore location history storage

---

## Architecture

### Three Main Components:

#### 1. **ESP32 Firmware** (`fall_detection_corrected.ino`)
- **GPS Module Integration**: Added TinyGPS++ library for UART serial GPS communication
- **New BLE Characteristic**: `GPS_CHAR_UUID` broadcasts live location data
- **Continuous GPS Reading**: Updates location every 5 seconds
- **Display Indicator**: Shows GPS signal status ("GPS" or "---") on OLED

#### 2. **Flutter BLE Service** (`ble_service.dart`)
- **New GPS Callback**: `BleGpsDataCallback` receives real-time coordinates
- **GPS Parser**: Extracts latitude/longitude from BLE payload
- **Auto-subscription**: Automatically subscribes to GPS data when connected

#### 3. **Flutter UI & State** (Multiple files)
- **Kids Mode Toggle**: Switch on home screen to enable/disable tracking
- **Live Map Screen**: Google Maps integration showing current location + history
- **Firebase Storage**: Automatic location persistence to Firestore
- **Location History**: Maintains up to 100 recent location points

---

## Detailed Implementation

### A. ESP32 Firmware Changes

#### Added Libraries & Pins:
```cpp
#include <TinyGPS++.h>

#define GPS_RX_PIN 20
#define GPS_TX_PIN 21
#define GPS_BAUD_RATE 9600
#define GPS_UPDATE_INTERVAL_MS 5000

HardwareSerial gpsSerial(1);
TinyGPS++ gps;
double lastLat = 0.0, lastLon = 0.0;
bool gpsValid = false;
```

#### New BLE Characteristic:
```cpp
#define GPS_CHAR_UUID "12345678-1234-1234-1234-123456789af0"

// Created in setup():
pGpsChar = pService->createCharacteristic(GPS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
```

#### GPS Functions:
- **`updateGpsData()`**: Reads UART serial data from GPS module
- **`sendGpsDataViaBLE()`**: Broadcasts coordinates via BLE every 10 seconds
- **`setupGPS()`**: Initializes UART1 at 9600 baud

#### BLE Payload Format:
```
"LAT:XXXXX.XXXXX,LON:XXXXX.XXXXX,VALID:1"
```

#### OLED Display Enhancement:
GPS status indicator shows in top-right corner:
- "GPS" - Signal acquired
- "---" - Searching for signal

---

### B. Flutter BLE Service Updates

#### New Callback Type:
```dart
typedef BleGpsDataCallback = void Function(double? lat, double? lon, bool valid);
```

#### New Static Variables:
```dart
static StreamSubscription<List<int>>? _gpsNotifySub;
static BleGpsDataCallback? _onGpsData;
static const String gpsCharUuid = '12345678-1234-1234-1234-123456789af0';
```

#### GPS Subscription Function:
```dart
static Future<void> subscribeGpsData({
    required void Function(double? lat, double? lon, bool valid) onGpsData,
}) async {
    // Discovers GPS characteristic
    // Parses BLE payload using regex
    // Triggers callback with coordinates
}
```

#### Cleanup on Disconnect:
```dart
_gpsNotifySub?.cancel();  // Added to _handleDisconnect()
```

---

### C. AppState GPS Tracking (Kids Mode State)

#### New Properties:
```dart
bool _kidsModeEnabled = false;
double? _lastKidsLat;
double? _lastKidsLon;
bool _kidsModeGpsValid = false;
DateTime? _lastKidsGpsUpdate;
List<({double lat, double lon, DateTime timestamp})> _kidsLocationHistory = [];
```

#### New Methods:
```dart
void enableKidsMode()
void disableKidsMode()
void updateKidsGpsLocation(double? lat, double? lon, bool valid)
```

#### Location History:
- Maintains up to 100 recent location points
- Each point includes timestamp
- Used for drawing polyline trails on map

---

### D. Kids Tracking Screen (`kids_tracking_screen.dart`)

#### Features:
1. **Google Maps Display**
   - Current location marker (blue)
   - History start marker (green)
   - Polyline trail showing movement history

2. **GPS Status Panel**
   - Shows signal validity
   - Displays last update time (relative: "5s ago")
   - Current latitude/longitude

3. **Location History Carousel**
   - Horizontal scrolling list of recent locations
   - Time and coordinates for each point
   - Latest 100 points displayed

4. **User Actions**
   - Refresh button to update map markers
   - Tap to enable kids mode if disabled
   - Navigate to tracking screen when enabled

#### Key Widgets:
- `GoogleMapController` for map management
- `Set<Marker>` for location points
- `Set<Polyline>` for movement trail
- `ListView.builder` for history carousel

---

### E. Home Screen Integration

#### Added Imports:
```dart
import '../screens/kids_tracking_screen.dart';
import '../services/firestore_service.dart';
```

#### GPS Callback Setup (in initState):
```dart
BleService.setGpsDataCallback((lat, lon, valid) {
    appState.updateKidsGpsLocation(lat, lon, valid);
    
    // Auto-save to Firebase
    if (valid && lat != null && lon != null && appState.kidsModeEnabled) {
        FirestoreService.saveKidsLocation(latitude: lat, longitude: lon);
    }
});
```

#### New Kids Mode Card:
- Purple gradient styling
- Toggle switch to enable/disable
- Shows "Live GPS tracking enabled" when active
- Tap to open tracking screen
- Automatically subscribes to GPS when enabled

---

### F. Firebase Integration

#### New Firestore Collections:
```
users/{deviceId}/kids_locations/{locationId}
```

#### New Methods:
```dart
Future<void> saveKidsLocation({
    required double latitude,
    required double longitude,
})

Future<List<Map<String, dynamic>>> loadKidsLocationHistory()

Stream<List<Map<String, dynamic>>> kidsLocationStream()

Future<void> clearKidsLocationHistory()
```

#### Document Structure:
```json
{
  "latitude": 37.7749,
  "longitude": -122.4194,
  "timestamp": Timestamp
}
```

---

## Hardware Requirements

### GPS Module Setup:
1. **Module Type**: Any GPS module with UART output (Neo-6M, Neo-7M, etc.)
2. **Connection**:
   - GPS TX → ESP32-C3 GPIO 20 (RX)
   - GPS RX → Not used (RX-only mode)
   - GND → GND
   - VCC → 5V or 3.3V (check module specs)

3. **Baud Rate**: 9600 bps (standard)
4. **Warm-up Time**: ~30-60 seconds for first fix
5. **Signal Requirements**: Open sky recommended for best accuracy

---

## Usage Flow

### Enabling Kids Mode:
1. Open app and connect ESP32-C3 bracelet via BLE
2. Go to Home Screen
3. Toggle "Kids Mode" switch ON
4. GPS subscription starts automatically
5. Real-time location displayed on map

### Viewing Location:
1. Tap the Kids Mode card to open tracking screen
2. Map shows current location (blue marker)
3. Movement history displayed as polyline trail
4. Scroll location carousel for recent points
5. Tap refresh button to update

### Data Storage:
- All location points auto-saved to Firebase
- Accessible from any authenticated device
- Historical data persists indefinitely
- Can be queried/analyzed later

---

## Configuration & Customization

### Adjust GPS Update Interval (Firmware):
```cpp
#define GPS_UPDATE_INTERVAL_MS 5000  // Change to desired milliseconds
```

### Adjust BLE Broadcast Interval (Firmware):
```cpp
#define GPS_UPDATE_INTERVAL_MS 10000  // Change to desired milliseconds
```

### Adjust Location History Size (AppState):
```dart
if (_kidsLocationHistory.length > 100) {  // Change 100 to desired limit
    _kidsLocationHistory.removeAt(0);
}
```

### Adjust Map Zoom Level (KidsTrackingScreen):
```dart
zoom: 16,  // Change zoom level (0-21, higher = more zoom)
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| GPS not acquiring signal | Ensure GPS module has clear sky view; wait 1-2 minutes |
| "GPS: Waiting for signal..." stays on | Check GPS module connection; verify UART pins |
| No data in Firebase | Ensure authenticated; check Firestore rules allow write |
| Map not loading | Install google_maps_flutter; add API keys |
| Kids Mode toggle not working | Ensure BLE is connected to bracelet first |
| Location history empty | Wait for several GPS updates; check interval |

---

## Firebase Firestore Rules

Add to Security Rules to allow Kids Mode logging:
```javascript
match /users/{userId}/kids_locations/{document=**} {
    allow read, write: if request.auth.uid == userId;
}
```

---

## Dependencies Required

### Flutter Packages (add to pubspec.yaml):
```yaml
google_maps_flutter: ^2.5.0
intl: ^0.19.0
```

### Arduino Libraries (add in firmware):
```cpp
#include <TinyGPS++.h>
```

---

## Testing Checklist

- [ ] GPS module powers on and acquires signal
- [ ] OLED shows GPS status indicator
- [ ] BLE transmits GPS coordinates
- [ ] Flutter app receives GPS data
- [ ] Kids Mode toggle appears on home screen
- [ ] Map displays current location correctly
- [ ] Location history trail shows movement
- [ ] Firebase stores location points
- [ ] Historical data persists after app restart
- [ ] GPS accuracy is within 5-10 meters
- [ ] Battery consumption acceptable

---

## Future Enhancements

1. **Geofencing**: Alert when leaving designated areas
2. **Speed Tracking**: Monitor movement speed
3. **Route Recording**: Save complete route as GPX file
4. **SOS Integration**: GPS included in emergency alerts
5. **Multi-device Tracking**: Monitor multiple bracelet wearers
6. **Heatmap Visualization**: Show frequent locations
7. **Real-time Streaming**: WebSocket instead of polling
8. **Offline Caching**: Store locations locally if offline

---

## Files Modified/Created

### Modified Files:
1. `arduino/fall_detection_corrected/fall_detection_corrected.ino` - GPS firmware
2. `lib/services/ble_service.dart` - GPS BLE subscription
3. `lib/services/app_state.dart` - Kids mode state management
4. `lib/services/firestore_service.dart` - GPS storage
5. `lib/screens/home_screen.dart` - Kids mode UI toggle

### New Files:
1. `lib/screens/kids_tracking_screen.dart` - GPS tracking UI

---

## Support & Documentation

For issues or questions:
1. Check troubleshooting section above
2. Verify hardware connections
3. Review Firebase rules
4. Check app logs for errors
5. Ensure BLE connection is stable

---

**Implementation Date**: April 2026  
**Status**: Complete and Ready for Testing

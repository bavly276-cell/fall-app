# Kids Safety Monitoring System Setup

This project now supports:
- Child phone GPS tracking (internal phone GPS, not external GPS hardware)
- BLE health fusion (HR, SpO2, accel/fall)
- Periodic safety updates every 5 minutes
- Immediate danger alerts (fall, abnormal health, geofence breach)
- Parent push notifications via Firebase Cloud Messaging (FCM)
- Parent monitoring map screen
- Local TensorFlow Lite (TFLite) fall detection model

## 1) Flutter Packages

Already added in `pubspec.yaml`:
- `geolocator`
- `firebase_messaging`
- `flutter_background_service`
- `google_maps_flutter`
- `tflite_flutter`
- `uuid`

Run:

```bash
flutter pub get
```

## 2) Firebase Mobile Setup

1. Create a Firebase project.
2. Add Android app package (current package is `com.bavly`).
3. Download `google-services.json` to:
   - `android/app/google-services.json`
4. In Firebase Console, enable:
   - Cloud Firestore
   - Cloud Messaging
5. Confirm `lib/firebase_options.dart` matches your Firebase app.

## 3) Firestore Data Model

The app writes to:

- `users/{deviceId}`
  - profile + role fields
  - `fcmToken`
  - `lastSafetySnapshot`
  - `alertStatus`
- `users/{deviceId}/safety_updates/{id}`
- `users/{deviceId}/safety_alerts/{id}`
- `users/{deviceId}/kids_locations/{id}`

## 4) Parent Push Notifications (FCM)

Child devices do not send push directly to FCM. Instead:
1. Child writes urgent docs to `safety_alerts`.
2. Cloud Function sends FCM to linked parent token.

### Deploy Cloud Function

Files:
- `cloud_functions/package.json`
- `cloud_functions/index.js`

Commands:

```bash
cd cloud_functions
npm install
firebase login
firebase use <your-project-id>
firebase deploy --only functions
```

## 5) App Pairing Flow

Open Profile screen on each phone:

- Child phone:
  - Set role = `Child Device`
  - Paste `Linked Parent Device ID`
  - Enable `Kids Mode`
- Parent phone:
  - Set role = `Parent Device`
  - Paste `Linked Child Device ID`

Use `Copy Device ID` from Profile to pair devices.

## 6) Background Reliability

Background service is configured with:
- Foreground service mode
- Auto-start + auto-start on boot
- Location + data sync service types

For best reliability on Android:
1. Disable battery optimization for this app.
2. Allow background location permission.
3. Allow notification permission.

## 7) Local AI Model (TFLite)

### Train and export fall model

Dataset must contain 6-axis time series:
- `acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z, label`
- See format: `ml/FALL_DATASET_FORMAT.md`
- Starter template: `ml/data/fall_timeseries.template.csv`

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r ml/requirements.txt
python ml/train_fall_model.py
```

Output:
- `assets/models/fall_detector.tflite`
- `assets/models/fall_detector_meta.json`

Optional activity model:

```bash
python ml/train_activity_model.py
```

Output:
- `assets/models/activity_classifier.tflite`

## 8) Notification Payload

Immediate danger push includes:
- Google Maps URL (`mapsUrl`)
- Latitude/longitude
- HR
- SpO2
- Fall status
- Alert reason

Notification tap opens Google Maps using the transmitted `mapsUrl`.

## 9) Build and run

```bash
flutter clean
flutter pub get
flutter run --dart-define-from-file=dart_define.local.json
```

## 10) Quick Verification Checklist

1. Child app receives BLE HR/SpO2/accel stream.
2. Child app gets phone GPS fix.
3. Every 5 minutes: child writes `safety_updates` and updates `lastSafetySnapshot`.
4. On fall/abnormal values: child writes `safety_alerts`.
5. Cloud Function sends FCM to parent token.
6. Parent app receives push and opens Google Maps on tap.
7. Parent monitoring screen shows child location and latest health state.

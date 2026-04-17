# SafeWatch Fall Detection App

Flutter caregiver app + ESP32-C3 wearable firmware for fall detection and emergency alerts.

## Kids Safety Monitoring System

This codebase now includes a full kids safety workflow:

- Child phone internal GPS tracking (foreground + background)
- BLE wearable health fusion (HR, SpO2, accel/fall)
- 5-minute periodic parent updates + immediate danger alerts
- FCM notification pipeline (via Firebase Cloud Function)
- Parent live monitoring map screen
- Local on-device TFLite fall inference

Full setup and deployment steps are in:

- `KIDS_SAFETY_SETUP.md`

## Hardware Supported

- ESP32-C3 Super Mini Development Board
- MPU6050 accelerometer + gyroscope
- MAX30102 heart rate + SpO2
- LiPo 3.7V battery + TP4056 USB-C charger
- 3V vibration motor module
- 6mm tactile push button
- 0.96" I2C OLED
- Breadboard/PCB + jumper wires

## Wiring (ESP32-C3)

Default pin mapping in `arduino/fall_detection_esp32.ino`:

- `GPIO8` -> I2C SDA (MPU6050 + MAX30102 + OLED SDA)
- `GPIO9` -> I2C SCL (MPU6050 + MAX30102 + OLED SCL)
- `GPIO3` -> Vibration motor IN
- `GPIO2` -> Push button (other side to GND, uses `INPUT_PULLUP`)
- `GPIO0` -> Battery divider midpoint (100k/100k divider from VBAT)
- `3V3` -> Sensor/OLED VCC
- `GND` -> Common ground for all modules

Notes:

- Keep MAX30102 and MPU6050 on 3.3V.
- Do not connect LiPo directly to ESP32 ADC without a divider.
- TP4056 `OUT+`/`OUT-` should power the system.

## Firmware (ESP32-C3)

Firmware file: `arduino/fall_detection_esp32.ino`

Install these Arduino libraries:

- Adafruit MPU6050
- SparkFun MAX3010x Pulse and Proximity Sensor Library
- U8g2
- ESP32 BLE Arduino

BLE protocol sent to Flutter:

- Service UUID: `12345678-1234-1234-1234-123456789abc`
- Sensor characteristic: `12345678-1234-1234-1234-123456789abe`
	- Example: `HR:72,SPO2:98.3,TILT:3.2,ACC:1.02,BATT:87,FALL:0,WIFI:1`
- Fall alert characteristic: `12345678-1234-1234-1234-123456789abd`
	- Binary payload: `[fallFlag, hrHigh, hrLow, tiltAngle, accelMag*10]`
- WiFi config characteristic (write): `12345678-1234-1234-1234-123456789abf`
	- App writes: `SSID=<name>;PASS=<password>;URL=<endpoint>`

On-device behavior:

- 3-stage fall detection (freefall -> impact -> orientation)
- 15-second cancel window after candidate fall
- Vibration motor active during pending/alert states
- Push button cancels false alarm before alert send
- OLED shows HR, SpO2, tilt, acceleration, battery, and alert state

## Flutter App

The app scans for BLE and displays live vitals + alert workflows.

WiFi settings in app:

- Open `Profile & Settings` -> `WiFi Settings`
- Save SSID, password, and server URL
- If device is connected on BLE, settings are pushed to ESP32 over BLE immediately

Run Android build:

```bash
flutter pub get
flutter run -d android --dart-define-from-file=dart_define.local.json
```

## Gemini AI Setup (Optional)

Create `dart_define.local.json` in project root:

```json
{
	"GEMINI_API_KEY": "YOUR_GEMINI_API_KEY"
}
```

This file should stay untracked.

/*
 * ============================================================
 *  RiskWatch Fall Detection Firmware (ESP32-C3 Super Mini)
 * ============================================================
 *
 *  Hardware:
 *    - ESP32-C3 Super Mini
 *    - MPU6050 (accel + gyro)
 *    - MAX30102 (heart rate + SpO2)
 *    - 0.96" I2C OLED
 *    - Vibration motor module (3V)
 *    - Tactile push button (cancel false alarm)
 *    - LiPo 3.7V + TP4056 charger
 *
 *  Default pin mapping (change if your board wiring differs):
 *    - I2C SDA: GPIO8
 *    - I2C SCL: GPIO9
 *    - Vibration motor: GPIO3
 *    - Push button: GPIO2 (active LOW, INPUT_PULLUP)
 *    - Battery ADC: GPIO0 (through 100k/100k divider)
 *
 *  BLE protocol (kept compatible with Flutter app):
 *    Service UUID:     12345678-1234-1234-1234-123456789abc
 *    Sensor Char UUID: 12345678-1234-1234-1234-123456789abe
 *      String format:
 *      "HR:72,SPO2:98.3,TILT:3.2,ACC:1.02,BATT:87,FALL:0"
 *    Fall Char UUID:   12345678-1234-1234-1234-123456789abd
 *      Binary format: [fallFlag, hrHigh, hrLow, tiltAngle, accelMag*10]
 *
 *  Required Arduino libraries:
 *    - Adafruit MPU6050
 *    - SparkFun MAX3010x Pulse and Proximity Sensor Library
 *    - U8g2
 *    - ESP32 BLE Arduino
 * ============================================================
 */

#include <Wire.h>
#include <math.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <MAX30105.h>
#include <heartRate.h>
#include <U8g2lib.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>
#include <Preferences.h>

// Pin mapping for ESP32-C3 Super Mini
static const int PIN_I2C_SDA = 8;
static const int PIN_I2C_SCL = 9;
static const int PIN_VIBRATION = 3;
static const int PIN_BUTTON = 2;
static const int PIN_BATTERY_ADC = 0;

// Fall detection thresholds
static const float IMPACT_THRESHOLD = 3.0f;
static const float FREEFALL_THRESHOLD = 0.4f;
static const float ANGLE_THRESHOLD = 60.0f;
static const int HR_STRESS_THRESHOLD = 100;
static const unsigned long DEBOUNCE_MS = 5000;
static const unsigned long FREEFALL_WINDOW_MS = 500;
static const unsigned long POST_IMPACT_MS = 1000;

// Alert workflow
static const unsigned long CONFIRMATION_MS = 15000;

// Loop timing
static const unsigned long HR_SAMPLE_PERIOD_MS = 20;
static const unsigned long SENSOR_SEND_PERIOD_MS = 300;
static const unsigned long OLED_REFRESH_MS = 500;
static const unsigned long BATTERY_REFRESH_MS = 10000;

// BLE UUIDs
static const char* SERVICE_UUID = "12345678-1234-1234-1234-123456789abc";
static const char* SENSOR_CHAR_UUID = "12345678-1234-1234-1234-123456789abe";
static const char* FALL_CHAR_UUID = "12345678-1234-1234-1234-123456789abd";
static const char* WIFI_CFG_CHAR_UUID = "12345678-1234-1234-1234-123456789abf";
static const char* BATTERY_SVC_UUID = "180F";
static const char* BATTERY_CHAR_UUID = "2A19";

Adafruit_MPU6050 mpu;
MAX30105 max30102;
U8G2_SSD1306_128X64_NONAME_F_HW_I2C oled(U8G2_R0, U8X8_PIN_NONE);

BLEServer* bleServer = nullptr;
BLEService* fallService = nullptr;
BLEService* batteryService = nullptr;
BLECharacteristic* sensorChar = nullptr;
BLECharacteristic* fallChar = nullptr;
BLECharacteristic* wifiCfgChar = nullptr;
BLECharacteristic* batteryChar = nullptr;

Preferences prefs;

bool bleConnected = false;
bool imuReady = false;
bool hrReady = false;

float accelX = 0;
float accelY = 0;
float accelZ = 1;
float accelMag = 1;
float tiltAngle = 0;
int heartRate = 0;
float spo2 = 0;
int batteryPercent = 100;
bool fingerDetected = false;
bool wifiConnected = false;
String wifiSsid;
String wifiPass;
String wifiServerUrl;

// Heart rate filter state
float bpmEma = 0;

// Fall history ring buffer
static const int ACCEL_HISTORY_SIZE = 64;
float accelHistory[ACCEL_HISTORY_SIZE];
unsigned long accelTimeHistory[ACCEL_HISTORY_SIZE];
int accelHistIdx = 0;

enum FallPhase { PHASE_IDLE, PHASE_IMPACT_DETECTED };
FallPhase fallPhase = PHASE_IDLE;
unsigned long impactTime = 0;
unsigned long lastFallTime = 0;

// Confirmation flow state
bool alertPending = false;
bool alertCancelled = false;
unsigned long pendingStartTime = 0;

// Non-blocking vibration patterns
enum VibMode { VIB_OFF, VIB_PENDING, VIB_ALERT };
VibMode vibMode = VIB_OFF;
bool vibOutputOn = false;
unsigned long vibToggleMs = 0;

// Loop timers
unsigned long lastHrSampleMs = 0;
unsigned long lastSensorSendMs = 0;
unsigned long lastOledRefreshMs = 0;
unsigned long lastBatteryRefreshMs = 0;
unsigned long lastWifiRetryMs = 0;

void loadWifiConfig() {
  prefs.begin("riskwatch", true);
  wifiSsid = prefs.getString("wifi_ssid", "");
  wifiPass = prefs.getString("wifi_pass", "");
  wifiServerUrl = prefs.getString("wifi_url", "");
  prefs.end();
}

void saveWifiConfig(const String& ssid, const String& pass, const String& url) {
  prefs.begin("riskwatch", false);
  prefs.putString("wifi_ssid", ssid);
  prefs.putString("wifi_pass", pass);
  prefs.putString("wifi_url", url);
  prefs.end();
  wifiSsid = ssid;
  wifiPass = pass;
  wifiServerUrl = url;
}

void tryConnectWifi() {
  if (wifiSsid.isEmpty()) return;
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  Serial.printf("WiFi connecting to SSID: %s\n", wifiSsid.c_str());

  const unsigned long start = millis();
  while (millis() - start < 6000) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiConnected = true;
      Serial.printf("WiFi connected, IP: %s\n", WiFi.localIP().toString().c_str());
      return;
    }
    delay(120);
  }

  wifiConnected = false;
  Serial.println("WiFi connect timeout");
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleConnected = true;
    Serial.println("BLE connected");
  }

  void onDisconnect(BLEServer* pServer) override {
    bleConnected = false;
    Serial.println("BLE disconnected, advertising...");
    BLEDevice::startAdvertising();
  }
};

class WifiConfigCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    std::string value = pCharacteristic->getValue();
    if (value.empty()) return;

    String msg = String(value.c_str());
    msg.trim();

    // Expected format: SSID=...;PASS=...;URL=...
    String ssid = "";
    String pass = "";
    String url = "";

    int p1 = msg.indexOf("SSID=");
    int p2 = msg.indexOf(";PASS=");
    int p3 = msg.indexOf(";URL=");

    if (p1 >= 0 && p2 > p1) {
      ssid = msg.substring(p1 + 5, p2);
      if (p3 > p2) {
        pass = msg.substring(p2 + 6, p3);
        url = msg.substring(p3 + 5);
      } else {
        pass = msg.substring(p2 + 6);
      }
    }

    ssid.trim();
    pass.trim();
    url.trim();

    if (ssid.isEmpty()) {
      Serial.println("WiFi config ignored: empty SSID");
      return;
    }

    saveWifiConfig(ssid, pass, url);
    Serial.printf("WiFi config received via BLE: ssid=%s\n", ssid.c_str());

    WiFi.disconnect(true);
    delay(100);
    tryConnectWifi();
  }
};

bool initImu() {
  if (!mpu.begin()) {
    Serial.println("MPU6050 not found at default address 0x68");
    return false;
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  Serial.println("MPU6050 initialized successfully");
  return true;
}

bool initMax30102() {
  if (!max30102.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found");
    return false;
  }

  max30102.setup(
    0x1F, // LED brightness
    4,    // sample average
    2,    // mode: red + IR
    100,  // sample rate
    411,  // pulse width
    4096  // ADC range
  );
  max30102.setPulseAmplitudeRed(0x24);
  max30102.setPulseAmplitudeIR(0x24);
  Serial.println("MAX30102 initialized");
  return true;
}

void initBle() {
  BLEDevice::init("RiskWatch_ESP32C3");
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  fallService = bleServer->createService(SERVICE_UUID);
  sensorChar = fallService->createCharacteristic(
    SENSOR_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensorChar->addDescriptor(new BLE2902());

  fallChar = fallService->createCharacteristic(
    FALL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  fallChar->addDescriptor(new BLE2902());

  wifiCfgChar = fallService->createCharacteristic(
    WIFI_CFG_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_WRITE_NR
  );
  wifiCfgChar->setCallbacks(new WifiConfigCallbacks());
  wifiCfgChar->setValue("SSID=;PASS=;URL=");

  batteryService = bleServer->createService(BATTERY_SVC_UUID);
  batteryChar = batteryService->createCharacteristic(
    BATTERY_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  batteryChar->addDescriptor(new BLE2902());

  sensorChar->setValue("HR:0,SPO2:0.0,TILT:0.0,ACC:1.00,BATT:100,FALL:0,WIFI:0");
  uint8_t initFall[5] = {0, 0, 0, 0, 10};
  fallChar->setValue(initFall, 5);
  uint8_t initBattery = 100;
  batteryChar->setValue(&initBattery, 1);

  fallService->start();
  batteryService->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising started");
}

void readImu() {
  if (!imuReady) return;

  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  // Convert m/s^2 to g
  accelX = a.acceleration.x / 9.80665f;
  accelY = a.acceleration.y / 9.80665f;
  accelZ = a.acceleration.z / 9.80665f;

  accelMag = sqrtf(accelX * accelX + accelY * accelY + accelZ * accelZ);
  if (accelMag > 0.01f) {
    float ratio = accelZ / accelMag;
    ratio = constrain(ratio, -1.0f, 1.0f);
    tiltAngle = acosf(ratio) * 180.0f / PI;
  }

  accelHistory[accelHistIdx % ACCEL_HISTORY_SIZE] = accelMag;
  accelTimeHistory[accelHistIdx % ACCEL_HISTORY_SIZE] = millis();
  accelHistIdx++;
}

void updateHeartAndSpO2() {
  if (!hrReady) return;

  long ir = max30102.getIR();
  long red = max30102.getRed();

  fingerDetected = (ir > 50000);
  if (!fingerDetected) {
    heartRate = 0;
    spo2 = 0;
    return;
  }

  if (checkForBeat(ir)) {
    static unsigned long lastBeatMs = 0;
    unsigned long now = millis();
    if (lastBeatMs > 0) {
      float deltaSec = (now - lastBeatMs) / 1000.0f;
      if (deltaSec > 0.3f && deltaSec < 2.0f) {
        float instantBpm = 60.0f / deltaSec;
        if (bpmEma < 1.0f) {
          bpmEma = instantBpm;
        } else {
          bpmEma = bpmEma * 0.7f + instantBpm * 0.3f;
        }
        bpmEma = constrain(bpmEma, 40.0f, 200.0f);
        heartRate = (int)bpmEma;
      }
    }
    lastBeatMs = now;
  }

  // Simple SpO2 approximation for live trend display.
  if (ir > 0 && red > 0) {
    float ratio = (float)red / (float)ir;
    float estimate = 110.0f - 25.0f * ratio;
    estimate = constrain(estimate, 70.0f, 100.0f);
    if (spo2 <= 0.1f) {
      spo2 = estimate;
    } else {
      spo2 = spo2 * 0.8f + estimate * 0.2f;
    }
  }
}

int readBatteryPercent() {
  int raw = analogRead(PIN_BATTERY_ADC);
  float voltage = ((float)raw / 4095.0f) * 3.3f * 2.0f;
  int pct = (int)((voltage - 3.0f) / (4.2f - 3.0f) * 100.0f);
  return constrain(pct, 0, 100);
}

bool hadFreefallRecently() {
  unsigned long now = millis();
  for (int i = 0; i < ACCEL_HISTORY_SIZE; i++) {
    int idx = ((accelHistIdx - 1 - i) % ACCEL_HISTORY_SIZE + ACCEL_HISTORY_SIZE) % ACCEL_HISTORY_SIZE;
    if (accelTimeHistory[idx] == 0) continue;
    if ((now - accelTimeHistory[idx]) > FREEFALL_WINDOW_MS) break;
    if (accelHistory[idx] < FREEFALL_THRESHOLD) return true;
  }
  return false;
}

bool detectFallCandidate() {
  unsigned long now = millis();

  if ((now - lastFallTime) < DEBOUNCE_MS || alertPending) {
    return false;
  }

  switch (fallPhase) {
    case PHASE_IDLE:
      if (accelMag > IMPACT_THRESHOLD && hadFreefallRecently()) {
        fallPhase = PHASE_IMPACT_DETECTED;
        impactTime = now;
        Serial.println("Fall candidate: impact after freefall");
      }
      break;

    case PHASE_IMPACT_DETECTED:
      if ((now - impactTime) < POST_IMPACT_MS) {
        if (tiltAngle > ANGLE_THRESHOLD) {
          bool hrConfirms = (heartRate == 0) || (heartRate > HR_STRESS_THRESHOLD);
          if (hrConfirms) {
            fallPhase = PHASE_IDLE;
            return true;
          }
        }
      } else {
        fallPhase = PHASE_IDLE;
      }
      break;
  }

  return false;
}

void startPendingAlert() {
  alertPending = true;
  alertCancelled = false;
  pendingStartTime = millis();
  vibMode = VIB_PENDING;
  Serial.println("Pending alert started (15s cancel window)");
}

void sendSensorData(bool fallFlag) {
  if (!bleConnected) return;

  char payload[96];
  snprintf(
    payload,
    sizeof(payload),
    "HR:%d,SPO2:%.1f,TILT:%.1f,ACC:%.2f,BATT:%d,FALL:%d,WIFI:%d",
    heartRate,
    spo2,
    tiltAngle,
    accelMag,
    batteryPercent,
    fallFlag ? 1 : 0,
    wifiConnected ? 1 : 0
  );

  sensorChar->setValue((uint8_t*)payload, strlen(payload));
  sensorChar->notify();
}

void sendFallAlert() {
  if (!bleConnected) {
    lastFallTime = millis();
    return;
  }

  uint8_t data[5];
  data[0] = 1;
  data[1] = (heartRate >> 8) & 0xFF;
  data[2] = heartRate & 0xFF;
  data[3] = (uint8_t)min((int)tiltAngle, 255);
  data[4] = (uint8_t)min((int)(accelMag * 10.0f), 255);

  fallChar->setValue(data, 5);
  fallChar->notify();

  sendSensorData(true);

  vibMode = VIB_ALERT;
  lastFallTime = millis();
  Serial.println("FALL ALERT SENT");
}

void handleButtonCancel() {
  static bool lastButtonState = HIGH;
  static unsigned long lastDebounceTime = 0;

  bool reading = digitalRead(PIN_BUTTON);
  if (reading != lastButtonState) {
    lastDebounceTime = millis();
    lastButtonState = reading;
  }

  if ((millis() - lastDebounceTime) > 35) {
    if (alertPending && reading == LOW) {
      alertCancelled = true;
      alertPending = false;
      vibMode = VIB_OFF;
      Serial.println("Pending alert cancelled by user");
    }
  }
}

void updateVibration() {
  unsigned long now = millis();

  switch (vibMode) {
    case VIB_OFF:
      vibOutputOn = false;
      digitalWrite(PIN_VIBRATION, LOW);
      return;

    case VIB_PENDING:
      // 250ms ON / 750ms OFF
      if (now - vibToggleMs >= (vibOutputOn ? 250 : 750)) {
        vibOutputOn = !vibOutputOn;
        vibToggleMs = now;
        digitalWrite(PIN_VIBRATION, vibOutputOn ? HIGH : LOW);
      }
      return;

    case VIB_ALERT:
      // 120ms ON / 180ms OFF for urgent state
      if (now - vibToggleMs >= (vibOutputOn ? 120 : 180)) {
        vibOutputOn = !vibOutputOn;
        vibToggleMs = now;
        digitalWrite(PIN_VIBRATION, vibOutputOn ? HIGH : LOW);
      }
      return;
  }
}

void updatePendingWindow() {
  if (!alertPending) return;

  unsigned long now = millis();
  if ((now - pendingStartTime) >= CONFIRMATION_MS) {
    alertPending = false;
    sendFallAlert();
  }
}

void updateOled() {
  unsigned long now = millis();
  if ((now - lastOledRefreshMs) < OLED_REFRESH_MS) return;
  lastOledRefreshMs = now;

  oled.clearBuffer();
  oled.setFont(u8g2_font_6x10_tf);

  char line1[32];
  char line2[32];
  char line3[32];
  char line4[32];

  snprintf(line1, sizeof(line1), "HR:%3d BPM  SpO2:%4.1f", heartRate, spo2);
  snprintf(line2, sizeof(line2), "Tilt:%5.1f  Acc:%4.2f", tiltAngle, accelMag);
  snprintf(
    line3,
    sizeof(line3),
    "Batt:%3d%% BLE:%s WiFi:%s",
    batteryPercent,
    bleConnected ? "ON" : "OFF",
    wifiConnected ? "ON" : "OFF"
  );

  if (alertPending) {
    int left = (int)((CONFIRMATION_MS - (millis() - pendingStartTime)) / 1000);
    if (left < 0) left = 0;
    snprintf(line4, sizeof(line4), "FALL? Cancel in %2ds", left);
  } else if (alertCancelled) {
    snprintf(line4, sizeof(line4), "Alert cancelled");
  } else if ((millis() - lastFallTime) < 10000 && lastFallTime > 0) {
    snprintf(line4, sizeof(line4), "ALERT SENT");
  } else {
    snprintf(line4, sizeof(line4), "Monitoring");
  }

  oled.drawStr(0, 12, line1);
  oled.drawStr(0, 28, line2);
  oled.drawStr(0, 44, line3);
  oled.drawStr(0, 60, line4);
  oled.sendBuffer();
}

void setup() {
  Serial.begin(115200);
  delay(600);

  Serial.println("\nRiskWatch ESP32-C3 firmware booting...");

  pinMode(PIN_VIBRATION, OUTPUT);
  digitalWrite(PIN_VIBRATION, LOW);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_BATTERY_ADC, INPUT);

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setClock(400000);

  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(0, 14, "RiskWatch ESP32-C3");
  oled.drawStr(0, 30, "Starting...");
  oled.sendBuffer();

  for (int i = 0; i < ACCEL_HISTORY_SIZE; i++) {
    accelHistory[i] = 1.0f;
    accelTimeHistory[i] = 0;
  }

  imuReady = initImu();
  hrReady = initMax30102();
  loadWifiConfig();
  tryConnectWifi();
  initBle();

  batteryPercent = readBatteryPercent();
  Serial.println("Setup complete");
}

void loop() {
  unsigned long now = millis();

  readImu();

  if ((now - lastHrSampleMs) >= HR_SAMPLE_PERIOD_MS) {
    updateHeartAndSpO2();
    lastHrSampleMs = now;
  }

  if (detectFallCandidate()) {
    startPendingAlert();
  }

  handleButtonCancel();
  updatePendingWindow();
  updateVibration();

  if ((now - lastBatteryRefreshMs) >= BATTERY_REFRESH_MS) {
    batteryPercent = readBatteryPercent();
    if (bleConnected) {
      uint8_t b = (uint8_t)batteryPercent;
      batteryChar->setValue(&b, 1);
      batteryChar->notify();
    }
    lastBatteryRefreshMs = now;
  }

  if ((now - lastWifiRetryMs) >= 10000) {
    wifiConnected = (WiFi.status() == WL_CONNECTED);
    if (!wifiConnected && !wifiSsid.isEmpty()) {
      tryConnectWifi();
    }
    lastWifiRetryMs = now;
  }

  if ((now - lastSensorSendMs) >= SENSOR_SEND_PERIOD_MS) {
    sendSensorData(false);
    lastSensorSendMs = now;
  }

  updateOled();
  delay(8);
}

#include <Wire.h>
#include <math.h>

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_SSD1306.h>

#include <MAX30105.h>
#include <heartRate.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =====================
// ESP32-C3 I2C pins
// NOTE: Many ESP32-C3 SuperMini boards use SDA=8, SCL=9.
// If I2C scan finds 0 devices, try changing these to 8/9.
// =====================
#define SDA_PIN 4
#define SCL_PIN 5

// =====================
// OLED
// =====================
Adafruit_SSD1306 display(128, 64, &Wire, -1);

// =====================
// Sensors
// =====================
Adafruit_MPU6050 mpu;
MAX30105 max30102;

// =====================
// BLE UUIDs (MUST MATCH Flutter app)
// =====================
#define SERVICE_UUID      "12345678-1234-1234-1234-123456789abc"
#define SENSOR_CHAR_UUID  "12345678-1234-1234-1234-123456789abe"
#define FALL_CHAR_UUID    "12345678-1234-1234-1234-123456789abd"

BLEServer* pServer = nullptr;
BLECharacteristic* sensorChar = nullptr;
BLECharacteristic* fallChar = nullptr;
bool bleConn = false;

class BLECallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    bleConn = true;
    Serial.println("BLE connected");
  }

  void onDisconnect(BLEServer* s) override {
    bleConn = false;
    Serial.println("BLE disconnected");
    BLEDevice::startAdvertising();
  }
};

// =====================
// Heart-rate state
// =====================
bool fingerDetected = false;
int bpm = 0;
float bpmEma = 0.0f;

// =====================
// SpO2 estimate (simple, non-medical)
// Uses ratio-of-ratios from RED/IR AC/DC components.
// =====================
float irDc = 0.0f, redDc = 0.0f;
float irAcSqSum = 0.0f, redAcSqSum = 0.0f;
uint16_t ppgSamples = 0;
float spo2 = 0.0f;
bool spo2Ready = false;
static const byte SPO2_AVG_SIZE = 5;
float spo2Samples[SPO2_AVG_SIZE] = {0};
byte spo2Spot = 0;
byte spo2Count = 0;

// =====================
// Sensor values the Flutter app expects
// =====================
float accelMagG = 1.0f;
float tiltAngleDeg = 0.0f;
float spo2 = 0.0f;          // placeholder (kept for app compatibility)
int batteryPercent = 100;   // placeholder (wire ADC divider if you need real value)

// =====================
// Fall detection (simple)
// =====================
bool freeFallSeen = false;
unsigned long freeFallTimeMs = 0;
unsigned long fallAlertTimeMs = 0;

static const float FREEFALL_THRESHOLD_G = 0.4f;
static const float IMPACT_THRESHOLD_G = 3.0f;
static const unsigned long FREEFALL_WINDOW_MS = 500;

// =====================
// Timing
// =====================
unsigned long lastSendMs = 0;
static const unsigned long SEND_PERIOD_MS = 300;

void scanI2C() {
  Serial.println("Scanning I2C bus...");
  byte count = 0;
  for (byte addr = 8; addr < 120; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.print("I2C device found at 0x");
      Serial.println(addr, HEX);
      count++;
    }
  }
  Serial.print("Total I2C devices found: ");
  Serial.println(count);
}

bool initMpu6050() {
  // Try default 0x68 then alternate 0x69.
  if (mpu.begin()) {
    return true;
  }
  Serial.println("MPU6050 not found at 0x68, trying 0x69...");
  return mpu.begin(0x69, &Wire);
}

void setupBle() {
  BLEDevice::init("RiskWatch_ESP32C3");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLECallbacks());

  BLEService* service = pServer->createService(SERVICE_UUID);

  sensorChar = service->createCharacteristic(
    SENSOR_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensorChar->addDescriptor(new BLE2902());
  sensorChar->setValue("HR:0,SPO2:0.0,TILT:0.0,ACC:1.00,BATT:100,FALL:0");

  fallChar = service->createCharacteristic(
    FALL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  fallChar->addDescriptor(new BLE2902());
  uint8_t initFall[5] = {0, 0, 0, 0, 10};
  fallChar->setValue(initFall, 5);

  service->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started");
}

void updateMpuReadings() {
  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);

  // convert m/s^2 -> g
  const float ax = a.acceleration.x / 9.80665f;
  const float ay = a.acceleration.y / 9.80665f;
  const float az = a.acceleration.z / 9.80665f;

  accelMagG = sqrtf(ax * ax + ay * ay + az * az);
  if (accelMagG > 0.01f) {
    float ratio = az / accelMagG;
    ratio = constrain(ratio, -1.0f, 1.0f);
    tiltAngleDeg = acosf(ratio) * 180.0f / PI;
  }
}

void updateHeartRate() {
  const long ir = max30102.getIR();
  const long red = max30102.getRed();
  fingerDetected = (ir > 50000);

  // Update DC filters + AC energy for SpO2 estimation
  irDc = (irDc * 0.95f) + ((float)ir * 0.05f);
  redDc = (redDc * 0.95f) + ((float)red * 0.05f);
  const float irAc = (float)ir - irDc;
  const float redAc = (float)red - redDc;
  irAcSqSum += irAc * irAc;
  redAcSqSum += redAc * redAc;
  ppgSamples++;

  if (!fingerDetected) {
    bpm = 0;
    bpmEma = 0.0f;
    spo2 = 0.0f;
    spo2Ready = false;
    irAcSqSum = 0.0f;
    redAcSqSum = 0.0f;
    ppgSamples = 0;
    return;
  }

  if (checkForBeat(ir)) {
    static unsigned long lastBeatMs = 0;
    const unsigned long now = millis();

    if (lastBeatMs != 0) {
      const float deltaSec = (now - lastBeatMs) / 1000.0f;
      if (deltaSec > 0.3f && deltaSec < 2.0f) {
        const float instant = 60.0f / deltaSec;
        bpmEma = (bpmEma < 1.0f) ? instant : (bpmEma * 0.7f + instant * 0.3f);
        bpmEma = constrain(bpmEma, 40.0f, 200.0f);
        bpm = (int)bpmEma;
      }
    }

    lastBeatMs = now;

    // SpO2 update on each detected beat (RMS AC over beat window)
    if (ppgSamples > 10 && irDc > 1000.0f && redDc > 1000.0f) {
      const float irRms = sqrtf(irAcSqSum / (float)ppgSamples);
      const float redRms = sqrtf(redAcSqSum / (float)ppgSamples);
      if (irRms > 1.0f && redRms > 1.0f) {
        const float r = (redRms / redDc) / (irRms / irDc);
        float est = 110.0f - 25.0f * r;
        est = constrain(est, 0.0f, 100.0f);

        spo2Samples[spo2Spot++] = est;
        spo2Spot %= SPO2_AVG_SIZE;
        if (spo2Count < SPO2_AVG_SIZE) spo2Count++;

        float sum = 0.0f;
        for (byte i = 0; i < spo2Count; i++) sum += spo2Samples[i];
        spo2 = sum / (float)spo2Count;
        spo2Ready = (spo2Count >= 3);
      }
    }

    // Reset beat window accumulators
    irAcSqSum = 0.0f;
    redAcSqSum = 0.0f;
    ppgSamples = 0;
  }
}

void updateFallDetection() {
  const unsigned long now = millis();

  if (accelMagG < FREEFALL_THRESHOLD_G && !freeFallSeen) {
    freeFallSeen = true;
    freeFallTimeMs = now;
  }

  if (freeFallSeen && accelMagG > IMPACT_THRESHOLD_G && (now - freeFallTimeMs) < FREEFALL_WINDOW_MS) {
    fallAlertTimeMs = now;
    freeFallSeen = false;
    Serial.println("FALL ALERT!");
  }

  if (freeFallSeen && (now - freeFallTimeMs) > 1000) {
    freeFallSeen = false;
  }
}

void sendBlePayloads() {
  if (!bleConn || sensorChar == nullptr || fallChar == nullptr) return;

  const bool fall = (millis() - fallAlertTimeMs) < 5000;

  char payload[96];
  snprintf(
    payload,
    sizeof(payload),
    "HR:%d,SPO2:%.1f,TILT:%.1f,ACC:%.2f,BATT:%d,FALL:%d",
    bpm,
    (spo2Ready ? spo2 : 0.0f),
    tiltAngleDeg,
    accelMagG,
    batteryPercent,
    fall ? 1 : 0
  );

  sensorChar->setValue((uint8_t*)payload, strlen(payload));
  sensorChar->notify();

  if (fall) {
    uint8_t fallData[5];
    fallData[0] = 1;
    fallData[1] = (bpm >> 8) & 0xFF;
    fallData[2] = bpm & 0xFF;
    fallData[3] = (uint8_t)min((int)tiltAngleDeg, 255);
    fallData[4] = (uint8_t)min((int)(accelMagG * 10.0f), 255);
    fallChar->setValue(fallData, 5);
    fallChar->notify();
  }
}

void drawOled() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  display.setCursor(0, 0);
  display.print("HR: ");
  if (!fingerDetected) {
    display.print("No finger");
  } else {
    display.print(bpm);
    display.print(" bpm");
  }

  display.setCursor(0, 12);
  display.print("Acc: ");
  display.print(accelMagG, 2);
  display.print(" g");

  display.setCursor(0, 24);
  display.print("Tilt: ");
  display.print(tiltAngleDeg, 1);
  display.print(" deg");

  display.setCursor(0, 36);
  display.print("BLE: ");
  display.print(bleConn ? "ON" : "WAIT");

  const bool fall = (millis() - fallAlertTimeMs) < 5000;
  display.setCursor(0, 48);
  display.print(fall ? "!!! FALL !!!" : "Status: SAFE");

  display.display();
}

void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.print("I2C pins: SDA=");
  Serial.print(SDA_PIN);
  Serial.print(" SCL=");
  Serial.println(SCL_PIN);

  // Help I2C stability on boards/modules without strong pullups.
  pinMode(SDA_PIN, INPUT_PULLUP);
  pinMode(SCL_PIN, INPUT_PULLUP);

  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  Wire.setClock(100000);
  delay(100);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("Booting...");
  display.display();

  scanI2C();

  if (!initMpu6050()) {
    Serial.println("MPU6050 FAIL: check I2C wiring/pins");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("MPU6050 FAIL");
    display.print("SDA=");
    display.print(SDA_PIN);
    display.print(" SCL=");
    display.println(SCL_PIN);
    display.println("If 0 devices: try 8/9");
    display.display();
    while (true) delay(200);
  }

  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  if (!max30102.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("MAX30102 FAIL: check I2C wiring");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("MAX30102 FAIL");
    display.display();
    while (true) delay(200);
  }

  max30102.setup(0x3F, 4, 2, 100, 411, 4096);

  setupBle();

  Serial.println("READY");
}

void loop() {
  updateMpuReadings();
  updateHeartRate();
  updateFallDetection();

  const unsigned long now = millis();
  if ((now - lastSendMs) >= SEND_PERIOD_MS) {
    sendBlePayloads();
    lastSendMs = now;
  }

  drawOled();
  delay(20);
}

#include <Wire.h>
#include <math.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_SSD1306.h>
#include <MAX30105.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ── PINS ──
#define SDA_PIN 4
#define SCL_PIN 5

// ── DEVICES ──
Adafruit_MPU6050 mpu;
Adafruit_SSD1306 display(128, 64, &Wire, -1);
MAX30105         max30102;

// ── BLE UUIDs (MUST MATCH Flutter app) ──
#define SERVICE_UUID      "12345678-1234-1234-1234-123456789abc"
#define SENSOR_CHAR_UUID  "12345678-1234-1234-1234-123456789abe"
#define FALL_CHAR_UUID    "12345678-1234-1234-1234-123456789abd"

BLEServer*         pServer    = nullptr;
BLECharacteristic* pSensorChar = nullptr;
BLECharacteristic* pFallChar  = nullptr;
bool               bleConn    = false;

class BLECallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s)    { bleConn = true; }
  void onDisconnect(BLEServer* s) {
    bleConn = false;
    BLEDevice::startAdvertising();
  }
};

class FallCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    // Any write from the phone app is treated as a remote cancel
    // of the current fall alert.
    if (characteristic->getValue().length() == 0) return;
    fallAlertTime = 0;
    freeFallSeen = false;
    Serial.println(F("Cancelled(remote)"));
  }
};

// ── HEART RATE ──
const byte RATE_SIZE = 4;
byte   rates[RATE_SIZE];
byte   rateSpot  = 0;
int    bpmAvg    = 0;
bool   hrReady   = false;
byte   beatCount = 0;

// ── BEAT DETECTION (DC removal) ──
float  dcFilter      = 0;
float  acSignal      = 0;
float  prevAC        = 0;
unsigned long lastBeatTime = 0;
unsigned long lastBeat     = 0;

// ── FALL STATE ──
bool  freeFallSeen   = false;
unsigned long freeFallTime   = 0;
unsigned long fallAlertTime  = 0;

// ── SENSOR EXTRA FIELDS (required by Flutter parser) ──
float tiltAngle = 0.0f;
float accelMagG = 1.0f;
float spo2Value = 0.0f; // not computed in this sketch; kept for compatibility
int batteryPercent = 100; // TODO: read from ADC if you wire a battery divider

void resetHR() {
  hrReady = false;
  beatCount = rateSpot = bpmAvg = 0;
  lastBeat = lastBeatTime = 0;
  dcFilter = acSignal = prevAC = 0;
  memset(rates, 0, sizeof(rates));
}

bool detectBeat(long irValue) {
  dcFilter = (dcFilter * 0.95f) + ((float)irValue * 0.05f);
  prevAC   = acSignal;
  acSignal = (float)irValue - dcFilter;

  if (prevAC > 0 && acSignal <= 0 && prevAC > 50) {
    unsigned long now = millis();
    if (now - lastBeatTime > 333) {
      lastBeatTime = now;
      return true;
    }
  }
  return false;
}

// Scan I2C bus to find devices (helps debug MPU6050 wiring)
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

// ── SETUP ──
void setup() {
  Serial.begin(115200);
  delay(500);
  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  Wire.setClock(100000);
  delay(100);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.print("Starting...");
  display.display();

  // I2C debug
  scanI2C();

  // MPU6050 init (try 0x68 then 0x69)
  if (!mpu.begin()) {
    Serial.println("MPU6050 not found at 0x68, trying 0x69...");
    if (!mpu.begin(0x69)) {
      Serial.println("MPU6050 not found at 0x69 either. Check I2C wiring/pins.");
      display.clearDisplay();
      display.setCursor(0, 0);
      display.print("MPU6050 FAIL");
      display.setCursor(0, 12);
      display.print("SDA=4 SCL=5");
      display.display();
      while (1) delay(200);
    }
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  if (!max30102.begin(Wire, I2C_SPEED_STANDARD)) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.print("MAX30102 FAIL");
    display.display();
    while (1);
  }

  max30102.setup(0x3F, 4, 2, 400, 411, 4096);

  // ── BLE ──
  BLEDevice::init("FallDetector");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLECallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Sensor data characteristic (CSV string)
  pSensorChar = pService->createCharacteristic(
    SENSOR_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pSensorChar->addDescriptor(new BLE2902());
  pSensorChar->setValue("HR:0,SPO2:0.0,TILT:0.0,ACC:1.00,BATT:100,FALL:0");

  pFallChar = pService->createCharacteristic(FALL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_WRITE
  );
  pFallChar->addDescriptor(new BLE2902());
  pFallChar->setCallbacks(new FallCharCallbacks());

  pService->start();
  BLEDevice::startAdvertising();

  Serial.println("READY");
}

// ── LOOP ──
void loop() {
  // MPU6050
  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);

  const float ax = a.acceleration.x / 9.80665f;
  const float ay = a.acceleration.y / 9.80665f;
  const float az = a.acceleration.z / 9.80665f;
  accelMagG = sqrtf(ax * ax + ay * ay + az * az);
  if (accelMagG > 0.01f) {
    float ratio = az / accelMagG;
    ratio = constrain(ratio, -1.0f, 1.0f);
    tiltAngle = acosf(ratio) * 180.0f / PI;
  }

  // MAX30102
  long irValue = max30102.getIR();

  if (irValue > 50000) {
    if (detectBeat(irValue)) {
      unsigned long now = millis();
      if (lastBeat == 0) {
        lastBeat = now;
      } else {
        long delta  = now - lastBeat;
        lastBeat    = now;
        float bpm   = 60000.0f / delta;

        if (bpm > 40 && bpm < 180) {
          rates[rateSpot++] = (byte)bpm;
          rateSpot %= RATE_SIZE;
          beatCount++;

          bpmAvg = 0;
          for (byte i = 0; i < RATE_SIZE; i++) bpmAvg += rates[i];
          bpmAvg /= RATE_SIZE;

          if (beatCount >= RATE_SIZE) hrReady = true;
        }
      }
    }
  } else {
    resetHR();
  }

  // FALL DETECTION (in g)
  if (accelMagG < 0.4f && !freeFallSeen) {
    freeFallSeen = true;
    freeFallTime = millis();
  }
  if (freeFallSeen && accelMagG > 3.0f && (millis() - freeFallTime < 500)) {
    fallAlertTime = millis();
    freeFallSeen  = false;
    Serial.println("FALL ALERT!");
  }
  if (freeFallSeen && (millis() - freeFallTime > 1000)) freeFallSeen = false;

  bool showFall = (millis() - fallAlertTime < 5000);

  // BLE notify
  if (bleConn) {
    // Send sensor CSV string (what Flutter app parses)
    char sensorPayload[96];
    snprintf(
      sensorPayload,
      sizeof(sensorPayload),
      "HR:%d,SPO2:%.1f,TILT:%.1f,ACC:%.2f,BATT:%d,FALL:%d",
      hrReady ? bpmAvg : 0,
      spo2Value,
      tiltAngle,
      accelMagG,
      batteryPercent,
      showFall ? 1 : 0
    );
    pSensorChar->setValue((uint8_t*)sensorPayload, strlen(sensorPayload));
    pSensorChar->notify();

    // Send fall binary notification (what Flutter expects)
    if (showFall) {
      uint8_t fallData[5];
      fallData[0] = 1;
      fallData[1] = (bpmAvg >> 8) & 0xFF;
      fallData[2] = bpmAvg & 0xFF;
      fallData[3] = (uint8_t)min((int)tiltAngle, 255);
      fallData[4] = (uint8_t)min((int)(accelMagG * 10.0f), 255);
      pFallChar->setValue(fallData, 5);
      pFallChar->notify();
    }
  }

  // OLED
  display.clearDisplay();

  // HR
  display.setCursor(0, 0);
  display.print("HR: ");
  if (irValue <= 50000)   display.print("No finger");
  else if (!hrReady)       display.print("...");
  else { display.print(bpmAvg); display.print(" BPM"); }

  // Accel
  display.setCursor(0, 14);
  display.print("Accel: ");
  display.print(accelMagG, 2);

  // BLE
  display.setCursor(0, 28);
  display.print("BLE: ");
  display.print(bleConn ? "connected" : "waiting");

  // Status
  display.setCursor(0, 40);
  if (showFall) display.print("!!! FALL DETECTED !!!");
  else          display.print("Status: SAFE");

  display.display();
  delay(20);
}

/*
 * SafeBrace — ESP32-C3 SuperMini Firmware
 * Fall Detection with BLE, HR, SpO2, OLED
 */

#include <Wire.h>
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
#define VIBE_MOTOR_PIN 6
#define CANCEL_BUTTON_PIN 7

// ── DEVICES ──
Adafruit_MPU6050 mpu;
Adafruit_SSD1306 display(128, 64, &Wire, -1);
MAX30105 max30102;

// ── BLE ──
#define SERVICE_UUID   "12345678-1234-1234-1234-123456789abc"
#define HR_CHAR_UUID   "12345678-1234-1234-1234-123456789abe"
#define FALL_CHAR_UUID "12345678-1234-1234-1234-123456789abd"

BLEServer* pServer = nullptr;
BLECharacteristic* pHRChar = nullptr;
BLECharacteristic* pFallChar = nullptr;
bool bleConn = false;

class BLECallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) { bleConn = true; }
  void onDisconnect(BLEServer* s) {
    bleConn = false;
    BLEDevice::startAdvertising();
  }
};

// ── HEART RATE ──
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
int bpmAvg = 0;
bool hrReady = false;
byte beatCount = 0;

// ── BEAT DETECTION (DC removal) ──
float dcFilter = 0;
float acSignal = 0;
float prevAC = 0;
unsigned long lastBeatTime = 0;
unsigned long lastBeat = 0;

// ── FALL STATE FSM ──
enum FallState {
  NORMAL = 0,
  FREE_FALL,
  IMPACT,
  STILLNESS_CHECK,
  ALERT
};

FallState fallState = NORMAL;
unsigned long freeFallTime = 0;
unsigned long impactTime = 0;
unsigned long stillnessStartTime = 0;
unsigned long fallAlertTime = 0;

// Thresholds
static const float TH_SVM_FREEFALL = 0.5f;
static const float TH_SVM_IMPACT = 2.5f;
static const float TH_GYRO = 200.0f;
static const float TH_TILT = 60.0f;

// Timing windows
static const unsigned long T_STILL_MS = 2000;
static const unsigned long T_CANCEL_MS = 20000;
static const unsigned long T_FREEFALL_WINDOW_MS = 800;

// ── SpO2 estimate ──
float spo2 = 0.0f;
bool spo2Ready = false;
float irDc = 0.0f, redDc = 0.0f;
float irAcSqSum = 0.0f, redAcSqSum = 0.0f;
uint16_t ppgSamples = 0;
static const byte SPO2_AVG_SIZE = 5;
float spo2Samples[SPO2_AVG_SIZE] = {0};
byte spo2Spot = 0;
byte spo2Count = 0;

// Global tilt for use in all functions
float tiltDeg = 0.0f;

// ── OLED helpers ──
static const int OLED_W = 128;
static const int OLED_H = 64;

void drawCenteredText(const char* text) {
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds(text, 0, 0, &x1, &y1, &w, &h);
  int x = (OLED_W - (int)w) / 2 - x1;
  int y = (OLED_H - (int)h) / 2 - y1;
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  display.setCursor(x, y);
  display.print(text);
}

void showSplashScreen() {
  display.clearDisplay();
  display.setTextColor(WHITE);
  display.setTextSize(2);
  drawCenteredText("SafeBrace");
  display.display();
  display.setTextSize(1);
}

void resetHR() {
  hrReady = false;
  beatCount = rateSpot = bpmAvg = 0;
  lastBeat = lastBeatTime = 0;
  dcFilter = acSignal = prevAC = 0;
  memset(rates, 0, sizeof(rates));
}

bool detectBeat(long irValue) {
  dcFilter = (dcFilter * 0.95f) + ((float)irValue * 0.05f);
  prevAC = acSignal;
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

// ── SETUP ──
void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  // Motor and button
  pinMode(VIBE_MOTOR_PIN, OUTPUT);
  digitalWrite(VIBE_MOTOR_PIN, LOW);
  pinMode(CANCEL_BUTTON_PIN, INPUT_PULLUP);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0, 0);
  display.println(F("SafeBrace Init..."));
  display.display();

  showSplashScreen();
  delay(1200);

  mpu.begin();

  if (!max30102.begin(Wire, I2C_SPEED_STANDARD)) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println(F("MAX30102 FAIL"));
    display.display();
    while (1);
  }

  max30102.setup(0x3F, 4, 2, 400, 411, 4096);

  display.clearDisplay();
  display.setTextColor(WHITE);
  display.setTextSize(2);
  drawCenteredText("SafeBrace");
  display.display();
  display.setTextSize(1);

  // BLE
  BLEDevice::init("SafeBrace");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLECallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pHRChar = pService->createCharacteristic(HR_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pHRChar->addDescriptor(new BLE2902());

  pFallChar = pService->createCharacteristic(FALL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pFallChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println(F("SafeBrace READY"));
}

// ── LOOP ──
void loop() {
  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);

  float accel = sqrt(
    a.acceleration.x * a.acceleration.x +
    a.acceleration.y * a.acceleration.y +
    a.acceleration.z * a.acceleration.z
  );

  // Calculate tilt angle (global)
  tiltDeg = 0.0f;
  if (accel > 0.01f) {
    float ratio = a.acceleration.z / accel;
    ratio = constrain(ratio, -1.0f, 1.0f);
    tiltDeg = acosf(ratio) * 180.0f / PI;
  }

  float svmG = accel / 9.80665f;

  float gyroMag = sqrt(g.gyro.x * g.gyro.x +
                        g.gyro.y * g.gyro.y +
                        g.gyro.z * g.gyro.z) * (180.0f / PI);

  // MAX30102
  long irValue = max30102.getIR();
  long redValue = max30102.getRed();

  irDc = (irDc * 0.95f) + ((float)irValue * 0.05f);
  redDc = (redDc * 0.95f) + ((float)redValue * 0.05f);

  const float irAc = (float)irValue - irDc;
  const float redAc = (float)redValue - redDc;
  irAcSqSum += irAc * irAc;
  redAcSqSum += redAc * redAc;
  ppgSamples++;

  if (irValue > 50000) {
    if (detectBeat(irValue)) {
      unsigned long now = millis();
      if (lastBeat == 0) {
        lastBeat = now;
      } else {
        long delta = now - lastBeat;
        lastBeat = now;
        float bpm = 60000.0f / delta;

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

      irAcSqSum = 0.0f;
      redAcSqSum = 0.0f;
      ppgSamples = 0;
    }
  } else {
    resetHR();
    spo2Ready = false;
    spo2 = 0.0f;
    irAcSqSum = 0.0f;
    redAcSqSum = 0.0f;
    ppgSamples = 0;
  }

  // ── FALL DETECTION FSM ──
  unsigned long nowMs = millis();
  bool fallDetected = false;

  switch (fallState) {
    case NORMAL:
      if (tiltDeg > TH_TILT) {
        fallState = ALERT;
        fallAlertTime = nowMs;
        fallDetected = true;
        Serial.println(F("FALL: Tilt > 60°"));
        break;
      }
      
      if (svmG < TH_SVM_FREEFALL) {
        fallState = FREE_FALL;
        freeFallTime = nowMs;
        Serial.println(F("FREE FALL"));
      }
      break;

    case FREE_FALL:
      if (svmG > TH_SVM_IMPACT) {
        fallState = IMPACT;
        impactTime = nowMs;
        Serial.println(F("IMPACT"));
      } else if (nowMs - freeFallTime > T_FREEFALL_WINDOW_MS) {
        fallState = NORMAL;
      }
      break;

    case IMPACT:
      if (gyroMag > TH_GYRO) {
        fallState = STILLNESS_CHECK;
        stillnessStartTime = 0;
        Serial.println(F("GYRO CONFIRMED"));
      } else if (nowMs - impactTime > 600) {
        fallState = NORMAL;
      }
      break;

    case STILLNESS_CHECK:
      if (svmG >= 0.8f && svmG <= 1.2f && gyroMag < 50.0f) {
        if (stillnessStartTime == 0) stillnessStartTime = nowMs;
        if (nowMs - stillnessStartTime >= T_STILL_MS) {
          fallState = ALERT;
          fallAlertTime = nowMs;
          fallDetected = true;
          Serial.println(F("STILLNESS -> ALERT"));
        }
      } else {
        stillnessStartTime = 0;
      }

      if (nowMs - impactTime > 5000) {
        fallState = ALERT;
        fallAlertTime = nowMs;
        fallDetected = true;
        Serial.println(F("ALERT (timeout)"));
      }
      break;

    case ALERT:
      digitalWrite(VIBE_MOTOR_PIN, HIGH);
      
      if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
        fallState = NORMAL;
        digitalWrite(VIBE_MOTOR_PIN, LOW);
        Serial.println(F("ALERT CANCELLED"));
      }
      
      if (nowMs - fallAlertTime >= T_CANCEL_MS) {
        fallState = NORMAL;
        digitalWrite(VIBE_MOTOR_PIN, LOW);
        Serial.println(F("ALERT CLOSED"));
      }
      break;
  }

  bool showFall = (fallState == ALERT);

  // BLE notify
  if (bleConn) {
    const float accelG = accel / 9.80665f;
    const int hr = hrReady ? bpmAvg : 0;
    const float spo2Out = (spo2Ready ? spo2 : 0.0f);

    char payload[96];
    snprintf(payload, sizeof(payload),
      "HR:%d,SPO2:%.1f,TILT:%.1f,ACC:%.2f,GYRO:%.1f,FALL:%d",
      hr, spo2Out, tiltDeg, accelG, gyroMag, showFall ? 1 : 0);
    pHRChar->setValue((uint8_t*)payload, strlen(payload));
    pHRChar->notify();

    if (showFall) {
      uint8_t fallData[5] = {1, (hr >> 8) & 0xFF, hr & 0xFF,
                             (uint8_t)min((int)tiltDeg, 255),
                             (uint8_t)min((int)(accelG * 10.0f), 255)};
      pFallChar->setValue(fallData, 5);
      pFallChar->notify();
    }
  }

  // OLED
  display.clearDisplay();
  display.setCursor(0, 0);

  display.print(F("HR: "));
  if (irValue <= 50000) {
  } else if (!hrReady) {
    display.print(F("..."));
  } else {
    display.print(bpmAvg);
    display.print(F(" BPM"));
  }

  display.setCursor(0, 14);
  display.print(F("Accel: "));
  display.print(accel, 1);

  display.setCursor(0, 28);
  display.print(F("SpO2: "));
  if (irValue <= 50000) {
  } else if (!spo2Ready) {
    display.print(F("..."));
  } else {
    display.print(spo2, 1);
    display.print(F("%"));
  }

  display.setCursor(0, 40);
  display.print(F("BLE: "));
  display.print(bleConn ? F("OK") : F("--"));

  display.setCursor(0, 52);
  if (showFall) {
    display.print(F("!ALERT! (20s)"));
  } else {
    display.print(F("SAFE"));
  }

  display.display();
  delay(20);
}

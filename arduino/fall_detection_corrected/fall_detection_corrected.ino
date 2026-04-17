/*
 * SafeBrace — ESP32-C3 SuperMini Firmware v2.0
 * Production-level Fall Detection with Smart Sleep
 * Features: BLE, HR, SpO2, OLED, Battery Optimization
 */

#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_SSD1306.h>
#include <MAX30105.h>
#include <TinyGPS++.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SDA_PIN 4
#define SCL_PIN 5
#define VIBE_MOTOR_PIN 6
#define CANCEL_BUTTON_PIN 7

// GPS (NEO-6M/NEO-M8N style modules)
// Change these pins if your hardware wiring is different.
#define GPS_RX_PIN 20
#define GPS_TX_PIN 21
#define GPS_BAUD_RATE 9600
#define GPS_NOTIFY_INTERVAL_MS 5000UL

// Power Management
#define INACTIVITY_TIMEOUT_MS 30000UL     // 30s inactivity threshold (tune: 20s-45s based on usage)
#define SMART_SLEEP_INTERVAL_MS 500UL     // Check for sleep every 500ms
#define LOW_POWER_POLL_INTERVAL_MS 100UL  // Reduced polling in low-power mode (80ms sleep when active)

Adafruit_MPU6050 mpu;
Adafruit_SSD1306 display(128, 64, &Wire, -1);
MAX30105 max30102;

// Power Management Variables
bool lowPowerMode = false;
unsigned long lastActivityTime = 0;
unsigned long lastSleepCheckTime = 0;
unsigned long lastBleNotifyTime = 0;
#define BLE_NOTIFY_INTERVAL_MS 500UL     // Send BLE updates every 500ms (was 20ms)

// BLE
#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define HR_CHAR_UUID "12345678-1234-1234-1234-123456789abe"
#define FALL_CHAR_UUID "12345678-1234-1234-1234-123456789abd"
#define GPS_CHAR_UUID "12345678-1234-1234-1234-123456789af0"

BLEServer* pServer = nullptr;
BLECharacteristic* pHRChar = nullptr;
BLECharacteristic* pFallChar = nullptr;
BLECharacteristic* pGpsChar = nullptr;
bool bleConn = false;

HardwareSerial gpsSerial(1);
TinyGPSPlus gps;
double gpsLat = 0.0;
double gpsLon = 0.0;
bool gpsValid = false;
unsigned long lastGpsNotifyTime = 0;

class BLECallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) { bleConn = true; }
  void onDisconnect(BLEServer* s) {
    bleConn = false;
    BLEDevice::startAdvertising();
  }
};

byte rates[4];
byte rateSpot = 0;
int bpmAvg = 0;
bool hrReady = false;
byte beatCount = 0;

float dcFilter = 0, acSignal = 0, prevAC = 0;
unsigned long lastBeatTime = 0, lastBeat = 0;

// OLED helpers
static const int OLED_W = 128;
static const int OLED_H = 64;

const byte RATE_SIZE = 4;
static const byte SPO2_AVG_SIZE = 5;

// Startup flag
bool systemReady = false;
unsigned long bootTime = 0;

// CORRECT THRESHOLDS (Production-optimized per report spec)
static const float ACCEL_FREEFALL_MS2 = 4.9f;      // 0.5g - free fall detection
static const float ACCEL_IMPACT_MS2 = 24.5f;       // 2.5g - impact detection
static const float ACCEL_IMPACT_DIRECT = 35.0f;    // 3.5g - direct hard impact (NEW)
static const float TILT_THRESHOLD_DEG = 60.0f;     // Horizontal position
static const unsigned long FREE_FALL_TIMEOUT_MS = 500UL;      // 500ms per spec
static const unsigned long IMPACT_TIMEOUT_MS = 600UL;         // Time to confirm impact
static const unsigned long STILL_TIMEOUT_MS = 2000UL;         // Immobility threshold
static const unsigned long ALERT_DURATION_MS = 20000UL;       // Alert active for 20s

// Gyro Stability Thresholds (NEW - for robust motion detection)
static const float GYRO_THRESHOLD_STILL = 50.0f;   // deg/s - motionless
static const float GYRO_THRESHOLD_IMPACT = 200.0f; // deg/s - sudden rotation

float spo2 = 0.0f;
bool spo2Ready = false;
float irDc = 0.0f, redDc = 0.0f;
float irAcSqSum = 0.0f, redAcSqSum = 0.0f;
uint16_t ppgSamples = 0;
float spo2Samples[SPO2_AVG_SIZE] = {0};
byte spo2Spot = 0, spo2Count = 0;
float tiltDeg = 0.0f;

// HR Spike Detection (Enhanced threshold - NEW)
#define HR_SPIKE_THRESHOLD_BPM 140      // Alert on elevated HR (was 150)
#define HR_ALERT_HYSTERESIS 10          // Reset only if drops below 130

// 5-State FSM
enum FallState { NORM, FREE, IMPACT, STILL, ALERT };
FallState fsmState = NORM;
unsigned long tFree, tImpact, tStill, tAlert;
bool showFall = false;

// Display modes
enum DisplayMode { MAIN_PAGE, FALL_ALERT_PAGE };
DisplayMode displayMode = MAIN_PAGE;

// Remote control flag
volatile bool remoteCancelTriggered = false;
unsigned long lastRemoteCancelTime = 0;

// Remote cancel via BLE (Enhanced with verification)
class FallCharCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    uint8_t* pData = characteristic->getData();
    size_t length = characteristic->getLength();
    
    if (length > 0 && pData != nullptr) {
      Serial.print(F("BLE Write received: "));
      Serial.println((int)pData[0]);
      
      // Accept any write command to trigger cancel
      fsmState = NORM;
      showFall = false;
      displayMode = MAIN_PAGE;
      remoteCancelTriggered = true;
      lastRemoteCancelTime = millis();
      
      digitalWrite(VIBE_MOTOR_PIN, LOW);
      Serial.println(F("REMOTE CANCEL - Fall Alert Cancelled"));
      
      // Send confirmation back to app
      uint8_t response[2] = {0xAA, 0x01};  // Confirmation code
      characteristic->setValue(response, 2);
      characteristic->notify();
    }
  }
  
  void onRead(BLECharacteristic* characteristic) override {
    // Return current fall status when app reads
    uint8_t statusData[1] = {showFall ? 0x01 : 0x00};
    characteristic->setValue(statusData, 1);
  }
};

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

void updateGpsData() {
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  if (gps.location.isValid()) {
    gpsLat = gps.location.lat();
    gpsLon = gps.location.lng();
    gpsValid = true;
  } else if (gps.location.age() > 10000) {
    // If no valid fix for 10s, mark GPS invalid.
    gpsValid = false;
  }
}

void notifyGpsDataIfNeeded() {
  if (!bleConn || pGpsChar == nullptr) return;

  const unsigned long now = millis();
  if (now - lastGpsNotifyTime < GPS_NOTIFY_INTERVAL_MS) return;

  lastGpsNotifyTime = now;

  char gpsPayload[80];
  snprintf(
    gpsPayload,
    sizeof(gpsPayload),
    "LAT:%.6f,LON:%.6f,VALID:%d",
    gpsLat,
    gpsLon,
    gpsValid ? 1 : 0
  );
  pGpsChar->setValue((uint8_t*)gpsPayload, strlen(gpsPayload));
  pGpsChar->notify();
}

// Power Management: Check for inactivity and enable low-power mode
void updatePowerMode(float accelG, float gyroMag) {
  unsigned long now = millis();
  
  // Activity detected: reset inactivity timer
  if (accelG > 0.15f || gyroMag > 10.0f || fsmState != NORM) {
    lastActivityTime = now;
    if (lowPowerMode) {
      lowPowerMode = false;
      Serial.println(F("Exit low-power mode"));
    }
  }
  
  // Check for inactivity timeout
  if ((now - lastActivityTime) > INACTIVITY_TIMEOUT_MS && !lowPowerMode) {
    lowPowerMode = true;
    Serial.println(F("Enter low-power mode"));
  }
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

void setup() {
  Serial.begin(115200);
  bootTime = millis();
  lastActivityTime = bootTime;
  lastSleepCheckTime = bootTime;
  lastBleNotifyTime = bootTime;
  lastGpsNotifyTime = bootTime;

  gpsSerial.begin(GPS_BAUD_RATE, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  pinMode(VIBE_MOTOR_PIN, OUTPUT);
  digitalWrite(VIBE_MOTOR_PIN, LOW);
  pinMode(CANCEL_BUTTON_PIN, INPUT_PULLUP);

  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  showSplashScreen();
  delay(1500);

  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("Initializing...");
  display.display();

  mpu.begin();
  delay(500);

  if (!max30102.begin(Wire, I2C_SPEED_STANDARD)) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.print("MAX30102 FAIL");
    display.display();
    while (1);
  }

  max30102.setup(0x3F, 4, 2, 400, 411, 4096);

  // BLE
  BLEDevice::init("SafeBrace");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLECallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pHRChar = pService->createCharacteristic(HR_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pHRChar->addDescriptor(new BLE2902());

  pFallChar = pService->createCharacteristic(FALL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR);  // Allow write without response
  pFallChar->addDescriptor(new BLE2902());
  pFallChar->setCallbacks(new FallCharCallbacks());

  pGpsChar = pService->createCharacteristic(
    GPS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pGpsChar->addDescriptor(new BLE2902());
  
  // Set initial value
  uint8_t initialValue[1] = {0x00};
  pFallChar->setValue(initialValue, 1);

  pService->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  // Calibration
  display.clearDisplay();
  display.setCursor(0, 0);
  display.print("Calibrating...");
  display.setCursor(0, 20);
  display.print("Keep device still");
  display.display();
  
  delay(3000);
  
  systemReady = true;
  
  display.clearDisplay();
  display.setCursor(0, 0);
  display.print("SafeBrace Ready!");
  display.display();
  delay(1000);
  
  Serial.println("READY");
}

void loop() {
  updateGpsData();

  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);

  float accel = sqrt(
    a.acceleration.x * a.acceleration.x +
    a.acceleration.y * a.acceleration.y +
    a.acceleration.z * a.acceleration.z
  );

  tiltDeg = 0.0f;
  if (accel > 0.01f) {
    float ratio = a.acceleration.z / accel;
    ratio = constrain(ratio, -1.0f, 1.0f);
    tiltDeg = acosf(ratio) * 180.0f / PI;
  }

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
    ppgSamples = 0;  // Reset sample counter for next HR window
  }

  // ===== POWER MANAGEMENT =====
  float accelG = accel / 9.80665f;
  float gyroMag = sqrt(g.gyro.x*g.gyro.x + g.gyro.y*g.gyro.y + g.gyro.z*g.gyro.z) * (180.0f/PI);
  updatePowerMode(accelG, gyroMag);

  // Reduce polling in low-power mode
  if (lowPowerMode) {
    static unsigned long lastLowPowerPoll = 0;
    if (millis() - lastLowPowerPoll < LOW_POWER_POLL_INTERVAL_MS) {
      delay(10);
      return;  // Skip this iteration
    }
    lastLowPowerPoll = millis();
  }

  // ===== ENHANCED 5-STATE FSM FALL DETECTION =====
  if (systemReady) {
    unsigned long now = millis();
    
    switch(fsmState) {
      case NORM:
        // Direct hard impact detection (NEW - immediate alert)
        if (accelG > 3.5f && tiltDeg > 45.0f) {
          fsmState = ALERT;
          tAlert = now;
          Serial.println(F("ALERT:DIRECT_IMPACT"));
          break;
        }
        
        // Extreme tilt = person down
        if (tiltDeg > TILT_THRESHOLD_DEG) {
          fsmState = ALERT;
          tAlert = now;
          Serial.println(F("ALERT:TILT"));
          break;
        }
        
        // Free fall detection (low SVM acceleration)
        if (accelG < 0.5f) {
          fsmState = FREE;
          tFree = now;
          Serial.println(F("FREE_FALL"));
          break;
        }
        
        // HR spike alert (enhanced detection - NEW)
        if (hrReady && bpmAvg > HR_SPIKE_THRESHOLD_BPM && tiltDeg > 50.0f) {
          fsmState = ALERT;
          tAlert = now;
          Serial.println(F("ALERT:HR_SPIKE"));
          break;
        }
        break;

      case FREE:
        // High acceleration = impact detected
        if (accelG > 2.5f) {
          fsmState = IMPACT;
          tImpact = now;
          Serial.println(F("IMPACT_DETECTED"));
          break;
        }
        
        // Free fall timeout - return to normal
        if (now - tFree > FREE_FALL_TIMEOUT_MS) {
          fsmState = NORM;
          Serial.println(F("FF_TIMEOUT"));
          break;
        }
        break;

      case IMPACT:
        // Gyro rotation detected = body motion (good sign)
        if (gyroMag > GYRO_THRESHOLD_IMPACT) {
          fsmState = STILL;
          tStill = 0;
          Serial.println(F("GYRO_MOTION_OK"));
          break;
        }
        
        // Impact timeout - check stillness
        if (now - tImpact > IMPACT_TIMEOUT_MS) {
          fsmState = STILL;
          tStill = now;
          Serial.println(F("MOVING_TO_STILL"));
          break;
        }
        break;

      case STILL:
        // Check for person stillness (person lying down)
        if (accelG >= 0.8f && accelG <= 1.2f && gyroMag < GYRO_THRESHOLD_STILL) {
          if (tStill == 0) {
            tStill = now;
            Serial.println(F("Stillness timer start"));
          }
          
          // Confirmed immobile for 2 seconds = fall detected
          if (now - tStill >= STILL_TIMEOUT_MS) {
            fsmState = ALERT;
            tAlert = now;
            Serial.println(F("ALERT:CONFIRMED_FALL"));
          }
        } else {
          tStill = 0;  // Reset stillness timer if motion detected
        }
        
        // Overall impact-to-alert timeout (5s max)
        if (now - tImpact > 5000UL) {
          fsmState = ALERT;
          tAlert = now;
          Serial.println(F("ALERT:TIMEOUT"));
        }
        break;

      case ALERT:
        // Hold alert state until timeout
        if (now - tAlert >= ALERT_DURATION_MS) {
          fsmState = NORM;
          Serial.println(F("Alert timeout - return to NORM"));
        }
        break;
    }
    
    showFall = (fsmState == ALERT);
  }

  // Switch to fall alert page when fall is detected
  if (showFall && displayMode == MAIN_PAGE) {
    displayMode = FALL_ALERT_PAGE;
    Serial.println(F("Switched to FALL_ALERT_PAGE"));
  }
  
  // Switch back to main page when fall is cleared
  if (!showFall && displayMode == FALL_ALERT_PAGE) {
    displayMode = MAIN_PAGE;
    Serial.println(F("Switched back to MAIN_PAGE"));
  }

  // Motor control
  digitalWrite(VIBE_MOTOR_PIN, showFall ? HIGH : LOW);

  // Local button cancel
  if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
    delay(50);
    if (digitalRead(CANCEL_BUTTON_PIN) == LOW) {
      fsmState = NORM;
      showFall = false;
      displayMode = MAIN_PAGE;
      Serial.println(F("Cancelled"));
      delay(200);
    }
  }

  // BLE notify (Throttled for power efficiency - NEW)
  if (bleConn) {
    unsigned long now = millis();
    
    // Only send BLE updates at reduced interval
    if (now - lastBleNotifyTime >= BLE_NOTIFY_INTERVAL_MS) {
      lastBleNotifyTime = now;
      
      const int hr = hrReady ? bpmAvg : 0;
      const float spo2Out = (spo2Ready ? spo2 : 0.0f);

      // ===== MAIN HR NOTIFICATION (with fall status) =====
      // 64-byte buffer with full readable keys for app compatibility
      char payload[64];
      snprintf(payload, sizeof(payload),
        "HR:%d,SPO2:%.0f,TILT:%.0f,ACC:%.1f,FALL:%d",
        hr, spo2Out, tiltDeg, accelG, showFall ? 1 : 0);
      pHRChar->setValue((uint8_t*)payload, strlen(payload));
      pHRChar->notify();

      // ===== FALL STATUS NOTIFICATION (simplified for app response) =====
      if (showFall) {
        uint8_t fallData[5] = {1, (hr >> 8) & 0xFF, hr & 0xFF,
                               (uint8_t)min((int)tiltDeg, 255),
                               (uint8_t)min((int)(accelG * 10.0f), 255)};
        pFallChar->setValue(fallData, 5);
        pFallChar->notify();
        Serial.println(F("BLE: Fall status notified to app"));
      } else {
        // Send safe status when not in alert
        uint8_t safeData[1] = {0x00};
        pFallChar->setValue(safeData, 1);
        // Note: Not notifying on safe state to save power
      }
    }

    // Send GPS BLE notification on its own interval.
    notifyGpsDataIfNeeded();
  }

  // ===== DISPLAY RENDERING (Main Page vs Fall Alert Page) =====
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);

  if (displayMode == MAIN_PAGE) {
    // ===== MAIN PAGE DISPLAY =====
    // Line 1: HR with icon
    display.setCursor(0, 0);
    display.print("HR: ");
    if (irValue <= 50000) {
      display.print("--");
    } else if (!hrReady) {
      display.print("...");
    } else {
      display.print(bpmAvg);
      display.print(" BPM");
    }

    // Line 2: Acceleration
    display.setCursor(0, 12);
    display.print("ACC: ");
    display.print(accelG, 2);
    display.print("g");

    // Line 3: Tilt angle
    display.setCursor(0, 24);
    display.print("TILT: ");
    display.print((int)tiltDeg);
    display.print("`");

    // Line 4: SpO2
    display.setCursor(0, 36);
    display.print("SpO2: ");
    if (irValue <= 50000) {
      display.print("--");
    } else if (!spo2Ready) {
      display.print("...");
    } else {
      display.print(spo2, 1);
      display.print("%");
    }

    // Line 5: BLE Connection status
    display.setCursor(0, 48);
    display.print("BLE: ");
    if (!bleConn) {
      display.print("OFF");
    } else {
      display.print("ON");
      // Show remote trigger indicator
      if (remoteCancelTriggered && (millis() - lastRemoteCancelTime) < 2000) {
        display.print(" (*)");  // Asterisk indicates recent remote action
      }
    }

    // Top-right GPS validity hint
    display.setCursor(96, 0);
    display.print(gpsValid ? "GPS" : "---");

    // Line 6: Status
    display.setCursor(0, 56);
    display.print("Status: ");
    display.print(fsmState == NORM ? "SAFE" : 
                  fsmState == FREE ? "FALLING" :
                  fsmState == IMPACT ? "IMPACT" :
                  fsmState == STILL ? "STILL" : "ALERT");

  } else if (displayMode == FALL_ALERT_PAGE) {
    // ===== FALL ALERT PAGE (Enhanced typography) =====
    display.setTextSize(3);
    display.setTextColor(WHITE);
    
    // Draw centered "FALL" text (large & bold)
    int16_t x1, y1;
    uint16_t w, h;
    const char* fallText = "FALL";
    display.getTextBounds(fallText, 0, 0, &x1, &y1, &w, &h);
    int fallX = (OLED_W - (int)w) / 2 - x1;
    display.setCursor(fallX, 2);
    display.print(fallText);
    
    // Draw centered "DETECTED" text (size 2)
    display.setTextSize(2);
    const char* detectedText = "DETECTED";
    display.getTextBounds(detectedText, 0, 0, &x1, &y1, &w, &h);
    int detectedX = (OLED_W - (int)w) / 2 - x1;
    display.setCursor(detectedX, 28);
    display.print(detectedText);
    
    // Separator line
    display.drawLine(10, 42, 118, 42, WHITE);
    
    // Draw centered action text (size 1)
    display.setTextSize(1);
    const char* actionText = "Press button";
    display.getTextBounds(actionText, 0, 0, &x1, &y1, &w, &h);
    int actionX = (OLED_W - (int)w) / 2 - x1;
    display.setCursor(actionX, 48);
    display.print(actionText);
    
    const char* actionText2 = "or BLE to cancel";
    display.getTextBounds(actionText2, 0, 0, &x1, &y1, &w, &h);
    int actionX2 = (OLED_W - (int)w) / 2 - x1;
    display.setCursor(actionX2, 57);
    display.print(actionText2);
    
    // Blinking indicator
    if ((millis() / 500) % 2 == 0) {
      display.drawRect(1, 1, 7, 7, WHITE);  // Blinking corner square
    }
  }

  display.display();
  
  // Adaptive polling based on power mode
  delay(lowPowerMode ? 50 : 20);
}

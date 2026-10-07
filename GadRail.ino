#include <Arduino.h>
#include <ESP32Servo.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#define SVC_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID  "6e400002-b5a3-f393-e0a9-e50e24dcca9e"   // اپ می‌نویسد
#define TX_UUID  "6e400003-b5a3-f393-e0a9-e50e24dcca9e"   // ESP32 وضعیت می‌فرستد

// ---------- پایه‌ها ----------
const int TRIG_PIN = 5;
const int ECHO_PIN = 18;
const int LED_GREEN_PIN = 4;
const int LED_YELLOW_PIN = 22;
const int LED_RED_PIN = 23;
const int BUZZER_PIN = 21;
const int SERVO_RIGHT_PIN = 19;
const int SERVO_LEFT_PIN = 13;
const int TOUCH_RIGHT_PIN = 27;
const int TOUCH_LEFT_PIN = 26;
const int BUTTON_PIN = 25;        // دکمه‌ی برگشت: یک پایه به D25، پایه‌ی دیگر به GND

// ---------- تنظیمات ----------
int CW_US = 1000;           // ساعتگرد (جهت رفتن). اگر خلاف ساعتگرد بود 2000 کنید
int CCW_US = 2000;          // جهت مخالف (برگشت). اگر CW_US را عوض کردید این را 1000 کنید
const int STOP_US = 1500;
unsigned long leftDelayMs = 2500;
float gMax = 35, gMin = 29, yMin = 21, rMin = 15;   // مرزهای فاصله (از اپ قابل تغییر)
int speedPct = 100;
bool soundOn = true, appRev = false;
unsigned long lastBeat = 0;
float lastDist = 999;
BLECharacteristic *txChar = nullptr;
volatile bool stopReq = false;   // تأخیر شروع سروو چپ بعد از راست

enum State { IDLE, RUNNING, FINISHED, REVERSING };
State state = IDLE;

Servo servoRight;
Servo servoLeft;

int baseRight = 0;
int baseLeft = 0;
bool rightRunning = false, leftRunning = false;
bool rightDone = false, leftDone = false;
bool rearmWait = false;           // بعد از برگشت، تا دور شدن جسم دوباره شروع نکن
unsigned long rightStartMs = 0;

// ---------- توابع کمکی ----------
float readDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  if (duration == 0) return 999.0;
  return (duration * 0.0343) / 2.0;
}

// لمس = هر تغییر نسبت به حالت عادی
bool touched(int pin, int base) {
  if (digitalRead(pin) == base) return false;
  delay(10);
  return digitalRead(pin) != base;
}

// دکمه با INPUT_PULLUP: فشرده = LOW
bool buttonDown() {
  if (digitalRead(BUTTON_PIN) == LOW) return true;
  delay(30);
  return digitalRead(BUTTON_PIN) == LOW;
}

// بازر همیشه دقیقاً همراه LED قرمز روشن و خاموش می‌شود
void setRed(bool on) {
  digitalWrite(LED_RED_PIN, on);
  digitalWrite(BUZZER_PIN, on && soundOn);
}

void leds(bool g, bool y, bool r) {
  digitalWrite(LED_GREEN_PIN, g);
  digitalWrite(LED_YELLOW_PIN, y);
  setRed(r);
}

void startRight() {
  servoRight.attach(SERVO_RIGHT_PIN, 1000, 2000);
  servoRight.writeMicroseconds(CW_US);
  digitalWrite(BUZZER_PIN, LOW);   // با شروع سروو، بازر خاموش می‌شود
  rightRunning = true;
  rightStartMs = millis();
  Serial.println("Right started");
}

void startLeft() {
  servoLeft.attach(SERVO_LEFT_PIN, 1000, 2000);
  servoLeft.writeMicroseconds(CW_US);
  leftRunning = true;
  Serial.println("Left started");
}

void stopRight() {
  servoRight.writeMicroseconds(STOP_US);
  servoRight.detach();
  rightRunning = false;
  rightDone = true;
  Serial.println("Right stopped");
}

void stopLeft() {
  servoLeft.writeMicroseconds(STOP_US);
  servoLeft.detach();
  leftRunning = false;
  leftDone = true;
  Serial.println("Left stopped");
}

void enterReverse() {
  if (!servoRight.attached()) servoRight.attach(SERVO_RIGHT_PIN, 1000, 2000);
  if (!servoLeft.attached())  servoLeft.attach(SERVO_LEFT_PIN, 1000, 2000);
  servoRight.writeMicroseconds(CCW_US);
  servoLeft.writeMicroseconds(CCW_US);
  rightRunning = leftRunning = false;
  leds(false, false, false);
  state = REVERSING;
  Serial.println("Reversing");
}

void leaveReverse() {
  servoRight.writeMicroseconds(STOP_US);
  servoLeft.writeMicroseconds(STOP_US);
  servoRight.detach();
  servoLeft.detach();
  rightDone = leftDone = false;
  rearmWait = true;
  state = IDLE;
  Serial.println("Back to initial state");
}

// ---------- بلوتوث ----------
void doStop() {
  appRev = false;
  if (servoRight.attached()) { servoRight.writeMicroseconds(STOP_US); servoRight.detach(); }
  if (servoLeft.attached())  { servoLeft.writeMicroseconds(STOP_US);  servoLeft.detach(); }
  rightRunning = leftRunning = false;
  rightDone = leftDone = true;
  leds(false, false, false);
  state = FINISHED;
}

class SrvCb : public BLEServerCallbacks {
  void onDisconnect(BLEServer* s) { appRev = false; s->getAdvertising()->start(); }
};

class RxCb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    String s = String(c->getValue().c_str());
    s.trim();
    if (s.startsWith("REV")) { appRev = s.endsWith("1"); lastBeat = millis(); }
    else if (s == "STOP") stopReq = true;
    else if (s.startsWith("SET")) {
      float a, b, c2, d; int dl, sp, sn;
      if (sscanf(s.c_str(), "SET %f %f %f %f %d %d %d", &a, &b, &c2, &d, &dl, &sp, &sn) == 7) {
        gMax = a; gMin = b; yMin = c2; rMin = d;
        leftDelayMs = constrain(dl, 500, 6000);
        speedPct = constrain(sp, 20, 100);
        soundOn = (sn == 1);
        CW_US = 1500 - 5 * speedPct;
        CCW_US = 3000 - CW_US;
      }
    }
  }
};

void bleInit() {
  BLEDevice::init("GadRail");
  BLEDevice::setMTU(247);
  BLEServer* srv = BLEDevice::createServer();
  srv->setCallbacks(new SrvCb());
  BLEService* sv = srv->createService(SVC_UUID);
  txChar = sv->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());
  BLECharacteristic* rx = sv->createCharacteristic(RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCb());
  sv->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SVC_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void bleTick() {
  if (stopReq) { stopReq = false; doStop(); }
  static unsigned long t = 0;
  if (txChar && millis() - t > 300) {
    t = millis();
    char b[100];
    snprintf(b, sizeof(b), "%.1f,%d,%d,%d,%d,%d,%d,%.0f,%.0f,%.0f,%.0f,%lu,%d", lastDist, (int)state,
             rightRunning, leftRunning, rightDone, leftDone, soundOn, gMax, gMin, yMin, rMin, leftDelayMs, speedPct);
    txChar->setValue((uint8_t*)b, strlen(b));
    txChar->notify();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);
  pinMode(LED_YELLOW_PIN, OUTPUT);
  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(TOUCH_RIGHT_PIN, INPUT);
  pinMode(TOUCH_LEFT_PIN, INPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  delay(300);                       // تاچ‌ها را لمس نکنید
  baseRight = digitalRead(TOUCH_RIGHT_PIN);
  baseLeft = digitalRead(TOUCH_LEFT_PIN);
  Serial.printf("Base R=%d L=%d\n", baseRight, baseLeft);

  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  servoRight.setPeriodHertz(50);
  servoLeft.setPeriodHertz(50);

  bleInit();
  leds(false, false, false);
}

void loop() {
  // دکمه‌ی برگشت در همه‌ی حالت‌ها کار می‌کند (حتی وقتی سرووها خاموش‌اند)
  bleTick();
  if (appRev && millis() - lastBeat > 800) appRev = false;   // ایمنی: قطع ارتباط = توقف
  if (state != REVERSING && (appRev || buttonDown())) enterReverse();

  switch (state) {

    case IDLE: {
      float d = readDistance();
      bool valid = (d > 0.0 && d < 900.0);
      Serial.println(d);
      lastDist = d;
      if (rearmWait && (!valid || d >= rMin)) rearmWait = false;

      if (!valid || d > gMax)  leds(false, false, false);
      else if (d >= gMin)      leds(true,  false, false);  // 29 تا 35 سبز
      else if (d >= yMin)      leds(false, true,  false);  // 21 تا 28 زرد
      else if (d >= rMin)      leds(false, false, true);   // 15 تا 20 قرمز + بازر
      else {                                               // 14 و کمتر
        leds(false, false, true);
        if (!rearmWait) {
          startRight();
          state = RUNNING;
        }
      }
      delay(60);
      break;
    }

    case RUNNING:
      // سروو چپ دقیقاً 2.5 ثانیه بعد از راست شروع می‌شود
      if (!leftRunning && !leftDone && millis() - rightStartMs >= leftDelayMs) startLeft();

      // هر سروو با تاچ خودش برای همیشه متوقف می‌شود
      if (rightRunning && touched(TOUCH_RIGHT_PIN, baseRight)) stopRight();
      if (leftRunning && touched(TOUCH_LEFT_PIN, baseLeft)) stopLeft();

      if (rightDone && leftDone) {
        leds(false, false, false);  // قرمز و بازر با هم خاموش
        state = FINISHED;
      }
      delay(5);
      break;

    case FINISHED:
      delay(20);                    // منتظر دکمه‌ی برگشت
      break;

    case REVERSING:
      // تا وقتی دکمه نگه داشته شده، برعکس می‌چرخد (تاچ‌ها نادیده گرفته می‌شوند)
      if (!appRev && !buttonDown()) leaveReverse();
      delay(10);
      break;
  }
}

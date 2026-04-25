# Automatic Meal Detection via Heart Rate + Contextual Signals

**Status:** Future scope — researched & planned, not yet implemented
**Created:** April 2026
**Estimated effort:** 6-8 days

---

## Overview

Detect when the user is eating without manual input by monitoring heart rate from Apple Watch during user-defined meal windows. When a sustained postprandial heart rate increase is detected, prompt the user with a notification to log their meal.

---

## Research Summary

### Heart Rate as a Meal Biomarker

**Heart rate is a reliable biomarker for eating.** Research shows:

- Heart rate increases **6-21%** after eating, observed in **95%+ of studies** ([Source: JAMIA hemodynamic review](https://www.i-jmr.org/2024/1/e52167/PDF))
- The increase begins **5-15 minutes** after the first bite and lasts **1-3 hours** (diet-induced thermogenesis)
- Cardiac output increases 9-100%, stroke volume 18-41% ([Source: postprandial cardiac study](https://pubmed.ncbi.nlm.nih.gov/1877363/))
- High-protein meals cause a **2x larger** thermogenic response than high-carb meals ([Source: PMC diet thermogenesis](https://pmc.ncbi.nlm.nih.gov/articles/PMC524030/))
- One study achieved **98.6% accuracy** detecting eating events using consumer smartwatch heart rate data alone

**The key signal pattern:**
```
[Resting HR baseline] --> [Sustained 6-21% increase for 15+ minutes] --> [Gradual return over 1-3 hours]
```
This is distinct from exercise (higher HR + movement) and stress (higher HRV variability).

### Accelerometer-Based Eating Gesture Detection

A separate approach uses wrist-worn accelerometer data to detect hand-to-mouth eating gestures:

- **F1 score: 87.3%, Precision: 80%, Recall: 96%** using random forest classifier on smartwatch accelerometer data ([Source: PMC7775824](https://pmc.ncbi.nlm.nih.gov/articles/PMC7775824/))
- Lunch detection: **99%**, Dinner: **98%**, Breakfast: **89.8%**
- False positive rate: only **0.7%**
- Tested on 28 students over 3 weeks — one of the longest real-world studies
- Uses 25 Hz accelerometer sampling with structural ECDF features
- 15-minute detection windows with 20-gesture threshold

**Key limitation for Apple Watch:** Apple doesn't expose raw 25 Hz accelerometer data via HealthKit — this approach requires a companion watchOS app using CoreMotion. This is a Phase 2 enhancement after the heart rate MVP.

### Multimodal Signal Comparison

| Signal | Detects | Accuracy | Latency | Apple Watch Support |
|--------|---------|----------|---------|:---:|
| Heart rate elevation | Meal digestion (thermogenesis) | 98.6% | 10-15 min after eating | Yes (HealthKit) |
| Accelerometer gestures | Hand-to-mouth eating motion | 87-99% | Real-time during eating | Requires watchOS companion app |
| CGM glucose spike | Carbohydrate absorption | ~95% | 15-25 min after eating | No (requires Dexcom/Libre) |
| Combined HR + accelerometer | Both physiological + behavioral | Expected >99% | Real-time to 15 min | Partial |

---

## What Apple Watch Provides

- **Background heart rate readings every 2-10 minutes** (activity-dependent, not configurable) ([Source: Apple Support](https://support.apple.com/en-us/120277))
- **During workouts: continuous readings** (not useful for meal detection)
- **HRV (SDNN)** available as daily summaries
- **Resting heart rate** calculated daily
- **Steps + active energy** (already integrated in the app)

## What HealthKit Allows

- **`HKObserverQuery`** -- long-running query that fires when new heart rate samples arrive, even in background ([Source: Apple Docs](https://developer.apple.com/documentation/healthkit/hkobserverquery))
- **`enableBackgroundDelivery(for:frequency:)`** -- wakes your app when new data arrives; frequency: `.immediate`, `.hourly`, `.daily` ([Source: Apple Docs](https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery(for:frequency:withCompletion:)))
- **`HKAnchoredObjectQuery`** -- efficient delta queries (only new samples since last check)
- **Entitlement required:** `com.apple.developer.healthkit.background-delivery`
- **Privacy:** Heart rate is a separate permission from steps/calories

---

## How It Works (User-Facing)

1. **User sets meal windows** in Settings (e.g., Breakfast 7-9 AM, Lunch 12-2 PM, Dinner 6-9 PM)
2. **During meal windows**, the app monitors heart rate in the background via HealthKit
3. **When a sustained HR increase is detected** (>=8% above recent baseline for >=10 minutes, with low/no movement), the app sends a local notification: *"Looks like you might be having lunch -- tap to log what you're eating"*
4. **Tapping the notification** opens the app to the food input screen
5. **The app learns** -- if the user dismisses 3 notifications in a row for a meal window, it lowers sensitivity for that window

---

## Detection Algorithm (MVP)

```
INPUTS:
  - HR samples from HealthKit (background delivery)
  - Step count from HealthKit (to filter out exercise)
  - User-defined meal windows
  - Personal resting HR baseline (rolling 7-day average)

ALGORITHM:
  1. Only evaluate during active meal windows
  2. Compute rolling baseline: median HR from the 30 minutes BEFORE the meal window started
  3. When a new HR sample arrives:
     a. If steps in last 5 min > 100 --> skip (user is walking/exercising)
     b. If HR > baseline * 1.08 (8% increase):
        - Start a "potential meal" timer
     c. If HR stays elevated for >= 10 consecutive minutes (2-5 samples):
        - Trigger notification (if not already sent for this window)
     d. If HR drops back to baseline before 10 min --> reset timer

FALSE POSITIVE FILTERS:
  - High step count --> exercise, not eating
  - Already logged food in last 30 min --> don't re-prompt
  - Already sent notification for this meal window --> don't repeat
  - User dismissed last 3 notifications --> suppress for this window
```

---

## Implementation Plan

### Phase 1: Heart Rate Data Access (Foundation) -- 1-2 days

| File | Change |
|------|--------|
| `HealthKitService.swift` | Add heart rate read permission, background delivery, HR query methods |
| `Info.plist` | Add `com.apple.developer.healthkit.background-delivery` entitlement |
| `Food App.entitlements` | Add HealthKit background delivery capability |

- Add `HKQuantityType(.heartRate)` to read permissions
- Add `enableBackgroundDelivery(for: heartRateType, frequency: .immediate)`
- Add `HKAnchoredObjectQuery` for efficient heart rate reads
- Add methods: `fetchRecentHeartRateSamples(last:)` and `observeHeartRate(handler:)`

### Phase 2: Meal Window Settings -- 1 day

| File | Change |
|------|--------|
| `MealWindowSettings.swift` | **CREATE** -- model + persistence for meal windows |
| `MealWindowSettingsView.swift` | **CREATE** -- SwiftUI settings screen with time pickers |
| `AppStore.swift` | Add meal detection enable/disable toggle |

```swift
struct MealWindow: Codable, Identifiable {
    let id: UUID
    var name: String          // "Breakfast", "Lunch", "Dinner", "Snack"
    var startTime: DateComponents  // hour + minute
    var endTime: DateComponents
    var isEnabled: Bool
    var suppressedUntil: Date?     // suppression from repeated dismissals
}
```

### Phase 3: Detection Engine -- 2-3 days

| File | Change |
|------|--------|
| `MealDetectionService.swift` | **CREATE** -- core detection logic, runs in background |

### Phase 4: Local Notifications -- 1 day

| File | Change |
|------|--------|
| `AppNotifications.swift` | Add meal detection notification category + actions |
| `MealDetectionService.swift` | Send local notification with "Log Food" and "Dismiss" actions |

### Phase 5: Integration + Polish -- 1 day

| File | Change |
|------|--------|
| `MainLoggingShellView.swift` | Handle notification deep link to open food input |
| `ContentView.swift` | Route meal detection notification taps |
| `AppStore.swift` | Coordinate meal detection service lifecycle |

### Phase 6 (Future): Accelerometer Gesture Detection

Requires building a **companion watchOS app** using CoreMotion:

- Access raw accelerometer at 25+ Hz on Apple Watch
- Run random forest classifier on-device to detect hand-to-mouth gestures
- Send detected eating episodes to the iPhone app via WatchConnectivity
- Combine with heart rate signal for >99% accuracy
- Reference: [Real-time eating detection study (PMC7775824)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7775824/)

This is a larger engineering effort (watchOS app + ML model) but achieves the highest detection accuracy, especially for snacking which heart rate alone may miss.

---

## Apple Health Permissions Required

| Permission | Type | Already Have | Purpose |
|------------|------|:---:|---------|
| Step Count | Read | Yes | Filter out exercise |
| Active Energy | Read | Yes | Additional exercise filter |
| Heart Rate | Read | **No** | Core meal detection signal |

---

## Limitations & Honest Assessment

### What will work well
- Detecting proper meals (lunch, dinner) -- strong HR signal
- Filtering out exercise -- step count makes this reliable
- User-defined windows dramatically reduce false positives

### What will be tricky
- **Snacking** -- small snacks may not produce enough HR elevation
- **Caffeine/stress** -- coffee and anxiety both raise HR
- **Variable sampling** -- Apple Watch reads every 2-10 min, so minimum detection latency is ~10-15 min
- **Requires Apple Watch** -- no HR data without it
- **Calibration period** -- needs 3-7 days of baseline HR data

---

## Verification Plan

1. Unit test detection algorithm with synthetic HR data
2. Simulator testing with mock HealthKit data
3. Device testing with Apple Watch: eat lunch --> verify notification within 15-20 min
4. Walk during meal window --> verify NO notification (step filter)
5. Sit quietly without eating --> verify NO notification (baseline HR)
6. Dismiss 3 notifications --> verify window gets suppressed

---

## Research Sources

- [Multiple physiological parameters for dietary monitoring (BMC Nutrition 2025)](https://link.springer.com/article/10.1186/s40795-025-01168-1)
- [Postprandial cardiac output study](https://pubmed.ncbi.nlm.nih.gov/1877363/)
- [Diet induced thermogenesis (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC524030/)
- [Automated meal detection from CGM (JAMIA)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6857509/)
- [Wearable eating detection scoping review (npj Digital Medicine)](https://www.nature.com/articles/s41746-020-0246-2)
- [Real-time eating detection via smartwatch accelerometer (PMC7775824)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7775824/)
- [Smartwatch eating detection ML (MDPI Sensors)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7963188/)
- [Apple Watch heart rate monitoring (Apple Support)](https://support.apple.com/en-us/120277)
- [HKObserverQuery (Apple Docs)](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- [enableBackgroundDelivery (Apple Docs)](https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery(for:frequency:withCompletion:))
- [HealthKit background delivery entitlement (Apple Docs)](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery)

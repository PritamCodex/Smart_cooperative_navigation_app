# Critical Fixes - Round 2 (v1.1.1)

**Build Date**: 2025-11-23 23:25:00 +05:30  
**APK Size**: 44.3 MB  
**APK Location**: `build/app/outputs/flutter-apk/app-release.apk`

## 🚨 **Issues Addressed**

### 1. **"No Alert" Even When Nearby**
**Root Cause**: The "Low Confidence" logic was too aggressive. If GPS accuracy was >20m (common indoors), it forced ALL alerts to GREEN, ignoring RSSI data.
**Fix**: 
- Modified `collision_engine.dart` to **TRUST RSSI**.
- If RSSI fusion indicates distance < 10m, the alert is ALLOWED even if GPS accuracy is poor.
- Only suppresses alerts if BOTH GPS is poor AND RSSI is unavailable/far.

### 2. **"Radar Dot Inaccurate"**
**Root Cause**: The heading (direction) logic was flawed. It was overwriting accurate GPS heading with noisy magnetometer data, or failing to use GPS heading when moving.
**Fix**:
- Implemented **Hybrid Heading** in `sensor_service.dart`.
- **Moving (>0.5 m/s)**: Uses GPS Heading (very accurate).
- **Stationary (<0.5 m/s)**: Uses Magnetometer Heading (fallback).
- This ensures the radar dot points correctly when walking/driving.

## 📦 **Installation**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 🧪 **Verification**

1. **Indoor Test**:
   - Even with poor GPS, bringing devices close (<2m) SHOULD trigger a Red/Critical alert now (thanks to RSSI trust).
   
2. **Movement Test**:
   - Walk with the device. The radar dot should align with your movement direction (thanks to GPS heading).

3. **Stationary Test**:
   - Stop moving. The heading should stabilize (using magnetometer).

---
**This build specifically targets the "Nothing Changed" feedback by fixing the logic that was silently suppressing alerts.**

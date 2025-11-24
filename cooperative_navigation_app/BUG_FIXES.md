# Critical Bug Fixes - Cooperative Navigation Safety App

## Issues Identified & Solutions

### 1. **Peer Discovery Issues (Android 12)**
**Problem**: Single-shot discovery with no retry mechanism
**Solution**: Add automatic retry with exponential backoff

### 2. **Warning System Glitching**
**Problem**: Stream subscriptions not resilient to errors
**Solution**: Add error handlers and automatic stream reconnection

### 3. **Inaccurate Distance Measurements**
**Problem**: 
- Using raw GPS without validation
- EKF not properly initialized before use
- No RSSI fusion in collision engine
**Solution**: 
- Add GPS validation
- Check EKF initialization status
- Integrate RSSI distance into collision calculations

### 4. **Slow/Non-Starting Discovery (30s delay)**
**Problem**: 
- No automatic restart after failures
- No periodic health checks
- Nearby Connections lifecycle issues
**Solution**: Add watchdog timer and automatic restart

### 5. **Alert Persistence >10m**
**Problem**: Stale beacon timeout (5s) too long
**Solution**: Reduce to 2 seconds

### 6. **Distance Showing Even After Separation**
**Problem**: Alerts based on last known distance, not removing stale alerts
**Solution**: Aggressive beacon cleanup and distance-based alert filtering

## Implementation Steps

1. nearby_service.dart - Add retry logic and watchdog
2. app_providers.dart - Fix stream error handling and reduce stale timeout
3. collision_engine.dart - Add distance validation and RSSI integration
4. sensor_service.dart - Add GPS validation

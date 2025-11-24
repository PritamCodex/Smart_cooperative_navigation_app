# 🏗️ Strong/Weak Node Architecture - Implementation Guide

This document explains the complete Strong/Weak Node architecture that has been implemented in the Cooperative Navigation Safety App.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Components](#components)
4. [Data Flow](#data-flow)
5. [Integration Guide](#integration-guide)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The Strong/Weak Node architecture is a **hierarchical clustering system** where:

- **Strong Nodes (Leaders)**: Powerful devices that perform sensor fusion, collision detection, and alert generation for the entire cluster
- **Weak Nodes (Followers)**: Lower-capability devices that act as "smart sensors," sending raw data to the leader and displaying alerts
- **Reduced Mode**: Fallback mode when no leader is available, using RSSI-only ranging

### Key Benefits

✅ **Battery Efficiency**: Weak nodes consume minimal power (no EKF, no collision detection)  
✅ **Scalability**: Leader handles N devices with O(N²) complexity centralized  
✅ **Accuracy**: Strong nodes use premium GNSS chipsets for better fusion  
✅ **Robustness**: Automatic leader election, re-election on failure  
✅ **Graceful Degradation**: Reduced mode ensures continued operation

---

## Architecture

### State Machine

```
┌─────────────┐
│ DISCOVERING │ (Initial scan for peers)
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│ CAPABILITY_EXCHANGE  │ (Send/receive capability scores)
└──────┬───────────────┘
       │
   ┌───┴────┐
   │ Score  │
   │ ≥ 70?  │
   └───┬────┘
       │
  ┌────┴────┐
  │         │
 YES        NO
  │         │
  ▼         ▼
┌────────┐  ┌──────────┐
│LEADER  │  │ FOLLOWER │
│CANDIDATE│  └──────────┘
└────┬───┘       │
     │           │
  Win │          │ Receive
  Election       │ Alerts
     │           │
     ▼           │
┌────────┐       │
│ LEADER │◄──────┘
└────┬───┘
     │
     │ Leader Lost?
     ▼
┌──────────────┐
│ REDUCED_MODE │ (RSSI-only fallback)
└──────────────┘
```

### Capability Scoring

```
Total Score = OS + GNSS + CPU + Battery + Thermal + Blacklist

OS Score (Max 50):
  Android 14+: +50
  Android 13:  +30
  Android 12:  +10

GNSS Score (Max 30):
  Dual-band L1+L5: +30
  Single-band:     +0

GNSS Accuracy (Max 20):
  <10m:  +20
  10-20m: +10
  >20m:   +0

CPU Tier (Max 20):
  High (8+ cores, flagship): +20
  Mid (6+ cores):            +10
  Low:                       +0

Battery Penalty:
  <15%:   -30
  15-30%: -10

Thermal Throttling: -20
Device Blacklist:   -50

Threshold: score ≥ 70 → STRONG_NODE
```

---

## Components

### 1. **Capability Detector**
**File**: `lib/src/services/capability_detector.dart`

Assesses device capability and computes a score (0-150).

```dart
final detector = CapabilityDetector();
final capability = await detector.assessCapability();
print('Score: ${capability.capabilityScore}');
// Output: Score: 120 (Strong Node)
```

### 2. **Leader Election Engine**
**File**: `lib/src/services/leader_election_engine.dart`

Manages cluster leadership using term-based elections.

**Key Features:**
- Heartbeat every 500ms
- 3-second timeout detection
- Split-brain resolution
- Challenge window (2 seconds)

```dart
final election = LeaderElectionEngine();
election.initialize(deviceId, capabilityScore);

election.stateStream.listen((state) {
  print('Role: ${state.myRole}, Leader: ${state.currentLeader}');
});
```

### 3. **Strong Node Controller**
**File**: `lib/src/services/strong_node_controller.dart`

Performs multi-device sensor fusion and collision detection.

**Responsibilities:**
- Collect sensor packets from all peers
- Run Extended Kalman Filter per device
- Compute N×N collision matrix
- Generate LeaderAlertPackets at 10-20 Hz

**EKF State Vector:**
```
x = [lat, lon, vx, vy]ᵀ
```

**Collision Detection:**
- Haversine distance calculation
- RSSI fusion for close range (<15m)
- Time-to-collision (TTC) computation
- Alert levels: GREEN, YELLOW, ORANGE, RED

### 4. **Weak Node Controller**
**File**: `lib/src/services/weak_node_controller.dart`

Transmits sensor data and displays alerts.

**Responsibilities:**
- Send SensorPackets at adaptive rate (2-10 Hz)
- Monitor leader heartbeat
- Display received alerts
- Enter reduced mode on leader loss

**Adaptive Transmission:**
```
Speed > 2 m/s:    10 Hz (moving)
0.5-2 m/s:        5 Hz (slow)
Speed < 0.5 m/s:  2 Hz (stationary)
```

### 5. **Cluster Orchestrator**
**File**: `lib/src/services/cluster_orchestrator.dart`

Coordinates all components and manages role transitions.

**Integration Points:**
```dart
// Initialize
await orchestrator.initialize(myDeviceId);

// Route incoming packets
orchestrator.handleIncomingPacket(packet);

// Feed sensor data
orchestrator.updateSensorData(gnss: gnss, imu: imu);

// Listen to events
orchestrator.roleChangeStream.listen((event) { ... });
orchestrator.packetOutStream.listen((packet) { ... });
```

---

## Data Flow

### Strong Node (Leader) Flow

```
┌──────────────┐
│ Own Sensors  │ → SensorPacket
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Sensor       │ ← SensorPacket (from peers)
│ Buffer       │
│ (50 samples) │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ EKF Update   │ (Per device, 10 Hz)
│ (4×4 matrix) │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Collision    │ (N×N pairs)
│ Detection    │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Alert        │ → Broadcast to all peers
│ Generation   │    (10-20 Hz)
└──────────────┘
```

### Weak Node (Follower) Flow

```
┌──────────────┐
│ Own Sensors  │ → SensorPacket
└──────┬───────┘           │
       │                    ▼
       │              ┌──────────────┐
       │              │ Send to      │
       │              │ Leader       │
       │              └──────────────┘
       │
       ▼
┌──────────────┐
│ Leader       │ ← HeartbeatPacket
│ Watchdog     │
└──────┬───────┘
       │
       │ Timeout? → REDUCED_MODE
       │
       ▼
┌──────────────┐
│ Receive      │ ← LeaderAlertPacket
│ Alerts       │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Update UI    │ (Display radar, alerts)
└──────────────┘
```

---

## Integration Guide

### Step 1: Initialize Orchestrator

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/services/cluster_orchestrator.dart';

class MyApp extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late ClusterOrchestrator orchestrator;
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    orchestrator = ref.read(clusterOrchestratorProvider);
    await orchestrator.initialize('my-device-id');
  }
}
```

### Step 2: Wire Nearby Service

```dart
import 'dart:convert';
import 'package:cooperative_navigation_safety/src/core/models/cluster_packet.dart';

// Send outgoing packets
orchestrator.packetOutStream.listen((packet) {
  final json = jsonEncode(packet.toJson());
  nearbyService.sendToAll(utf8.encode(json));
});

// Receive incoming packets
void onNearbyPayloadReceived(Uint8List bytes) {
  final json = jsonDecode(utf8.decode(bytes));
  final packet = ClusterPacket.fromJson(json);
  orchestrator.handleIncomingPacket(packet);
}
```

### Step 3: Wire Sensor Service

```dart
// Location updates
void onLocationUpdate(LocationData location) {
  final gnss = GnssData(
    lat: location.latitude!,
    lon: location.longitude!,
    altitude: location.altitude ?? 0,
    accuracy: location.accuracy ?? 999,
    speed: location.speed ?? 0,
    speedAccuracy: location.speedAccuracy ?? 0,
    bearing: location.heading ?? 0,
    bearingAccuracy: location.headingAccuracy ?? 0,
    gnssTimestamp: location.time?.millisecondsSinceEpoch ?? 0,
  );
  
  orchestrator.updateSensorData(gnss: gnss);
}

// IMU updates
void onIMUUpdate(AccelerometerEvent accel, GyroscopeEvent gyro, MagnetometerEvent mag) {
  final imu = ImuData(
    accel: [accel.x, accel.y, accel.z],
    gyro: [gyro.x, gyro.y, gyro.z],
    mag: [mag.x, mag.y, mag.z],
    imuTimestamp: DateTime.now().millisecondsSinceEpoch,
  );
  
  orchestrator.updateSensorData(imu: imu);
}
```

### Step 4: Handle Role Changes

```dart
orchestrator.roleChangeStream.listen((event) {
  switch (event.newRole) {
    case ElectionState.LEADER:
      print('I am now the leader!');
      // Update UI: Show "Leader" badge
      break;
      
    case ElectionState.FOLLOWER:
      print('Following leader: ${event.leaderId}');
      // Update UI: Show "Connected" status
      break;
      
    case ElectionState.REDUCED_MODE:
      print('No leader - reduced accuracy mode');
      // Update UI: Show warning banner
      break;
  }
});
```

---

## Testing

### Unit Test Example

```dart
void main() {
  group('CapabilityDetector', () {
    test('should score Android 14 device as strong', () async {
      final detector = CapabilityDetector();
      final capability = await detector.assessCapability();
      
      expect(capability.capabilityScore, greaterThanOrEqualTo(70));
      expect(detector.isStrongNode(capability.capabilityScore), true);
    });
  });
  
  group('LeaderElection', () {
    test('highest score wins election', () {
      final election = LeaderElectionEngine();
      election.initialize('device-A', 120);
      
      final peerB = CapabilityPacket(
        deviceId: 'device-B',
        score: 80,
        isStrongNode: true,
        currentRole: 'CANDIDATE',
        capability: ...,
      );
      
      election.onCapabilityPacket(peerB);
      
      expect(election.state.currentLeader, 'device-A');
      expect(election.state.myRole, ElectionState.LEADER);
    });
  });
}
```

### Integration Test Scenario

**3-Device Setup:**
- Phone A: Android 15, Flagship (score: 120)
- Phone B: Android 14, Mid-range (score: 70)
- Phone C: Android 13, Budget (score: 30)

**Expected Behavior:**
1. All broadcast CapabilityPackets
2. Phone A elected as leader
3. Phones B & C become followers
4. Phone A sends HeartbeatPackets every 500ms
5. Phone A receives SensorPackets from B & C
6. Phone A broadcasts LeaderAlertPackets
7. Phones B & C display alerts

**Kill Phone A:**
1. Phones B & C detect heartbeat timeout (3s)
2. Phone B re-elected as leader
3. Phone C follows Phone B
4. System recovers in <5 seconds

---

## Troubleshooting

### Issue: "No strong nodes available"
**Symptom**: All devices enter REDUCED_MODE  
**Cause**: All devices score < 70  
**Solution**: Check Android version, ensure at least one Android 14+ device

### Issue: "Split-brain detected"
**Symptom**: Multiple leaders exist  
**Cause**: Network partition or delayed heartbeat  
**Solution**: System auto-resolves using score comparison, lower score steps down

### Issue: "Leader keeps changing"
**Symptom**: Frequent re-elections  
**Cause**: Unstable network or thermal throttling  
**Solution**: Check proximity, ensure devices aren't overheating

### Issue: "Weak node not receiving alerts"
**Symptom**: Follower UI not updating  
**Cause**: Packet loss or parsing error  
**Solution**: Check nearby connection quality, verify JSON parsing

### Issue: "High battery drain on follower"
**Symptom**: Weak node consuming too much power  
**Cause**: Transmission rate too high  
**Solution**: Verify adaptive transmission is working (check speed-based intervals)

---

## Performance Characteristics

### CPU Usage
- **Strong Node (Leader)**: ~50% single core (acceptable for flagship)
- **Weak Node (Follower)**: ~5% single core (minimal)

### Memory Usage
- **Sensor Buffers**: ~10 KB per device (50 packets × 200 bytes)
- **EKF States**: ~500 bytes per device
- **Total for 10 devices**: ~105 KB (negligible)

### Network Bandwidth
- **SensorPacket**: ~300 bytes @ 5-10 Hz = 1.5-3 KB/s per follower
- **LeaderAlertPacket**: ~500 bytes @ 10-20 Hz = 5-10 KB/s broadcast
- **Total for 5-device cluster**: ~20 KB/s (very low)

### Latency Budget
| Stage | Time |
|-------|------|
| Packet receive | 10 ms |
| Deserialization | 5 ms |
| EKF update | 3 ms |
| Collision detection | 10 ms |
| Alert generation | 3 ms |
| Packet send | 10 ms |
| **Total** | **41 ms** |

**Target**: 100 ms (10 Hz) → **59 ms headroom** ✅

---

## References

- **Architecture Spec**: `ARCHITECTURE_v2.md`
- **Implementation Status**: `STRONG_WEAK_IMPLEMENTATION_STATUS.md`
- **Integration Example**: `lib/src/examples/cluster_integration_example.dart`
- **Packet Schemas**: `lib/src/core/models/cluster_packet.dart`

---

**Status**: ✅ **Fully Implemented and Ready for Integration**  
**Last Updated**: 2025-11-24

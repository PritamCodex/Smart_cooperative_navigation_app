# Strong-Node / Weak-Node Implementation Guide

This guide provides the step-by-step implementation details for the new architecture.

## 1. Core Logic: Leader Election

**File:** `lib/src/services/cluster_manager.dart`

The `ClusterManager` is the brain of the operation. It decides the role of the device.

### State Machine
1.  **Initialization**: Assess capability -> Broadcast `CapabilityPacket`.
2.  **Discovery**: Listen for peers.
3.  **Election**:
    - Wait 2 seconds after first connection to gather candidates.
    - Sort candidates by Score (Desc) -> DeviceID (Asc).
    - If `myID == topCandidateID` -> Become **LEADER**.
    - Else -> Become **FOLLOWER**.
4.  **Monitoring**:
    - If Leader disconnects -> Re-run election immediately.
    - If new Strong Node joins -> Re-run election (preemption).

## 2. Strong Node Algorithm (Leader)

**File:** `lib/src/services/fusion/centralized_fusion_engine.dart`

1.  **Input**: Receive `SensorPacket` from all followers.
2.  **Fusion**:
    - Update `DeviceState` for each peer.
    - (Optional) Run EKF Predict/Update for each peer state to smooth jitter.
3.  **Collision Check**:
    - Calculate distance matrix (Leader <-> Peer, Peer <-> Peer).
    - Check against thresholds (Warning: 10m, Danger: 5m).
4.  **Broadcast**:
    - Construct `LeaderAlertPacket`.
    - Broadcast to ALL peers via `NearbyService`.
    - Frequency: 10Hz (100ms).

## 3. Weak Node Algorithm (Follower)

**File:** `lib/src/ui/screens/main_screen.dart` (Logic layer)

1.  **Input**: Read local sensors (GNSS, IMU).
2.  **Transmit**:
    - Construct `SensorPacket`.
    - Send to Leader via `NearbyService`.
    - Frequency: 10Hz.
3.  **Receive**:
    - Listen for `LeaderAlertPacket`.
4.  **Display**:
    - Update UI with `packet.globalState` (Green/Yellow/Red).
    - Update Radar with `packet.peers` positions.
    - **NO LOCAL COMPUTATION**.

## 4. Fallback Mode (Reduced Mode)

If `ClusterManager` reports `ClusterRole.REDUCED` (No Strong Nodes):
1.  **Switch Logic**:
    - Enable local `LegacyCollisionEngine` (simplified).
    - Use Raw GPS distance.
    - Use RSSI ranging if GPS accuracy > 20m.
2.  **UI**: Show "Reduced Accuracy Mode" banner.

---

## 5. Backward Compatibility Strategy

To support Android 13 and below:
1.  **Capability Check**: The scoring algorithm naturally marks them as **WEAK**.
2.  **Performance**:
    - Disable EKF on these devices.
    - Disable high-frequency UI updates (cap at 30fps).
    - Use `flutter_foreground_task` to keep connection alive.
3.  **Graceful Degradation**:
    - If a Weak Node cannot send data fast enough, the Leader extrapolates position (Dead Reckoning).

---

## 6. Example Scenario: 3 Devices

**Setup**:
- **Phone A** (Android 15, Score 90)
- **Phone B** (Android 14, Score 80)
- **Phone C** (Android 13, Score 40)

**Flow**:
1.  **Connection**: A, B, C connect via Nearby.
2.  **Election**:
    - A sees [A:90, B:80, C:40]. A becomes **LEADER**.
    - B sees [A:90, B:80, C:40]. B becomes **FOLLOWER** (Backup).
    - C sees [A:90, B:80, C:40]. C becomes **FOLLOWER**.
3.  **Operation**:
    - B & C send `SensorPacket` to A.
    - A computes everything.
    - A broadcasts `LeaderAlertPacket` to B & C.
4.  **Failover**:
    - A disconnects (Battery dies).
    - B detects loss of A.
    - B re-runs election: [B:80, C:40].
    - B becomes **LEADER**.
    - C sends `SensorPacket` to B.
    - System recovers in < 2 seconds.


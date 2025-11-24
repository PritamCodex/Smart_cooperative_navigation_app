# Strong-Node / Weak-Node Architecture Design

## 1. System Overview

The system transitions from a pure P2P mesh to a **Dynamic Cluster Architecture**. 
- **Strong Node (Leader)**: The device with the highest `CapabilityScore` becomes the cluster leader. It acts as the central compute engine.
- **Weak Node (Follower)**: Low-tier devices that act as "dumb sensors" and "remote displays".

### Roles & Responsibilities

| Feature | Strong Node (Leader) | Weak Node (Follower) |
|---------|----------------------|----------------------|
| **Sensor Data** | Generates own & Receives peers' | Generates own & Sends to Leader |
| **Fusion (EKF)** | Runs Centralized EKF for ALL nodes | **DISABLED** |
| **Collision Logic** | Computes N x N collision matrix | **DISABLED** |
| **Alert Generation** | Generates global alert state | Receives & Displays |
| **Communication** | Broadcasts `LeaderAlertPacket` | Broadcasts `SensorPacket` |

---

## 2. Leader Election Algorithm

1.  **Discovery**: Nodes discover each other via Nearby Connections.
2.  **Capability Exchange**: On connection, nodes exchange `CapabilityPacket`.
3.  **Scoring**:
    - `Score = (OS_Ver * 10) + (RAM_GB * 5) + (GNSS_Acc_Weight) + (CPU_Tier)`
    - Threshold: Score > 70 = Potential Leader.
4.  **Election**:
    - Node with **Highest Score** declares itself Leader.
    - Tie-breaker: **Lowest Device ID** (lexicographical).
5.  **Heartbeat**: Leader sends `HeartbeatPacket` (or `LeaderAlertPacket`) every 500ms.
6.  **Failover**: If Leader is silent for 3 seconds, the next highest node takes over.

---

## 3. Packet Protocol (JSON Payloads)

### A. Capability Packet (Type: `CAPABILITY`)
Sent immediately upon connection.
```json
{
  "type": "CAPABILITY",
  "deviceId": "uuid-v4",
  "osVersion": 14,
  "score": 85,
  "isStrongNode": true
}
```

### B. Sensor Packet (Type: `SENSOR`)
Sent by **ALL** nodes to the Leader at 10Hz.
```json
{
  "type": "SENSOR",
  "deviceId": "uuid-v4",
  "timestamp": 1716234000000,
  "gnss": {
    "lat": 12.9716,
    "lon": 77.5946,
    "acc": 4.5,
    "spd": 1.2,
    "head": 45.0
  },
  "imu": {
    "accel": [0.1, 0.0, 9.8],
    "gyro": [0.0, 0.0, 0.1],
    "mag": [10.0, 20.0, 30.0]
  },
  "rssi": -55
}
```

### C. Leader Alert Packet (Type: `ALERT`)
Sent by **Leader** to **ALL** nodes at 10-20Hz.
```json
{
  "type": "ALERT",
  "leaderId": "uuid-v4",
  "timestamp": 1716234000050,
  "globalState": "WARNING",
  "peers": [
    {
      "deviceId": "uuid-weak-1",
      "relDist": 5.4,
      "alertLevel": "ORANGE",
      "azimuth": 120
    },
    {
      "deviceId": "uuid-weak-2",
      "relDist": 12.1,
      "alertLevel": "GREEN",
      "azimuth": 270
    }
  ]
}
```

---

## 4. Fallback Logic (Reduced Mode)

If **NO Leader** is present (e.g., all nodes are Weak):
1.  Nodes enter `REDUCED_MODE`.
2.  **EKF Disabled**.
3.  **GPS-Only Logic**: Simple distance calculation using raw GPS.
4.  **RSSI-Only Logic**: If GPS > 20m accuracy, use RSSI ranging.
5.  **UI**: Shows "Low Accuracy Mode" banner.


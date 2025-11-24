# 📁 Complete File Structure - Cooperative Navigation Safety App

## 📊 Overview

**Total Dart Files**: ~33 files  
**Total Lines of Code**: ~15,000+ lines  
**Main Components**: 8 major systems  
**Architecture**: Modular, service-based

---

## 🎯 MAIN APPLICATION FILES

### Entry Point
```
lib/
├── main.dart                          # App entry point, initializes providers
└── src/
    └── app.dart                       # Main app widget, MaterialApp setup
```

**Purpose**: 
- `main.dart` - Launches the app, sets up Riverpod providers
- `app.dart` - Configures theme, routes, and main screen

---

## 🏗️ CORE LAYER (Data Models & Configuration)

### Core Models (`lib/src/core/models/`)
```
├── beacon_packet.dart                 # Legacy beacon format (v1 protocol)
├── cluster_packet.dart                # NEW v2 protocol (5 packet types)
│   ├── CapabilityPacket              # Device capability exchange
│   ├── SensorPacket                  # GNSS + IMU data
│   ├── LeaderAlertPacket             # Collision alerts
│   ├── HeartbeatPacket               # Leader liveness
│   └── ElectionPacket                # Leader election
├── sensor_data.dart                   # IMU/GNSS raw data structures
└── collision_alert.dart               # Alert level definitions
```

**Key File**: `cluster_packet.dart` (~420 lines)
- Defines all communication protocols
- Version 2 protocol with backward compatibility
- JSON serialization for all packet types

### Configuration (`lib/src/core/config/`)
```
└── feature_flags.dart                 # Feature toggles & thresholds
    ├── GPS_ACCURACY_THRESHOLD = 20m
    ├── STATIONARY_SPEED_THRESHOLD = 0.5 m/s
    ├── RSSI_FUSION_ENABLED = true
    └── DISTRIBUTED_FUSION_ENABLED = true
```

### Theme (`lib/src/core/theme/`)
```
└── app_theme.dart                     # Dark theme with glassmorphism
    ├── Background: #0B0F1A (dark blue-gray)
    ├── Accent: #00D1B2 (neon teal)
    └── Typography: Inter font family
```

---

## 🔧 SERVICE LAYER (Business Logic)

### 1. **Capability & Election Services** (NEW - Strong/Weak Architecture)

```
lib/src/services/
├── capability_detector.dart           # NEW: Device capability scoring
│   └── assessCapability()            # Returns score 0-150
│
├── capability_engine.dart             # Detailed capability assessment
│   └── detectCapability()            # Full device profiling
│
├── leader_election_engine.dart        # NEW: Leader election state machine
│   ├── initialize()                  # Start election
│   ├── onCapabilityPacket()          # Handle peer capabilities
│   ├── onHeartbeatPacket()           # Monitor leader
│   └── stateStream                   # Election state changes
│
└── cluster_orchestrator.dart          # NEW: Main coordinator
    ├── initialize()                  # Setup entire system
    ├── handleIncomingPacket()        # Route packets
    ├── updateSensorData()            # Feed sensors
    └── roleChangeStream              # Role transitions
```

**Key Files**:
- `capability_detector.dart` (170 lines) - Scores devices
- `leader_election_engine.dart` (360 lines) - Manages elections
- `cluster_orchestrator.dart` (330 lines) - Coordinates everything

### 2. **Fusion Engines** (Position Estimation)

```
lib/src/services/fusion/
├── distributed_fusion_engine.dart     # Basic EKF (existing)
├── centralized_fusion_engine.dart     # Multi-device fusion
├── strong_node_engine.dart            # Leader fusion logic
├── mid_node_engine.dart               # Mid-tier device logic
├── weak_node_engine.dart              # Follower logic (existing)
└── strong_node_controller.dart        # NEW: Complete leader controller
    ├── addSensorPacket()             # Collect from peers
    ├── _runFusionCycle()             # EKF at 10 Hz
    ├── _updateEKF()                  # Per-device Kalman filter
    └── _broadcastAlerts()            # Generate alerts
```

**Key File**: `strong_node_controller.dart` (450 lines)
- Multi-device Extended Kalman Filter
- N×N collision matrix computation
- RSSI fusion for close range
- Real-time alert generation (10-20 Hz)

### 3. **Weak Node System** (NEW)

```
lib/src/services/
└── weak_node_controller.dart          # NEW: Follower controller
    ├── startTransmission()           # Begin sending to leader
    ├── updateSensorData()            # Feed raw data
    ├── onLeaderAlert()               # Receive alerts
    ├── stopTransmission()            # Enter reduced mode
    └── sensorPacketStream            # Outgoing packets
```

**Key File**: `weak_node_controller.dart` (240 lines)
- Adaptive transmission (2-10 Hz based on speed)
- Leader watchdog (3s timeout)
- Reduced mode fallback (RSSI-only)

### 4. **Sensor Services** (Data Collection)

```
lib/src/services/
├── sensor_service.dart                # GNSS + IMU + Battery
│   ├── initializeGNSS()              # Start location tracking
│   ├── initializeIMU()               # Start accelerometer/gyro
│   └── locationStream                # Real-time position
│
└── incident_detector.dart             # Sudden deceleration detection
    ├── analyzeAcceleration()         # Detect crashes
    └── incidentStream                # Emergency events
```

**Key File**: `sensor_service.dart` (340 lines)
- Interfaces with device sensors
- Provides GNSS at 1-10 Hz
- Provides IMU at 50-100 Hz

### 5. **Nearby Communication** (P2P Networking)

```
lib/src/services/
├── nearby_service.dart                # Main P2P service
│   ├── startDiscovery()              # Find peers
│   ├── sendPayload()                 # Transmit data
│   └── onPayloadReceived()           # Receive data
│
└── nearby/
    ├── packet_protocol.dart          # Packet encoding/decoding
    ├── connection_manager.dart       # Manage endpoints
    └── payload_handler.dart          # Process received data
```

**Key File**: `nearby_service.dart` (375 lines)
- Google Nearby Connections API
- P2P_CLUSTER strategy
- <300ms latency

### 6. **Collision Detection**

```
lib/src/services/
└── collision_engine.dart              # TTC calculations
    ├── computeDistance()             # Haversine formula
    ├── computeTTC()                  # Time-to-collision
    └── classifyAlertLevel()          # GREEN/YELLOW/ORANGE/RED
```

**Key File**: `collision_engine.dart` (125 lines)
- Haversine distance calculation
- Relative velocity computation
- Alert level classification

### 7. **Legacy/Compatibility**

```
lib/src/services/
├── cluster_manager.dart               # Basic cluster management (old)
├── capability_service.dart            # Simple scoring (old)
└── nearby_service_v2_template.dart    # Template for new service
```

---

## 🎨 UI LAYER (User Interface)

### Screens
```
lib/src/ui/screens/
└── main_screen.dart                   # Main app screen
    ├── Radar display
    ├── Alert banners
    ├── Control panel
    └── Status cards
```

**Key File**: `main_screen.dart` (~500 lines)
- Central UI hub
- Coordinates all widgets
- Displays real-time data

### Widgets
```
lib/src/ui/widgets/
├── radar_widget.dart                  # Circular radar view
│   ├── 60 FPS smooth animation
│   ├── Peer indicators
│   └── Distance rings
│
├── alert_banner.dart                  # Slide-in alert notifications
│   └── Color-coded by severity
│
├── status_card.dart                   # Device status display
│   ├── Battery level
│   ├── GPS accuracy
│   └── Connection count
│
├── control_panel.dart                 # Start/stop controls
├── glass_card.dart                    # Glassmorphism card component
└── peer_indicator.dart                # Peer device visualization
```

**Key Files**:
- `radar_widget.dart` (400 lines) - Main visualization
- `alert_banner.dart` (200 lines) - Alert system
- `status_card.dart` (150 lines) - Status display

---

## 🔌 STATE MANAGEMENT

### Providers
```
lib/src/providers/
└── app_providers.dart                 # Riverpod providers
    ├── sensorServiceProvider
    ├── nearbyServiceProvider
    ├── collisionEngineProvider
    ├── clusterOrchestratorProvider   # NEW
    └── leaderElectionProvider        # NEW
```

**Purpose**: Dependency injection and state management

---

## 📱 ANDROID NATIVE LAYER

### Kotlin Services
```
android/app/src/main/kotlin/com/example/cooperative_navigation_safety/
├── MainActivity.kt                    # Main activity, permissions
├── ForegroundService.kt              # Background execution
├── ConnectivityService.kt            # Network connectivity
├── SensorPlugin.kt                   # Sensor platform channel
└── NearbyConnectionsPlugin.kt        # Nearby API bridge
```

**Key Files**:
- `ForegroundService.kt` - Keeps app running in background
- `MainActivity.kt` - Handles runtime permissions

### Build Configuration
```
android/
├── build.gradle.kts                  # Project-level Gradle
├── app/
│   ├── build.gradle.kts              # App-level Gradle
│   └── src/main/
│       └── AndroidManifest.xml       # Permissions & services
```

---

## 📚 EXAMPLES & DOCUMENTATION

### Examples
```
lib/src/examples/
└── cluster_integration_example.dart   # NEW: Complete integration guide
    ├── How to wire orchestrator
    ├── Nearby Service integration
    ├── Sensor Service integration
    └── UI update handling
```

### Documentation Files
```
Root directory:
├── README.md                          # Project overview
├── ARCHITECTURE_v2.md                 # Strong/Weak design
├── IMPLEMENTATION_STATUS.md           # Implementation tracking
├── BUILD_SUCCESS_REPORT.md            # Build validation
├── BUG_FIXES.md                       # Bug tracking
│
└── NEW Strong/Weak Docs:
    ├── QUICK_START.md                 # 30-min integration guide
    ├── IMPLEMENTATION_SUMMARY.md      # Executive summary
    ├── STRONG_WEAK_ARCHITECTURE_GUIDE.md # Complete guide
    ├── ARCHITECTURE_VISUAL.md         # Visual diagrams
    ├── DELIVERABLES.md                # File inventory
    └── PROJECT_FILE_STRUCTURE.md      # This file
```

---

## 🗂️ FILE ORGANIZATION BY FEATURE

### **Feature 1: Strong/Weak Node Architecture** (NEW - Phase 1-8)
```
Core:
├── lib/src/core/models/cluster_packet.dart
├── lib/src/services/capability_detector.dart
├── lib/src/services/leader_election_engine.dart
├── lib/src/services/strong_node_controller.dart
├── lib/src/services/weak_node_controller.dart
└── lib/src/services/cluster_orchestrator.dart
```

### **Feature 2: Sensor Fusion** (Existing)
```
├── lib/src/services/fusion/distributed_fusion_engine.dart
├── lib/src/services/fusion/centralized_fusion_engine.dart
├── lib/src/services/fusion/strong_node_engine.dart
├── lib/src/services/fusion/mid_node_engine.dart
└── lib/src/services/fusion/weak_node_engine.dart
```

### **Feature 3: P2P Communication** (Existing)
```
├── lib/src/services/nearby_service.dart
├── lib/src/services/nearby/packet_protocol.dart
├── lib/src/services/nearby/connection_manager.dart
└── android/.../NearbyConnectionsPlugin.kt
```

### **Feature 4: Collision Detection** (Existing)
```
├── lib/src/services/collision_engine.dart
└── lib/src/services/incident_detector.dart
```

### **Feature 5: UI/Visualization** (Existing)
```
├── lib/src/ui/screens/main_screen.dart
├── lib/src/ui/widgets/radar_widget.dart
├── lib/src/ui/widgets/alert_banner.dart
└── lib/src/ui/widgets/status_card.dart
```

---

## 📊 FILE SIZE STATISTICS

### By Component
| Component | Files | Approx Lines | Purpose |
|-----------|-------|--------------|---------|
| **Core Models** | 4 | ~1,000 | Data structures |
| **Strong/Weak System** | 6 | ~2,220 | NEW architecture |
| **Fusion Engines** | 5 | ~3,500 | Position estimation |
| **Services** | 7 | ~4,000 | Business logic |
| **UI Components** | 7 | ~2,500 | User interface |
| **Native (Kotlin)** | 5 | ~1,500 | Platform integration |
| **Providers** | 1 | ~200 | State management |
| **Examples** | 1 | ~250 | Integration guide |
| **TOTAL** | **~36** | **~15,170** | |

---

## 🎯 MOST IMPORTANT FILES (Top 10)

### For Understanding the System:
1. **`cluster_orchestrator.dart`** (330 lines)
   - Main coordinator, ties everything together
   - Start here to understand the flow

2. **`cluster_packet.dart`** (420 lines)
   - All communication protocols
   - Essential for understanding data exchange

3. **`leader_election_engine.dart`** (360 lines)
   - Election state machine
   - Core of distributed decision making

4. **`strong_node_controller.dart`** (450 lines)
   - Leader's fusion and collision logic
   - Most complex algorithm

5. **`sensor_service.dart`** (340 lines)
   - Data collection from hardware
   - Feeds the entire system

6. **`nearby_service.dart`** (375 lines)
   - P2P communication backbone
   - How devices talk to each other

7. **`main_screen.dart`** (~500 lines)
   - Central UI hub
   - User interaction point

8. **`radar_widget.dart`** (400 lines)
   - Main visualization
   - Real-time display

9. **`collision_engine.dart`** (125 lines)
   - Alert generation
   - Safety-critical logic

10. **`app_providers.dart`** (~200 lines)
    - Dependency injection
    - Connects all services

---

## 🔍 HOW TO NAVIGATE THE CODEBASE

### Starting Point for Different Tasks:

**1. Understanding the Architecture**
```
Read: ARCHITECTURE_v2.md
Then: cluster_orchestrator.dart
Then: cluster_packet.dart
```

**2. Implementing Integration**
```
Read: QUICK_START.md
Then: lib/src/examples/cluster_integration_example.dart
Then: cluster_orchestrator.dart
```

**3. Understanding Sensor Fusion**
```
Start: lib/src/services/fusion/distributed_fusion_engine.dart
Then: strong_node_controller.dart
Then: weak_node_controller.dart
```

**4. Understanding P2P Communication**
```
Start: lib/src/services/nearby_service.dart
Then: lib/src/services/nearby/packet_protocol.dart
Then: cluster_packet.dart
```

**5. Modifying the UI**
```
Start: lib/src/ui/screens/main_screen.dart
Then: lib/src/ui/widgets/radar_widget.dart
Then: lib/src/ui/widgets/alert_banner.dart
```

---

## 🚀 QUICK FILE REFERENCE

### Need to...

**Add a new packet type?**
→ `lib/src/core/models/cluster_packet.dart`

**Change capability scoring?**
→ `lib/src/services/capability_detector.dart`

**Modify election logic?**
→ `lib/src/services/leader_election_engine.dart`

**Adjust fusion algorithm?**
→ `lib/src/services/strong_node_controller.dart`

**Change transmission rates?**
→ `lib/src/services/weak_node_controller.dart`

**Update thresholds?**
→ `lib/src/core/config/feature_flags.dart`

**Modify UI theme?**
→ `lib/src/core/theme/app_theme.dart`

**Add a new widget?**
→ `lib/src/ui/widgets/`

**Change permissions?**
→ `android/app/src/main/AndroidManifest.xml`

---

## 💡 DEPENDENCIES (pubspec.yaml)

```yaml
dependencies:
  nearby_connections: ^4.0.0      # P2P communication
  location: ^7.0.0                # GNSS access
  sensors_plus: ^6.0.0            # IMU access
  flutter_riverpod: ^2.6.1        # State management
  vector_math: ^2.1.4             # Math operations
  device_info_plus: ^12.2.0       # Device detection
  flutter_foreground_task: ^8.0.0 # Background service
  permission_handler: ^11.3.0     # Runtime permissions
  google_fonts: ^6.1.0            # Typography
  uuid: ^4.0.0                    # Unique IDs
```

---

**Total Project Size**: ~15,000+ lines of code across 36+ Dart files + 5 Kotlin files

**Complexity**: High (distributed systems, sensor fusion, real-time processing)

**Architecture**: Clean, modular, service-based with clear separation of concerns

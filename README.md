# 📡 Cooperative Navigation Safety System

A real-time, peer-to-peer navigation safety system that detects potential collisions and broadcasts alerts between nearby devices using low-latency communication.

This system focuses on real-time processing, sensor fusion, and distributed communication without requiring internet connectivity.

---

## 🚀 Key Features

- ⚡ Ultra-Low Latency Communication  
  - <300ms device-to-device transmission  
  - Peer-to-peer clustering (no central server)  

- 📍 Real-Time Sensor Integration  
  - GNSS (location tracking)  
  - IMU sensors (acceleration, motion detection)  

- 🚨 Collision Detection  
  - Time-To-Collision (TTC) calculation  
  - Real-time risk alerts  

- 📢 Emergency Broadcasting  
  - Instant alerts to nearby devices  
  - Incident detection (sudden stops, abnormal motion)  

- 🌐 Offline Operation  
  - Works without internet  
  - Uses Nearby Connections API  

---

## 🏗️ System Architecture

Sensor Data (GNSS + IMU)
↓
Sensor Fusion Layer
↓
Collision Detection Engine
(TTC Calculation)
↓
P2P Communication Layer
(Nearby Connections API)
↓
Alert & Visualization UI


---

## 🛠️ Tech Stack

- Frontend: Flutter  
- Native Layer: Kotlin  
- Communication: Google Nearby Connections  
- Sensors: GNSS, Accelerometer, Gyroscope  
- Platform: Android  

---

## ⚡ Performance Highlights

- Latency: ~150–300ms  
- Processing Time: <10ms per cycle  
- UI: 60 FPS radar visualization  
- Battery: Optimized for continuous operation  

---

## 🧠 Core Logic

### Collision Detection
- Uses distance and relative velocity  
- Calculates Time-To-Collision (TTC)  
- Generates multi-level alerts  

### Communication
- Peer-to-peer clustering  
- Automatic reconnection  
- Optimized packet transmission  

---

## 📦 Example Beacon Packet

```json
{
  "type": "beacon",
  "lat": 37.7749,
  "lon": -122.4194,
  "speed": 15.5,
  "heading": 135.0
}
```

## ⚙️ Setup Instructions
flutter pub get
flutter run

🎯 Problem Solved

Traditional navigation systems:

Do not communicate with nearby users
Cannot predict collisions in real-time

This system enables:

Real-time peer awareness
Predictive safety alerts
Offline cooperative navigation
🚀 Future Scope
Machine learning-based prediction
iOS support
Voice alerts
Vehicle system integration
⭐ Note

This project demonstrates real-time systems, distributed communication, and low-latency processing — not just mobile UI development.

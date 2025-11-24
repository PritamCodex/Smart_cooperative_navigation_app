import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:cooperative_navigation_safety/src/core/models/sensor_data.dart';
import 'fusion/distributed_fusion_engine.dart';
import '../core/config/feature_flags.dart';

class SensorService {
  static const MethodChannel _channel = MethodChannel('cooperative_navigation_safety/sensors');
  
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  final StreamController<SensorData> _sensorController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorStream => _sensorController.stream;
  
  DateTime? _lastLocationTime;
  // LocationData? _lastLocation; // Unused
  SensorData? _lastSensorData;
  
  bool _isRunning = false;
  
  Future<void> initialize() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print('Warning: Location service not enabled - features will be limited');
          return; // Don't throw, just return
        }
      }
      
      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('Warning: Location permission not granted - features will be limited');
          return; // Don't throw, just return
        }
      }
      
      _location.changeSettings(
        accuracy: LocationAccuracy.navigation,
        interval: 100, // Request updates as fast as possible
        distanceFilter: 0,
      );
      
    } catch (e) {
      print('Sensor initialization error: $e');
      // Don't rethrow - let the app continue
    }
  }
  
  void startSensors() {
    if (_isRunning) return;
    
    _isRunning = true;
    
    // Location updates (1-10Hz)
    _locationSubscription = _location.onLocationChanged.listen((locationData) {
      // _lastLocation = locationData;
      _lastLocationTime = DateTime.now();
      
      if (_lastSensorData != null) {
        _lastSensorData = _lastSensorData!.copyWith(
          latitude: locationData.latitude,
          longitude: locationData.longitude,
          altitude: locationData.altitude,
          speed: locationData.speed,
          accuracy: locationData.accuracy,
          // Use GPS heading if moving (> 0.5 m/s) and available
          heading: (locationData.speed ?? 0) > 0.5 && locationData.heading != null 
              ? locationData.heading 
              : _lastSensorData!.heading,
        );
        _processSensorData();
      }
    });
    
    // IMU sensors (50-100Hz)
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (_lastSensorData != null) {
        _lastSensorData = _lastSensorData!.copyWith(
          accelerometerX: event.x,
          accelerometerY: event.y,
          accelerometerZ: event.z,
        );
        _processSensorData();
      }
    });
    
    _gyroscopeSubscription = gyroscopeEventStream().listen((event) {
      if (_lastSensorData != null) {
        _lastSensorData = _lastSensorData!.copyWith(
          gyroscopeX: event.x,
          gyroscopeY: event.y,
          gyroscopeZ: event.z,
        );
        _processSensorData();
      }
    });
    
    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      if (_lastSensorData != null) {
        final heading = math.atan2(event.y, event.x) * 180 / math.pi;
        _lastSensorData = _lastSensorData!.copyWith(
          magnetometerX: event.x,
          magnetometerY: event.y,
          magnetometerZ: event.z,
          // Only use magnetometer heading if stationary or GPS heading unavailable
          heading: (_lastSensorData!.speed ?? 0) < 0.5 
              ? heading 
              : _lastSensorData!.heading,
        );
        _processSensorData();
      }
    });
    
    // Initialize sensor data
    _lastSensorData = SensorData(
      timestamp: DateTime.now(),
      accelerometerX: 0,
      accelerometerY: 0,
      accelerometerZ: 0,
      gyroscopeX: 0,
      gyroscopeY: 0,
      gyroscopeZ: 0,
      magnetometerX: 0,
      magnetometerY: 0,
      magnetometerZ: 0,
      latitude: 0.0,
      longitude: 0.0,
      altitude: 0.0,
      speed: 0.0,
      accuracy: 0.0,
    );
  }
  
  void stopSensors() {
    if (!_isRunning) return;
    
    _isRunning = false;
    _locationSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _magnetometerSubscription?.cancel();
  }
  
  // Filter constants
  static const double _minSpeedThreshold = 0.5; // m/s
  static const double _gpsUnstableThreshold = 20.0; // meters
  
  // Fusion Engine
  final DistributedFusionEngine? _fusionEngine;
  
  SensorService([this._fusionEngine]);

  double? _lastValidHeading;
  double? _lastValidSpeed;
  SensorData? _frozenStationaryData;

  void _processSensorData() {
    if (_lastSensorData == null) return;
    
    final currentTime = DateTime.now();
    final timeSinceLastUpdate = _lastLocationTime != null 
        ? currentTime.difference(_lastLocationTime!).inMilliseconds 
        : 1000;
    
    // Only emit if we have recent location data (within 2 seconds)
    if (timeSinceLastUpdate < 2000) {
      var processedData = _lastSensorData!.copyWith(timestamp: currentTime);
      
      // FUSION ENGINE INTEGRATION
      if (FeatureFlags.FEATURE_DISTRIBUTED_FUSION && _fusionEngine != null) {
        // 1. Predict Step
        final dt = timeSinceLastUpdate / 1000.0;
        _fusionEngine!.predict(processedData, dt);
        
        // 2. Update Step (GNSS)
        if (processedData.latitude != null && processedData.longitude != null) {
           // Initialize if first run (0,0)
           if (_fusionEngine!.latitude == 0 && _fusionEngine!.longitude == 0) {
             _fusionEngine!.initialize(
               processedData.latitude!, 
               processedData.longitude!, 
               processedData.accuracy ?? 20.0
             );
           }
           
           _fusionEngine!.updateGNSS(
             processedData.latitude!, 
             processedData.longitude!, 
             processedData.accuracy ?? 20.0
           );
        }
        
        // 3. Overwrite with Fused State
        // This ensures the rest of the app uses the refined position
        processedData = processedData.copyWith(
          latitude: _fusionEngine!.latitude,
          longitude: _fusionEngine!.longitude,
          accuracy: _fusionEngine!.accuracy,
        );
      }

      // 1. GPS Accuracy Check (Legacy/Fallback logic)
      if ((processedData.accuracy ?? 0) > _gpsUnstableThreshold) {
        // High uncertainty
      }

      // 2. Dead Reckoning / Stationary Anchor
      // If Fusion is enabled, it handles stationary logic internally via FEATURE_DEAD_RECKONING_STABILITY
      // But we keep this as a fallback or for the "Speed" field which Fusion might not output directly
      final currentSpeed = processedData.speed ?? 0;
      
      if (FeatureFlags.FEATURE_DEAD_RECKONING_STABILITY && currentSpeed < _minSpeedThreshold) {
        // STATIONARY MODE:
        // If Fusion is OFF, we use this manual anchor logic.
        // If Fusion is ON, it already locked the position, but we still need to zero the speed.
        
        if (!FeatureFlags.FEATURE_DISTRIBUTED_FUSION) {
           _frozenStationaryData ??= processedData;
           processedData = processedData.copyWith(
             speed: 0.0,
             heading: _lastValidHeading ?? _frozenStationaryData!.heading,
             latitude: _frozenStationaryData!.latitude,
             longitude: _frozenStationaryData!.longitude,
             altitude: _frozenStationaryData!.altitude,
           );
        } else {
           // Fusion is ON, just zero the speed for UI
           // AND freeze heading to prevent rotation jitter
           processedData = processedData.copyWith(
             speed: 0.0,
             heading: _lastValidHeading ?? processedData.heading,
           );
        }
      } else {
        // MOVING MODE:
        _frozenStationaryData = null;
        _lastValidHeading = processedData.heading;
        _lastValidSpeed = currentSpeed;
      }
      
      _sensorController.add(processedData);
    }
  }
  
  void calibrate() {
    _fusionEngine?.calibrateSensors();
  }
  
  Future<double?> getHeading() async {
    try {
      final double? heading = await _channel.invokeMethod('getHeading');
      return heading;
    } catch (e) {
      print('Error getting heading: $e');
      return null;
    }
  }
  
  Future<Map<String, dynamic>?> getGnssRawData() async {
    try {
      final Map<dynamic, dynamic>? rawData = await _channel.invokeMethod('getGnssRawData');
      return rawData?.cast<String, dynamic>();
    } catch (e) {
      print('Error getting GNSS raw data: $e');
      return null;
    }
  }
  
  void dispose() {
    stopSensors();
    _sensorController.close();
  }
}
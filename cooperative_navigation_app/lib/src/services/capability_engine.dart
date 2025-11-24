// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
// Note: In a real implementation, you would import these:
// import 'package:geolocator/geolocator.dart';
// import 'package:sensors_plus/sensors_plus.dart';
// import 'package:battery_plus/battery_plus.dart';
// import 'package:permission_handler/permission_handler.dart';

/// Enum representing the capability tier of a node in the cooperative network.
enum NodeTier {
  /// High-performance device capable of leading the cluster, running EKF,
  /// and managing complex fusion tasks. Score >= 70.
  STRONG_NODE,

  /// Moderate-performance device capable of participating fully but
  /// preferably not as a leader unless necessary. Score 40-69.
  MID_NODE,

  /// Low-performance or legacy device that should operate in a reduced capacity,
  /// primarily sending raw data and receiving alerts. Score < 40.
  WEAK_NODE
}

/// Classification of CPU performance based on synthetic benchmarks.
enum CpuClass { LOW, MID, HIGH }

/// Thermal status of the device.
enum ThermalState { NOMINAL, LIGHT, MODERATE, SEVERE }

/// Raw metrics collected from the device to assess its capability.
class DeviceStats {
  final int androidVersion;
  final double gnssAccuracy; // in meters
  final bool hasGnssChipsetSupport; // Dual-frequency, etc.
  final double imuNoiseLevel; // Variance (0.0 - 1.0)
  final CpuClass cpuClass;
  final bool isBatterySaverEnabled;
  final bool hasOemDeepSleepRestrictions;
  final ThermalState thermalState;
  final double sensorUpdateRate; // Hz
  final bool canPerformBleScanning;
  final int cpuCores;
  final int ramMB;
  final DateTime collectedAt;

  DeviceStats({
    required this.androidVersion,
    required this.gnssAccuracy,
    required this.hasGnssChipsetSupport,
    required this.imuNoiseLevel,
    required this.cpuClass,
    required this.isBatterySaverEnabled,
    required this.hasOemDeepSleepRestrictions,
    required this.thermalState,
    required this.sensorUpdateRate,
    required this.canPerformBleScanning,
    required this.cpuCores,
    required this.ramMB,
    DateTime? collectedAt,
  }) : collectedAt = collectedAt ?? DateTime.now();

  DeviceStats copyWith({
    int? androidVersion,
    double? gnssAccuracy,
    bool? hasGnssChipsetSupport,
    double? imuNoiseLevel,
    CpuClass? cpuClass,
    bool? isBatterySaverEnabled,
    bool? hasOemDeepSleepRestrictions,
    ThermalState? thermalState,
    double? sensorUpdateRate,
    bool? canPerformBleScanning,
    int? cpuCores,
    int? ramMB,
    DateTime? collectedAt,
  }) {
    return DeviceStats(
      androidVersion: androidVersion ?? this.androidVersion,
      gnssAccuracy: gnssAccuracy ?? this.gnssAccuracy,
      hasGnssChipsetSupport: hasGnssChipsetSupport ?? this.hasGnssChipsetSupport,
      imuNoiseLevel: imuNoiseLevel ?? this.imuNoiseLevel,
      cpuClass: cpuClass ?? this.cpuClass,
      isBatterySaverEnabled: isBatterySaverEnabled ?? this.isBatterySaverEnabled,
      hasOemDeepSleepRestrictions: hasOemDeepSleepRestrictions ?? this.hasOemDeepSleepRestrictions,
      thermalState: thermalState ?? this.thermalState,
      sensorUpdateRate: sensorUpdateRate ?? this.sensorUpdateRate,
      canPerformBleScanning: canPerformBleScanning ?? this.canPerformBleScanning,
      cpuCores: cpuCores ?? this.cpuCores,
      ramMB: ramMB ?? this.ramMB,
      collectedAt: collectedAt ?? this.collectedAt,
    );
  }

  @override
  String toString() {
    return 'DeviceStats(Android: $androidVersion, GNSS: ${gnssAccuracy.toStringAsFixed(1)}m, '
        'CPU: ${cpuClass.name}, BatterySaver: $isBatterySaverEnabled, '
        'Thermal: ${thermalState.name}, RAM: ${ramMB}MB)';
  }
}

/// The final capability assessment result.
class DeviceCapability {
  final NodeTier tier;
  final int score;
  final DeviceStats stats;
  final Map<String, int> breakdown;
  final DateTime assessedAt;
  final String deviceModel;
  final String deviceId;

  DeviceCapability({
    required this.tier,
    required this.score,
    required this.stats,
    required this.breakdown,
    required this.deviceModel,
    required this.deviceId,
    DateTime? assessedAt,
  }) : assessedAt = assessedAt ?? DateTime.now();

  @override
  String toString() {
    return 'DeviceCapability(Tier: ${tier.name}, Score: $score, Model: $deviceModel)';
  }
}

/// Engine responsible for assessing device capabilities and assigning a NodeTier.
///
/// This class orchestrates the collection of hardware, OS, and runtime metrics
/// to compute a capability score. It is designed to be robust, handling timeouts
/// and missing sensors gracefully.
class CapabilityEngine {
  static final CapabilityEngine _instance = CapabilityEngine._internal();
  factory CapabilityEngine() => _instance;
  CapabilityEngine._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  // Cache for static metrics that don't change during app lifecycle
  DeviceStats? _cachedStaticStats;

  /// Main entry point to detect device capability.
  ///
  /// Collects all necessary stats, computes the score, and returns the classification.
  /// This operation may take a few seconds (up to 5s) to complete fully.
  Future<DeviceCapability> detectCapability() async {
    final stats = await collectDeviceStats();
    final score = computeScore(stats);
    final tier = classifyFromScore(score);
    final breakdown = _generateBreakdown(stats);

    // Get basic device info for the report
    String model = 'Unknown';
    String id = 'Anonymous';
    
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      model = '${androidInfo.manufacturer} ${androidInfo.model}';
      id = androidInfo.id;
    }

    return DeviceCapability(
      tier: tier,
      score: score,
      stats: stats,
      breakdown: breakdown,
      deviceModel: model,
      deviceId: id,
    );
  }

  /// Computes a score (0-100) based on the provided [DeviceStats].
  int computeScore(DeviceStats stats) {
    int score = 0;

    // 1. Android OS Version (Max 15)
    if (stats.androidVersion >= 33) { // Android 13+
      score += 15;
    } else if (stats.androidVersion >= 29) { // Android 10-12
      score += 10;
    } else if (stats.androidVersion >= 26) { // Android 8-9
      score += 5;
    }

    // 2. GNSS Accuracy (Max 12)
    if (stats.gnssAccuracy < 5.0) {
      score += 12;
    } else if (stats.gnssAccuracy < 10.0) {
      score += 8;
    } else if (stats.gnssAccuracy < 20.0) {
      score += 4;
    }

    // 3. GNSS Chipset Support (Max 8)
    if (stats.hasGnssChipsetSupport) {
      score += 8;
    }

    // 4. IMU Stability (Max 10)
    if (stats.imuNoiseLevel < 0.1) {
      score += 10;
    } else if (stats.imuNoiseLevel < 0.3) {
      score += 6;
    } else if (stats.imuNoiseLevel < 0.5) {
      score += 3;
    }

    // 5. CPU Class (Max 15)
    switch (stats.cpuClass) {
      case CpuClass.HIGH:
        score += 15;
        break;
      case CpuClass.MID:
        score += 8;
        break;
      case CpuClass.LOW:
        score += 0;
        break;
    }

    // 6. Battery Saver (Max 5)
    if (!stats.isBatterySaverEnabled) {
      score += 5;
    }

    // 7. OEM Restrictions (Max 8)
    if (!stats.hasOemDeepSleepRestrictions) {
      score += 8;
    }

    // 8. Thermal State (Max 7)
    switch (stats.thermalState) {
      case ThermalState.NOMINAL:
        score += 7;
        break;
      case ThermalState.LIGHT:
        score += 4;
        break;
      case ThermalState.MODERATE:
        score += 2;
        break;
      case ThermalState.SEVERE:
        score += 0;
        break;
    }

    // 9. Sensor Update Rate (Max 10)
    if (stats.sensorUpdateRate >= 50.0) {
      score += 10;
    } else if (stats.sensorUpdateRate >= 30.0) {
      score += 6;
    } else if (stats.sensorUpdateRate >= 10.0) {
      score += 3;
    }

    // 10. BLE Scanning (Max 10)
    if (stats.canPerformBleScanning) {
      score += 10;
    }

    return score.clamp(0, 100);
  }

  /// Classifies the node tier based on the computed score.
  NodeTier classifyFromScore(int score) {
    if (score >= 70) {
      return NodeTier.STRONG_NODE;
    } else if (score >= 40) {
      return NodeTier.MID_NODE;
    } else {
      return NodeTier.WEAK_NODE;
    }
  }

  /// Collects all device statistics.
  ///
  /// This method aggregates data from various sensors and system APIs.
  /// It handles timeouts and errors by providing conservative fallback values.
  Future<DeviceStats> collectDeviceStats() async {
    // 1. Android Version & Hardware Info
    int androidVer = 0;
    int cores = 4;
    int ram = 2048;
    String manufacturer = '';

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      androidVer = androidInfo.version.sdkInt;
      manufacturer = androidInfo.manufacturer;
      // Note: Getting RAM/Cores accurately usually requires native code or reading /proc/cpuinfo
      // Here we assume standard values or mock them for pure Dart implementation
      cores = 8; // Placeholder
      ram = 4096; // Placeholder
    }

    // 2. Parallel execution of time-consuming tasks
    final results = await Future.wait([
      _measureGnssAccuracy(),
      _hasGnssChipsetSupport(),
      _estimateImuNoise(),
      _benchmarkCpu(),
      _isBatterySaverEnabled(),
      _getThermalState(),
      _measureSensorRate(),
      _canScanBle(),
    ]);

    final gnssAccuracy = results[0] as double;
    final hasGnssSupport = results[1] as bool;
    final imuNoise = results[2] as double;
    final cpuClass = results[3] as CpuClass;
    final batterySaver = results[4] as bool;
    final thermal = results[5] as ThermalState;
    final sensorRate = results[6] as double;
    final canBle = results[7] as bool;

    // 3. OEM Restrictions Check
    final hasOemRestrictions = _checkOemRestrictions(manufacturer);

    return DeviceStats(
      androidVersion: androidVer,
      gnssAccuracy: gnssAccuracy,
      hasGnssChipsetSupport: hasGnssSupport,
      imuNoiseLevel: imuNoise,
      cpuClass: cpuClass,
      isBatterySaverEnabled: batterySaver,
      hasOemDeepSleepRestrictions: hasOemRestrictions,
      thermalState: thermal,
      sensorUpdateRate: sensorRate,
      canPerformBleScanning: canBle,
      cpuCores: cores,
      ramMB: ram,
    );
  }

  /// Monitors dynamic changes in device capability (e.g., battery saver toggled).
  Stream<NodeTier> watchDynamicTierChanges() {
    // Poll every 30 seconds for changes in dynamic metrics
    return Stream.periodic(const Duration(seconds: 30), (_) async {
      // We only re-check dynamic properties to save battery
      final batterySaver = await _isBatterySaverEnabled();
      final thermal = await _getThermalState();
      
      // If we have cached stats, update them and re-score
      if (_cachedStaticStats != null) {
        // Create a new stats object with updated dynamic values
        final updatedStats = _cachedStaticStats!.copyWith(
          isBatterySaverEnabled: batterySaver,
          thermalState: thermal,
          collectedAt: DateTime.now(),
        );
        
        // Update cache
        _cachedStaticStats = updatedStats;
        
        return classifyFromScore(computeScore(updatedStats)); 
      }
      
      // Fallback to full detection if no cache
      final cap = await detectCapability();
      _cachedStaticStats = cap.stats;
      return cap.tier;
    }).asyncMap((event) => event).distinct();
  }

  // ---------------------------------------------------------------------------
  // Private Helper Methods
  // ---------------------------------------------------------------------------

  Future<double> _measureGnssAccuracy() async {
    try {
      // In a real app:
      // return await Geolocator.getCurrentPosition(
      //   desiredAccuracy: LocationAccuracy.high,
      //   timeLimit: Duration(seconds: 2)
      // ).then((p) => p.accuracy);
      
      // Mock implementation:
      await Future.delayed(const Duration(milliseconds: 500));
      return 4.5; // Simulate good accuracy
    } catch (e) {
      return 999.9; // Error/Timeout
    }
  }

  Future<bool> _hasGnssChipsetSupport() async {
    // Requires native platform channel to query GnssStatus/GnssCapabilities
    // Mock: Assume true for newer Android versions
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return info.version.sdkInt >= 30; // Android 11+ often has better support
    }
    return false;
  }

  Future<double> _estimateImuNoise() async {
    try {
      // In a real app: Subscribe to accelerometerStream, collect samples, compute variance
      await Future.delayed(const Duration(milliseconds: 500));
      return 0.05; // Low noise
    } catch (e) {
      return 1.0; // High noise (fallback)
    }
  }

  Future<CpuClass> _benchmarkCpu() async {
    final stopwatch = Stopwatch()..start();
    // Simple floating point stress test
    double result = 0.0;
    for (int i = 0; i < 1000000; i++) {
      result += math.sin(i) * math.cos(i);
    }
    stopwatch.stop();
    
    // Prevent optimization (though unlikely in JIT)
    if (result.isNaN) return CpuClass.LOW;
    
    final elapsed = stopwatch.elapsedMilliseconds;
    
    if (elapsed < 50) return CpuClass.HIGH;
    if (elapsed < 150) return CpuClass.MID;
    return CpuClass.LOW;
  }

  Future<bool> _isBatterySaverEnabled() async {
    // In real app: return await Battery().batteryState == BatteryState.charging ...
    // or native check for Power Save Mode
    return false; 
  }

  Future<ThermalState> _getThermalState() async {
    // Requires Android 10+ PowerManager.getCurrentThermalStatus() via native channel
    return ThermalState.NOMINAL;
  }

  Future<double> _measureSensorRate() async {
    // In real app: Count sensor events over 1 second
    await Future.delayed(const Duration(milliseconds: 200));
    return 60.0; // 60Hz
  }

  Future<bool> _canScanBle() async {
    // Check permissions and hardware support
    return true;
  }

  bool _checkOemRestrictions(String manufacturer) {
    final aggressiveOems = ['Xiaomi', 'OnePlus', 'Oppo', 'Vivo', 'Huawei'];
    return aggressiveOems.any((oem) => 
      manufacturer.toLowerCase().contains(oem.toLowerCase()));
  }

  Map<String, int> _generateBreakdown(DeviceStats stats) {
    // Helper to visualize where points came from
    return {
      'Android OS': stats.androidVersion >= 33 ? 15 : (stats.androidVersion >= 29 ? 10 : 5),
      'GNSS Accuracy': stats.gnssAccuracy < 5 ? 12 : (stats.gnssAccuracy < 10 ? 8 : 4),
      'CPU Class': stats.cpuClass == CpuClass.HIGH ? 15 : (stats.cpuClass == CpuClass.MID ? 8 : 0),
      // ... add other fields as needed for debugging
    };
  }
}

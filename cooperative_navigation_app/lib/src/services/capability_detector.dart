import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/cluster_packet.dart';

final capabilityDetectorProvider = Provider<CapabilityDetector>((ref) {
  return CapabilityDetector();
});

/// Complete capability detection system following the architectural spec
class CapabilityDetector {
  // Device blacklist (known problematic models)
  static const Set<String> _blacklistedDevices = {
    'SM-A105F', // Samsung A10 (poor GNSS)
    'Redmi 6A', // Xiaomi budget series
    // Add more as discovered
  };

  /// Compute the complete capability score
  Future<CapabilityDetail> assessCapability() async {
    int score = 0;
    
    // Get device info
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt;
    final model = deviceInfo.model;
    final manufacturer = deviceInfo.manufacturer;
    
    // 1. OS Version Score (Max 50)
    int osScore = 0;
    if (sdkInt >= 34) { // Android 14+
      osScore = 50;
    } else if (sdkInt >= 33) { // Android 13
      osScore = 30;
    } else if (sdkInt >= 31) { // Android 12
      osScore = 10;
    }
    score += osScore;
    
    // 2. GNSS Capability Score (Max 30 for dual-band)
    // Note: Detecting dual-band requires native code or checking specific chipsets
    // For now, we'll use a heuristic based on Android version and manufacturer
    String gnssCapability = 'SINGLE_BAND';
    int gnssScore = 0;
    
    if (sdkInt >= 31 && _isPremiumDevice(manufacturer, model)) {
      // Likely has dual-band GNSS
      gnssCapability = 'DUAL_BAND_L1L5';
      gnssScore = 30;
    }
    score += gnssScore;
    
    // 3. GNSS Accuracy (Max 20 for <10m accuracy)
    // This would need real-time GNSS measurement - placeholder for now
    double avgGnssAccuracy = 15.0; // Assume moderate accuracy
    int gnssAccuracyScore = 0;
    if (avgGnssAccuracy < 10.0) {
      gnssAccuracyScore = 20;
    } else if (avgGnssAccuracy < 20.0) {
      gnssAccuracyScore = 10;
    }
    score += gnssAccuracyScore;
    
    // 4. CPU Tier (Max 20)
    final cores = Platform.numberOfProcessors;
    String cpuTier = 'LOW';
    int cpuScore = 0;
    
    if (cores >= 8 && _isPremiumDevice(manufacturer, model)) {
      cpuTier = 'HIGH';
      cpuScore = 20;
    } else if (cores >= 6) {
      cpuTier = 'MID';
      cpuScore = 10;
    }
    score += cpuScore;
    
    // 5. Battery Level (Penalty if low)
    int batteryLevel = 100; // TODO: Get real battery level
    int batteryPenalty = 0;
    if (batteryLevel < 15) {
      batteryPenalty = -30;
    } else if (batteryLevel < 30) {
      batteryPenalty = -10;
    }
    score += batteryPenalty;
    
    // 6. Thermal State (Penalty if throttling)
    bool isThermalThrottling = false; // TODO: Detect thermal state
    int thermalPenalty = isThermalThrottling ? -20 : 0;
    score += thermalPenalty;
    
    // 7. Device Blacklist (Penalty)
    bool isBlacklisted = _blacklistedDevices.contains(model);
    int blacklistPenalty = isBlacklisted ? -50 : 0;
    score += blacklistPenalty;
    
    // Clamp score to 0-150 range
    score = score.clamp(0, 150);
    
    return CapabilityDetail(
      osVersion: sdkInt,
      gnssCapability: gnssCapability,
      avgGnssAccuracy: avgGnssAccuracy,
      cpuTier: cpuTier,
      batteryLevel: batteryLevel,
      isThermalThrottling: isThermalThrottling,
      isBlacklisted: isBlacklisted,
      capabilityScore: score,
    );
  }
  
  /// Heuristic to detect premium devices
  bool _isPremiumDevice(String manufacturer, String model) {
    final mfg = manufacturer.toLowerCase();
    final mdl = model.toLowerCase();
    
    // Samsung flagship series
    if (mfg.contains('samsung') && (mdl.contains('s2') || mdl.contains('s3') || 
        mdl.contains('fold') || mdl.contains('ultra'))) {
      return true;
    }
    
    // Google Pixel series (6+)
    if (mfg.contains('google') && mdl.contains('pixel')) {
      final match = RegExp(r'(\d+)').firstMatch(mdl);
      if (match != null) {
        final version = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (version >= 6) return true;
      }
    }
    
    // OnePlus flagship series
    if (mfg.contains('oneplus') && (mdl.contains('9') || mdl.contains('10') || mdl.contains('11'))) {
      return true;
    }
    
    // Xiaomi flagship series
    if (mfg.contains('xiaomi') && (mdl.contains('mi 11') || mdl.contains('mi 12') || 
        mdl.contains('mi 13') || mdl.contains('ultra'))) {
      return true;
    }
    
    return false;
  }
  
  /// Determine if device qualifies as a strong node
  bool isStrongNode(int score) {
    return score >= 70;
  }
  
  /// Determine role based on score
  String determineInitialRole(int score) {
    if (score >= 70) {
      return 'LEADER_CANDIDATE';
    } else if (score >= 40) {
      return 'CAPABLE_FOLLOWER';
    } else {
      return 'WEAK_NODE';
    }
  }
}

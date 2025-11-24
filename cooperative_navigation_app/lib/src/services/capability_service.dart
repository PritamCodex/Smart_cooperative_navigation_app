import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final capabilityServiceProvider = Provider<CapabilityService>((ref) {
  return CapabilityService();
});

class CapabilityService {
  int _score = 0;
  bool _isStrongNode = false;
  
  int get score => _score;
  bool get isStrongNode => _isStrongNode;
  
  Future<void> assessCapability() async {
    int tempScore = 0;
    
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      // 1. OS Version Score (Max 50)
      // Android 14 (API 34) or higher is preferred
      if (sdkInt >= 34) {
        tempScore += 50;
      } else if (sdkInt >= 33) { // Android 13
        tempScore += 30;
      } else {
        tempScore += 10;
      }
      
      // 2. Hardware/Performance Score (Max 30)
      // We use core count as a proxy for performance since we can't easily get CPU freq
      // Most modern strong phones have 8 cores
      final cores = Platform.numberOfProcessors;
      if (cores >= 8) {
        tempScore += 30;
      } else if (cores >= 6) {
        tempScore += 20;
      } else {
        tempScore += 10;
      }
      
      // 3. RAM Score (Proxy)
      // We can't get exact RAM easily in Flutter without native code, 
      // but we can infer from "isLowRamDevice" if available (requires native)
      // For now, we assume standard mid-tier
      tempScore += 20; 
    }
    
    _score = tempScore;
    
    // Threshold: 70
    // Android 14 (50) + 8 Cores (30) + Base (20) = 100 -> STRONG
    // Android 13 (30) + 8 Cores (30) + Base (20) = 80 -> STRONG
    // Android 12 (10) + 8 Cores (30) + Base (20) = 60 -> WEAK
    _isStrongNode = _score >= 70;
    
    print('Device Capability Assessment: Score=$_score, Role=${_isStrongNode ? "STRONG" : "WEAK"}');
  }
}

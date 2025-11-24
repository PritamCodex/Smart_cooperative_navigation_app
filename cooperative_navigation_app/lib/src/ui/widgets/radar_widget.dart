import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/core/models/collision_alert.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';
import 'package:cooperative_navigation_safety/src/core/config/feature_flags.dart';

import 'package:cooperative_navigation_safety/src/ui/widgets/glass_card.dart';

class RadarWidget extends ConsumerStatefulWidget {
  const RadarWidget({super.key});

  @override
  ConsumerState<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends ConsumerState<RadarWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(collisionAlertsProvider);
    final criticalAlert = ref.watch(criticalAlertProvider);
    
    return GlassCard(
      height: 300,
      padding: EdgeInsets.zero, // Radar needs full width
      child: Stack(
        children: [
          // Animated background rings
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: RadarPainter(
                    animationValue: _controller.value,
                    alerts: alerts,
                    criticalAlert: criticalAlert,
                  ),
                );
              },
            ),
          ),
          
          // Center user indicator
          Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.6),
                    blurRadius: 15,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          
          // Peer indicators
          ..._buildPeerIndicators(alerts),
          
          // Range indicators
          _buildRangeIndicators(),
        ],
      ),
    );
  }

  List<Widget> _buildPeerIndicators(List<CollisionAlert> alerts) {
    return alerts.map((alert) {
      // FIX: Use actual relative position instead of random angle
      // Scale: 50m radius = 120 pixels
      final scale = 120.0 / 50.0; 
      
      // lateralDelta is X (right positive), longitudinalDelta is Y (forward positive)
      // In screen coordinates: X is right, Y is down. So forward (Y) should be negative screen Y.
      final x = alert.lateralDelta * scale;
      final y = -alert.longitudinalDelta * scale;
      
      // Clamp to radar bounds to keep dots inside
      final dist = math.sqrt(x*x + y*y);
      double finalX = x;
      double finalY = y;
      
      if (dist > 120) {
        final ratio = 120 / dist;
        finalX = x * ratio;
        finalY = y * ratio;
      }
      
      return AnimatedPositioned(
        duration: FeatureFlags.FEATURE_INTERPOLATED_MOVEMENT 
            ? const Duration(milliseconds: 300) 
            : Duration.zero,
        curve: Curves.easeOut,
        left: 150 + finalX - 8, // Center (150) + offset - half_size
        top: 150 + finalY - 8,
        child: _buildPeerIndicator(alert),
      );
    }).toList();
  }

  Widget _buildPeerIndicator(CollisionAlert alert) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: alert.level.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: alert.level.color.withOpacity(0.8),
            blurRadius: 12,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildRangeIndicators() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RANGE: 50m',
            style: AppTheme.labelStyle.copyWith(color: AppTheme.textSecondary),
          ),
          Text(
            'UPD: 60 FPS',
            style: AppTheme.labelStyle.copyWith(color: AppTheme.accentColor),
          ),
        ],
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double animationValue;
  final List<CollisionAlert> alerts;
  final CollisionAlert? criticalAlert;

  RadarPainter({
    required this.animationValue,
    required this.alerts,
    this.criticalAlert,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw concentric circles (Nothing style: dotted or thin lines)
    for (int i = 1; i <= 4; i++) {
      paint.color = Colors.white.withOpacity(0.05);
      canvas.drawCircle(center, i * 30, paint);
    }

    // Draw cross lines
    paint.color = Colors.white.withOpacity(0.05);
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      paint,
    );

    // Draw rotating sweep line
    final sweepAngle = animationValue * 2 * math.pi;
    final sweepPaint = Paint()
      ..color = AppTheme.accentColor.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

    final sweepEnd = Offset(
      center.dx + math.cos(sweepAngle) * 120,
      center.dy + math.sin(sweepAngle) * 120,
    );
    canvas.drawLine(center, sweepEnd, sweepPaint);

    // Draw sweep gradient
    final gradientPaint = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [
          AppTheme.accentColor.withOpacity(0.2),
          AppTheme.accentColor.withOpacity(0.05),
          Colors.transparent,
        ],
        [0.0, 0.25, 0.5],
        TileMode.clamp,
        sweepAngle - math.pi / 2,
        sweepAngle,
      );

    canvas.drawCircle(center, 120, gradientPaint);

    // Draw critical alert overlay
    if (criticalAlert != null && criticalAlert!.level.isCritical) {
      final alertPaint = Paint()
        ..color = criticalAlert!.level.color.withOpacity(0.15)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      
      canvas.drawCircle(center, 140, alertPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
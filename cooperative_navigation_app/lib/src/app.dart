import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/ui/screens/main_screen.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';

class CooperativeNavigationApp extends ConsumerWidget {
  const CooperativeNavigationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Cooperative Navigation Safety',
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
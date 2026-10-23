import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();

    _goToMapWhenReady();
  }

  /// 스플래시가 떠 있는 동안 내 위치를 먼저 확인한다.
  /// 최소 2초는 보여주고, 위치가 늦으면 최대 8초까지 기다린 뒤 지도로 넘어간다.
  Future<void> _goToMapWhenReady() async {
    final minDisplay = Future.delayed(const Duration(milliseconds: 2000));
    final location = LocationService.getCurrentPosition()
        .timeout(const Duration(seconds: 8), onTimeout: () => null)
        .catchError((_) => null);

    final position = await location;
    await minDisplay;
    if (!mounted) return;

    final initial = position == null ? null : LatLng(position.latitude, position.longitude);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MapScreen(initialLocation: initial),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // FlatWay Logo Image
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: const Color(0xFF047857),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.navigation_rounded, size: 54, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // FlatWay Brand Title Text
              const Text(
                'FlatWay',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF047857),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '이동 약자 전용 안전 경로 지도 서비스',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF777777),
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              // Loading Progress Bar
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Color(0xFF047857),
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

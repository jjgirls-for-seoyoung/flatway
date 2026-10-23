import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  // Default fallback location (Jakjeon Station area in Incheon)
  static const LatLng defaultLocation = LatLng(37.5307, 126.7225);

  /// Check location service status
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check location permission status
  static Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  static Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Check location service and permissions, then return current LatLng position.
  /// Returns null if GPS is disabled or permissions are denied.
  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return null;
    }

    // 1. 마지막으로 알려진 위치가 있으면 즉시 사용 (웹은 이 기능을 지원하지 않아 건너뜀).
    //    여기서 실패해도 현재 위치 조회로 넘어가야 하므로 따로 감싼다.
    if (!kIsWeb) {
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) return lastPos;
      } catch (e) {
        debugPrint('Last known position unavailable: $e');
      }
    }

    // 2. 현재 위치를 직접 조회
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  /// Get real-time position stream
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // notify every 3 meters
      ),
    );
  }

  /// Get real-time heading stream for smooth compass map camera rotation
  static Stream<Position> getHeadingStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    );
  }

  /// Open device OS location settings (GPS toggle page)
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings page for location permission grant
  static Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}

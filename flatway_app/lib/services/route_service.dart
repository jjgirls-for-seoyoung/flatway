import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PedestrianRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isSuccess;

  PedestrianRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isSuccess,
  });
}

class RouteService {
  static const String _osrmFootUrl = 'https://router.project-osrm.org/route/v1/foot';

  // Fetch real pedestrian walking route following actual streets, sidewalks and crosswalks
  static Future<PedestrianRouteResult> fetchPedestrianRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(
        '$_osrmFootUrl/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;

          final List<LatLng> points = coordinates.map((coord) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          return PedestrianRouteResult(
            points: points,
            distanceMeters: distance,
            durationSeconds: duration,
            isSuccess: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching OSRM pedestrian route: $e');
    }

    // Fallback to straight line if offline/error
    return PedestrianRouteResult(
      points: [origin, destination],
      distanceMeters: const Distance().as(LengthUnit.Meter, origin, destination),
      durationSeconds: 300,
      isSuccess: false,
    );
  }
}

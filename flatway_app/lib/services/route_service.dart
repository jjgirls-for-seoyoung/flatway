import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteStep {
  final String instruction;
  final String modifier; // 'left', 'right', 'straight', etc.
  final double distanceMeters;
  final LatLng location;

  RouteStep({
    required this.instruction,
    required this.modifier,
    required this.distanceMeters,
    required this.location,
  });
}

class PedestrianRouteResult {
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double distanceMeters;
  final double durationSeconds;
  final bool isSuccess;

  PedestrianRouteResult({
    required this.points,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isSuccess,
  });
}

class RouteService {
  static const String _osrmFootUrl = 'https://router.project-osrm.org/route/v1/foot';

  // Fetch real pedestrian walking route following actual streets, sidewalks and crosswalks with step maneuvers
  static Future<PedestrianRouteResult> fetchPedestrianRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(
        '$_osrmFootUrl/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true',
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

          // Parse OSRM Maneuver Steps
          final List<RouteStep> parsedSteps = [];
          if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
            final leg = route['legs'][0];
            if (leg['steps'] != null) {
              for (final s in leg['steps']) {
                final stepDist = (s['distance'] as num).toDouble();
                final name = (s['name'] ?? '').toString();
                final maneuver = s['maneuver'] ?? {};
                final type = (maneuver['type'] ?? '').toString();
                final modifier = (maneuver['modifier'] ?? 'straight').toString();
                final locCoords = maneuver['location'] as List?;
                
                LatLng stepLoc = origin;
                if (locCoords != null && locCoords.length >= 2) {
                  stepLoc = LatLng((locCoords[1] as num).toDouble(), (locCoords[0] as num).toDouble());
                }

                String text = '';
                if (type == 'depart') {
                  text = '보행로를 따라 출발합니다.';
                } else if (type == 'arrive') {
                  text = '목적지에 도착합니다.';
                } else if (modifier == 'right' || modifier == 'sharp right' || modifier == 'slight right') {
                  text = '${stepDist.toStringAsFixed(0)}m 앞 우회전 ($name)';
                } else if (modifier == 'left' || modifier == 'sharp left' || modifier == 'slight left') {
                  text = '${stepDist.toStringAsFixed(0)}m 앞 좌회전 ($name)';
                } else {
                  text = '${stepDist.toStringAsFixed(0)}m 직진 ($name)';
                }

                parsedSteps.add(RouteStep(
                  instruction: text,
                  modifier: modifier,
                  distanceMeters: stepDist,
                  location: stepLoc,
                ));
              }
            }
          }

          return PedestrianRouteResult(
            points: points,
            steps: parsedSteps,
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
      steps: [
        RouteStep(instruction: '출발지', modifier: 'straight', distanceMeters: 0, location: origin),
        RouteStep(instruction: '목적지 도착', modifier: 'arrive', distanceMeters: 100, location: destination),
      ],
      distanceMeters: const Distance().as(LengthUnit.Meter, origin, destination),
      durationSeconds: 300,
      isSuccess: false,
    );
  }
}

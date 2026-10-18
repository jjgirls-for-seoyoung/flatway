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

  /// OSRM에서 경로를 받아온다. [via]를 주면 해당 지점을 순서대로 경유하고,
  /// [alternatives]가 true면 대안 경로까지 함께 돌려준다. 실패하면 빈 리스트.
  static Future<List<PedestrianRouteResult>> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> via = const [],
    bool alternatives = false,
  }) async {
    try {
      final coords = [origin, ...via, destination]
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final url = Uri.parse(
        '$_osrmFootUrl/$coords?overview=full&geometries=geojson&steps=true&alternatives=${alternatives ? 'true' : 'false'}',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final routes = data['routes'] as List?;
      if (routes == null) return [];

      return routes.map((r) => _parseRoute(r, origin)).toList();
    } catch (e) {
      debugPrint('Error fetching OSRM pedestrian route: $e');
      return [];
    }
  }

  static PedestrianRouteResult _parseRoute(dynamic route, LatLng origin) {
    final points = (route['geometry']['coordinates'] as List).map((coord) {
      return LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble());
    }).toList();

    // 경유지가 있으면 leg가 여러 개: 중간 leg의 도착/출발 안내는 건너뛴다.
    final steps = <RouteStep>[];
    final legs = (route['legs'] as List?) ?? const [];
    for (var li = 0; li < legs.length; li++) {
      final isFirstLeg = li == 0;
      final isLastLeg = li == legs.length - 1;
      for (final s in (legs[li]['steps'] as List?) ?? const []) {
        final maneuver = s['maneuver'] ?? {};
        final type = (maneuver['type'] ?? '').toString();
        if (type == 'depart' && !isFirstLeg) continue;
        if (type == 'arrive' && !isLastLeg) continue;

        final stepDist = (s['distance'] as num).toDouble();
        final name = (s['name'] ?? '').toString();
        final modifier = (maneuver['modifier'] ?? 'straight').toString();
        final locCoords = maneuver['location'] as List?;

        LatLng stepLoc = origin;
        if (locCoords != null && locCoords.length >= 2) {
          stepLoc = LatLng((locCoords[1] as num).toDouble(), (locCoords[0] as num).toDouble());
        }

        String text;
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

        steps.add(RouteStep(
          instruction: text,
          modifier: modifier,
          distanceMeters: stepDist,
          location: stepLoc,
        ));
      }
    }

    return PedestrianRouteResult(
      points: points,
      steps: steps,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      isSuccess: true,
    );
  }

  /// 단일 최단 보행 경로. 오프라인/오류 시 직선으로 대체한다.
  static Future<PedestrianRouteResult> fetchPedestrianRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final routes = await fetchRoutes(origin: origin, destination: destination);
    if (routes.isNotEmpty) return routes.first;
    return fallbackRoute(origin, destination);
  }

  static PedestrianRouteResult fallbackRoute(LatLng origin, LatLng destination) {
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

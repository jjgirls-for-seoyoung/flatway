import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'route_service.dart';

/// 현재 위치를 기준으로 계산한 길안내 상태.
class NavState {
  /// 다음에 수행할 안내 단계의 인덱스 (steps 기준). 단계가 없으면 0.
  final int nextStepIndex;

  /// 다음 안내 지점까지 남은 거리(m, 경로를 따라)
  final double metersToNextStep;

  /// 도착지까지 남은 거리(m, 경로를 따라)
  final double remainingMeters;

  /// 경로에서 떨어진 거리(m)
  final double offRouteMeters;

  /// 도착지에 거의 다 왔는지
  final bool arrived;

  const NavState({
    required this.nextStepIndex,
    required this.metersToNextStep,
    required this.remainingMeters,
    required this.offRouteMeters,
    required this.arrived,
  });
}

/// 경로(폴리라인)와 안내 단계로, 사용자의 현재 위치가 경로의 어디쯤인지 추적한다.
class NavTracker {
  static const double arrivalMeters = 25;

  final List<LatLng> points;
  final List<RouteStep> steps;

  late final List<double> _cum; // 각 꼭짓점까지의 누적 거리(m)
  late final List<double> _stepAlong; // 각 안내 단계가 경로상 몇 m 지점인지
  int _segHint = 0; // 직전에 있던 구간. 되돌아가며 엉뚱한 구간에 붙는 것을 막는다.

  NavTracker(this.points, this.steps) {
    const d = Distance();
    _cum = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      _cum[i] = _cum[i - 1] + d.as(LengthUnit.Meter, points[i - 1], points[i]);
    }

    // 각 단계의 위치를 경로상 가장 가까운 꼭짓점에 대응시킨다 (앞 단계보다 뒤에서만 찾는다).
    _stepAlong = [];
    var from = 0;
    for (final s in steps) {
      var best = from;
      var bestD = double.infinity;
      for (var i = from; i < points.length; i++) {
        final dist = d.as(LengthUnit.Meter, points[i], s.location);
        if (dist < bestD) {
          bestD = dist;
          best = i;
        }
      }
      _stepAlong.add(_cum[best]);
      from = best;
    }
  }

  double get totalMeters => _cum.isEmpty ? 0 : _cum.last;

  NavState update(LatLng user) {
    if (points.length < 2) {
      return const NavState(nextStepIndex: 0, metersToNextStep: 0, remainingMeters: 0, offRouteMeters: 0, arrived: true);
    }

    // 사용자를 가장 가까운 경로 구간에 투영한다.
    final mPerLat = 110540.0;
    final mPerLng = 111320.0 * cos(user.latitude * pi / 180);
    var bestDist = double.infinity;
    var bestSeg = _segHint;
    var bestAlong = 0.0;

    final start = max(0, _segHint - 3);
    for (var i = start; i < points.length - 1; i++) {
      final ax = (points[i].longitude - user.longitude) * mPerLng;
      final ay = (points[i].latitude - user.latitude) * mPerLat;
      final bx = (points[i + 1].longitude - user.longitude) * mPerLng;
      final by = (points[i + 1].latitude - user.latitude) * mPerLat;
      final abx = bx - ax, aby = by - ay;
      final len2 = abx * abx + aby * aby;
      final t = len2 == 0 ? 0.0 : ((-ax * abx - ay * aby) / len2).clamp(0.0, 1.0);
      final cx = ax + abx * t, cy = ay + aby * t;
      final dist = sqrt(cx * cx + cy * cy);
      if (dist < bestDist) {
        bestDist = dist;
        bestSeg = i;
        bestAlong = _cum[i] + (_cum[i + 1] - _cum[i]) * t;
      }
    }
    if (bestDist < 60) _segHint = bestSeg; // 경로 근처일 때만 위치를 갱신

    final remaining = max(0.0, totalMeters - bestAlong);

    var next = steps.length - 1;
    for (var k = 1; k < steps.length; k++) {
      if (_stepAlong[k] > bestAlong - 10) {
        next = k;
        break;
      }
    }
    if (next < 0) next = 0;
    final toNext = steps.isEmpty ? 0.0 : max(0.0, _stepAlong[next] - bestAlong);

    return NavState(
      nextStepIndex: next,
      metersToNextStep: toNext,
      remainingMeters: remaining,
      offRouteMeters: bestDist,
      arrived: remaining < arrivalMeters && bestDist < 60,
    );
  }
}

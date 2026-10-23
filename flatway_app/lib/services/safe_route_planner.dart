import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart';
import '../models/hazard_types.dart';
import 'route_service.dart';

/// 지도에 제보된 위험 요소 하나.
class RouteHazard {
  final LatLng point;
  final String type;
  final String severity; // 'high' | 'medium' | 'low'
  final double stepHeightCm;

  const RouteHazard({
    required this.point,
    required this.type,
    required this.severity,
    this.stepHeightCm = 0,
  });

  static RouteHazard? fromMap(Map<String, dynamic> h) {
    final lat = (h['latitude'] as num?)?.toDouble();
    final lng = (h['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return RouteHazard(
      point: LatLng(lat, lng),
      type: (h['type'] ?? '').toString(),
      severity: (h['severity'] ?? 'medium').toString(),
      stepHeightCm: (h['step_height_cm'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SafeRouteResult {
  /// 최종 선택된 경로
  final PedestrianRouteResult route;

  /// 최종 경로가 여전히 지나가는 위험 요소
  final List<RouteHazard> hazardsOnRoute;

  /// 최단 경로 대비 피한 위험 요소 수
  final int avoidedCount;

  /// 최단 경로 대비 늘어난 거리(m)
  final double detourMeters;

  /// 경로에 남은 위험 중, 이 이동 수단이 절대 지나면 안 되는데 피하지 못한 것의 수
  final int unavoidableHardCount;

  const SafeRouteResult({
    required this.route,
    required this.hazardsOnRoute,
    required this.avoidedCount,
    required this.detourMeters,
    this.unavoidableHardCount = 0,
  });
}

/// 위험 요소를 피하는 보행 경로 탐색.
///
/// 1. OSRM에서 최단 경로와 대안 경로를 후보로 받는다.
/// 2. 후보마다 `비용 = 거리(m) + 지나는 위험 요소의 페널티(m 환산)`을 계산한다.
/// 3. 가장 비싼 위험 요소의 좌우 80m·160m·260m 지점을 경유하는 우회 후보를 추가하고
///    다시 평가하는 과정을 몇 차례 반복한다.
/// 4. 비용이 가장 낮은 경로를 고른다. (우회가 위험 페널티보다 비싸면 우회하지 않는다)
///
/// 이동 수단별로 위험을 피하는 정도가 다르다.
/// - 보행자: 위험 요소를 거의 신경 쓰지 않는다(심각한 것만 약하게 피함).
/// - 전동휠체어: 단차는 절대 지나지 않는다(수동휠체어와 같은 엄격 회피). 파손·적치물은
///   잘 피하고, 경사는 덜 피한다.
/// - 수동휠체어: 위험 요소를 지나지 않는 경로를 우선한다. 아무리 멀리 돌아가더라도
///   위험이 없는 경로가 있으면 그것을 고르고, 우회로 자체가 없을 때만 위험이 남는다.
class SafeRoutePlanner {
  /// 경로와 이 거리 이내면 위험 요소를 "지나간다"고 본다.
  static const double hazardFullRadius = 15; // m, 이 안에서는 페널티 100%
  static const double hazardMaxRadius = 35; // m, 이 밖에서는 0%, 사이는 선형 감소
  // 우회 경유점의 옆 거리(m). 가까운 곳이 같은 도로로 붙어버리면 더 먼 곳을 시도한다.
  static const _detourOffsets = [80.0, 160.0, 260.0];

  // 이동 수단별 우회 탐색 횟수
  static const _maxRoundsByMode = {'pedestrian': 1, 'electric': 8, 'manual': 8};

  // 위험이 이 값(m 환산)보다 작으면 우회로 얻는 이득이 없어 우회 탐색을 건너뛴다(엄격 회피 제외)
  static const double _negligiblePenalty = 60;

  // 우회 경로는 최단 경로의 이 배수 + 여유 거리를 넘으면 쓰지 않는다. (절대 회피 모드라도
  // 몇 km씩 돌아가는 비현실적인 경로는 걸러낸다)
  static const double _maxDetourFactor = 2.5;
  static const double _maxDetourExtraMeters = 500;

  // 같은 길을 갔다가 되돌아오는 구간이 이 길이(m)를 넘으면 불필요한 곁길 왕복으로 보고 버린다.
  static const double _maxRetraceMeters = 40;

  // 수동휠체어: 경로에 위험 요소 1건이 있을 때마다 붙는 사실상 통과 불가 페널티(m 환산)
  static const double _hardBlockPenalty = 1000000;

  /// 이 이동 수단이 [type] 위험을 절대 지나면 안 되는지.
  /// 수동휠체어는 모든 위험, 전동휠체어는 단차만 해당한다.
  static bool isHardAvoid(String mode, String type) =>
      mode == 'manual' || (mode == 'electric' && type == 'step');

  // 출발/도착지에 이만큼 가까운 위험 요소는 우회로 피할 수 없으므로 우회 대상에서 제외
  static const double _unavoidableRadius = 40;

  // 위험 종류별 기본 페널티(m 환산)
  static const _basePenalty = {
    'step': 450.0,
    'damage': 250.0,
    'obstacle': 350.0,
    'slope': 300.0,
  };

  // 이동 수단별 종류 가중치. 휠체어일수록 단차·경사에 민감하다.
  static const _modeWeight = {
    'pedestrian': {'step': 0.1, 'damage': 0.1, 'obstacle': 0.15, 'slope': 0.05},
    'electric': {'step': 2.0, 'damage': 1.3, 'obstacle': 1.3, 'slope': 0.4},
    'manual': {'step': 3.0, 'damage': 1.6, 'obstacle': 1.3, 'slope': 2.5},
  };

  static const _severityWeight = {'high': 3.0, 'medium': 1.5, 'low': 0.7};

  /// 위험 요소 1건의 페널티(m 환산, 근접도 반영 전).
  static double hazardPenalty(RouteHazard h, String mode) {
    var base = _basePenalty[h.type] ?? 80.0;
    if (h.type == HazardType.step.key) base += h.stepHeightCm * 40; // 10cm 단차 = +400
    final modeW = (_modeWeight[mode] ?? _modeWeight['pedestrian']!)[h.type] ?? 1.0;
    final sevW = _severityWeight[h.severity] ?? 1.0;
    return base * modeW * sevW;
  }

  // 수동휠체어는 위험 요소 25m 안을 지나면 "통과"로 본다. (옆 도로에 있는 위험까지 막으면
  // 우회로가 없어지는 경우가 많다. 제보 위치 오차를 감안해 경로 위로 볼 수 있는 거리.)
  static const double _strictMaxRadius = 25;

  static double _proximityWeight(double distanceMeters, double maxRadius) {
    if (distanceMeters <= hazardFullRadius) return 1;
    if (distanceMeters >= maxRadius) return 0;
    return (maxRadius - distanceMeters) / (maxRadius - hazardFullRadius);
  }

  /// 경로가 지나는 위험 요소별 (근접도를 반영한 페널티, 가장 가까운 선분)
  static List<_Exposure> _exposures(List<LatLng> path, List<RouteHazard> hazards, String mode) {
    final result = <_Exposure>[];
    for (final h in hazards) {
      final hard = isHardAvoid(mode, h.type);
      final d = _distanceToPolyline(h.point, path);
      final w = _proximityWeight(d.distance, hard ? _strictMaxRadius : hazardMaxRadius);
      if (w > 0) {
        result.add(_Exposure(h, w * hazardPenalty(h, mode), d.segmentIndex, hard));
      }
    }
    return result;
  }

  /// [fetcher]로 경로 공급자를 바꿀 수 있다(테스트용). 기본은 OSRM.
  static Future<SafeRouteResult> plan({
    required LatLng origin,
    required LatLng destination,
    required List<RouteHazard> hazards,
    required String mode,
    Future<List<PedestrianRouteResult>> Function(List<LatLng> via, bool alternatives)? fetcher,
  }) async {
    final fetch = fetcher ??
        (via, alternatives) => RouteService.fetchRoutes(
              origin: origin,
              destination: destination,
              via: via,
              alternatives: alternatives,
            );

    const dist = Distance();
    bool nearEndpoint(LatLng p) =>
        dist.as(LengthUnit.Meter, p, origin) < _unavoidableRadius ||
        dist.as(LengthUnit.Meter, p, destination) < _unavoidableRadius;

    final candidates = <_Candidate>[];
    var maxAllowedDistance = double.infinity;
    void addAll(List<PedestrianRouteResult> routes, List<LatLng> vias) {
      for (final r in routes) {
        if (r.points.length < 2) continue;
        if (vias.isNotEmpty) {
          // 너무 멀리 돌거나, 곁길까지 갔다가 되돌아오는 우회 경로는 후보에서 제외
          if (r.distanceMeters > maxAllowedDistance) continue;
          if (retraceMeters(r.points) > _maxRetraceMeters) continue;
        }
        final exposures = _exposures(r.points, hazards, mode);
        var cost = r.distanceMeters + exposures.fold<double>(0, (a, e) => a + e.penalty);
        cost += _hardBlockPenalty * exposures.where((e) => e.hard).length;
        // 거리 차 5m 미만이고 지나는 위험 요소 수가 같으면 같은 경로로 본다.
        final dup = candidates.any((c) =>
            (c.route.distanceMeters - r.distanceMeters).abs() < 5 &&
            c.exposures.length == exposures.length);
        if (!dup) candidates.add(_Candidate(r, exposures, cost, vias));
      }
    }

    // 1) 최단 + 대안 경로
    addAll(await fetch(const [], true), const []);
    if (candidates.isEmpty) {
      return SafeRouteResult(
        route: RouteService.fallbackRoute(origin, destination),
        hazardsOnRoute: const [],
        avoidedCount: 0,
        detourMeters: 0,
      );
    }
    final baseline = candidates.first; // OSRM의 첫 경로 = 최단 경로
    maxAllowedDistance = baseline.route.distanceMeters * _maxDetourFactor + _maxDetourExtraMeters;

    // 2) 가장 비싼 위험 요소를 좌우로 비켜 가는 우회 후보 추가 반복
    final triedVia = <String>{};
    final maxRounds = _maxRoundsByMode[mode] ?? 3;
    for (var round = 0; round < maxRounds; round++) {
      final current = _best(candidates);
      if (current.exposures.isEmpty) break;
      final totalPenalty = current.exposures.fold<double>(0, (a, e) => a + e.penalty);
      if (!current.exposures.any((e) => e.hard) && totalPenalty < _negligiblePenalty) break;

      final avoidable = current.exposures.where((e) => !nearEndpoint(e.hazard.point)).toList();
      if (avoidable.isEmpty) break;
      // 절대 지나면 안 되는 위험이 있으면 그것부터 처리한다.
      final hardOnes = avoidable.where((e) => e.hard).toList();
      final targets = hardOnes.isNotEmpty ? hardOnes : avoidable;
      final worst = targets.reduce((a, b) => a.penalty >= b.penalty ? a : b);
      // 기존 경유지를 유지한 채 새 우회 경유점을 진행 순서에 맞게 끼워 넣는다.
      final fresh = <List<LatLng>>[];
      for (final v in _detourPoints(current.route.points, worst)) {
        final combined = _insertInOrder(current.vias, v, current.route.points);
        final key = combined.map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}').join('|');
        if (triedVia.add(key)) fresh.add(combined);
      }
      if (fresh.isEmpty) break;

      final before = candidates.length;
      final responses = await Future.wait(fresh.map((vias) => fetch(vias, false)));
      for (var i = 0; i < responses.length; i++) {
        addAll(responses[i], fresh[i]);
      }
      if (candidates.length == before) break;
    }

    // 3) 가지치기: 최종 후보의 경유지 중 빼도 위험이 늘지 않는 것은 빼서 불필요한 우회를 줄인다.
    for (var pass = 0; pass < 2; pass++) {
      final current = _best(candidates);
      if (current.vias.isEmpty) break;
      final trials = <List<LatLng>>[];
      for (var i = 0; i < current.vias.length; i++) {
        final trial = [...current.vias]..removeAt(i);
        final key = trial.map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}').join('|');
        if (triedVia.add(key)) trials.add(trial);
      }
      if (trials.isEmpty) break;
      final before = candidates.length;
      final responses = await Future.wait(trials.map((vias) => fetch(vias, false)));
      for (var i = 0; i < responses.length; i++) {
        addAll(responses[i], trials[i]);
      }
      if (candidates.length == before) break;
    }

    final best = _best(candidates);
    final baselineSet = baseline.exposures.map((e) => e.hazard).toSet();
    final bestSet = best.exposures.map((e) => e.hazard).toSet();

    return SafeRouteResult(
      route: best.route,
      hazardsOnRoute: bestSet.toList(),
      avoidedCount: baselineSet.difference(bestSet).length,
      detourMeters: max(0, best.route.distanceMeters - baseline.route.distanceMeters),
      unavoidableHardCount: best.exposures.where((e) => e.hard).length,
    );
  }

  /// 경로가 같은 길을 되돌아가는(왕복) 총 길이(m)의 근사값.
  /// 8m 간격으로 경로를 샘플링해, 경로상 64m 이상 떨어진 뒤에 같은 자리(5m 이내)를 다시 지나는 점을 센다.
  @visibleForTesting
  static double retraceMeters(List<LatLng> path) {
    const step = 8.0;
    const minGapSamples = 8; // 64m
    final proj = _Projector(path.first);
    final samples = <_XY>[];
    var carry = 0.0;
    var prev = proj.toXY(path.first);
    samples.add(prev);
    for (var i = 1; i < path.length; i++) {
      final cur = proj.toXY(path[i]);
      var segLen = sqrt(pow(cur.dx - prev.dx, 2) + pow(cur.dy - prev.dy, 2));
      var from = prev;
      while (carry + segLen >= step) {
        final t = (step - carry) / segLen;
        from = _XY(from.dx + (cur.dx - from.dx) * t, from.dy + (cur.dy - from.dy) * t);
        samples.add(from);
        segLen = sqrt(pow(cur.dx - from.dx, 2) + pow(cur.dy - from.dy, 2));
        carry = 0;
      }
      carry += segLen;
      prev = cur;
    }

    var revisits = 0;
    for (var i = 0; i < samples.length; i++) {
      for (var j = i + minGapSamples; j < samples.length; j++) {
        final dx = samples[i].dx - samples[j].dx, dy = samples[i].dy - samples[j].dy;
        if (dx * dx + dy * dy < 25) {
          revisits++;
          break;
        }
      }
    }
    return revisits * step;
  }

  static _Candidate _best(List<_Candidate> list) =>
      list.reduce((a, b) => a.cost <= b.cost ? a : b);

  /// [vias]에 [v]를 [path] 진행 방향 순서대로 끼워 넣은 새 리스트.
  static List<LatLng> _insertInOrder(List<LatLng> vias, LatLng v, List<LatLng> path) {
    final idx = _distanceToPolyline(v, path).segmentIndex;
    final result = [...vias];
    var pos = result.length;
    for (var i = 0; i < result.length; i++) {
      if (_distanceToPolyline(result[i], path).segmentIndex > idx) {
        pos = i;
        break;
      }
    }
    result.insert(pos, v);
    return result;
  }

  /// 위험 요소가 놓인 구간의 진행 방향에 수직으로 좌/우 [_detourOffsets]m 떨어진 지점들.
  static List<LatLng> _detourPoints(List<LatLng> path, _Exposure e) {
    final i = e.segmentIndex.clamp(0, path.length - 2);
    final proj = _Projector(e.hazard.point);
    final a = proj.toXY(path[i]);
    final b = proj.toXY(path[i + 1]);
    var dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 0.01) return const [];
    dx /= len;
    dy /= len;
    // 수직 방향 (-dy, dx) 과 그 반대
    return [
      for (final off in _detourOffsets) ...[
        proj.toLatLng(_XY(-dy * off, dx * off)),
        proj.toLatLng(_XY(dy * off, -dx * off)),
      ],
    ];
  }

  /// 점에서 폴리라인까지의 최소 거리(m)와 가장 가까운 선분 인덱스.
  static _PolyDistance _distanceToPolyline(LatLng p, List<LatLng> path) {
    final proj = _Projector(p);
    var bestD = double.infinity;
    var bestI = 0;
    var prev = proj.toXY(path.first);
    for (var i = 0; i < path.length - 1; i++) {
      final next = proj.toXY(path[i + 1]);
      final d = _originToSegment(prev, next);
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
      prev = next;
    }
    return _PolyDistance(bestD, bestI);
  }

  /// 원점(0,0)에서 선분 a-b까지의 거리.
  static double _originToSegment(_XY a, _XY b) {
    final abx = b.dx - a.dx, aby = b.dy - a.dy;
    final len2 = abx * abx + aby * aby;
    var t = len2 == 0 ? 0.0 : (-a.dx * abx - a.dy * aby) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = a.dx + abx * t, cy = a.dy + aby * t;
    return sqrt(cx * cx + cy * cy);
  }
}

class _Candidate {
  final PedestrianRouteResult route;
  final List<_Exposure> exposures;
  final double cost;
  final List<LatLng> vias; // 이 경로가 거치는 우회 경유지
  _Candidate(this.route, this.exposures, this.cost, this.vias);
}

class _Exposure {
  final RouteHazard hazard;
  final double penalty;
  final int segmentIndex;
  final bool hard; // 이 이동 수단이 절대 지나면 안 되는 위험인지
  _Exposure(this.hazard, this.penalty, this.segmentIndex, this.hard);
}

class _PolyDistance {
  final double distance;
  final int segmentIndex;
  _PolyDistance(this.distance, this.segmentIndex);
}

class _XY {
  final double dx, dy;
  const _XY(this.dx, this.dy);
}

/// 기준점을 원점으로 하는 간이 평면 투영(미터). 도시 규모 거리에서는 충분히 정확하다.
class _Projector {
  final LatLng origin;
  final double _mPerLng;
  static const _mPerLat = 110540.0;

  _Projector(this.origin) : _mPerLng = 111320.0 * cos(origin.latitude * pi / 180);

  _XY toXY(LatLng p) => _XY(
        (p.longitude - origin.longitude) * _mPerLng,
        (p.latitude - origin.latitude) * _mPerLat,
      );

  LatLng toLatLng(_XY o) => LatLng(
        origin.latitude + o.dy / _mPerLat,
        origin.longitude + o.dx / _mPerLng,
      );
}

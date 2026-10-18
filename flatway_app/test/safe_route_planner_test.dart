import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flatway_app/services/route_service.dart';
import 'package:flatway_app/services/safe_route_planner.dart';

const _dist = Distance();

PedestrianRouteResult _route(List<LatLng> pts) {
  var d = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    d += _dist.as(LengthUnit.Meter, pts[i], pts[i + 1]);
  }
  return PedestrianRouteResult(
    points: pts,
    steps: const [],
    distanceMeters: d,
    durationSeconds: d / 1.2,
    isSuccess: true,
  );
}

// 동쪽으로 약 800m 직선 경로. 경유점이 있으면 그 점을 지나 돌아간다.
final _origin = const LatLng(37.5300, 126.7200);
final _dest = const LatLng(37.5300, 126.7290);

Future<List<PedestrianRouteResult>> _fakeFetcher(List<LatLng> via, bool alternatives) async {
  return [_route([_origin, ...via, _dest])];
}

RouteHazard _hazardOnPath({String type = 'step', String severity = 'high', double height = 10}) {
  return RouteHazard(
    point: const LatLng(37.5300, 126.7245), // 직선 경로 한가운데
    type: type,
    severity: severity,
    stepHeightCm: height,
  );
}

void main() {
  test('위험 요소가 없으면 최단 경로를 그대로 쓴다', () async {
    final r = await SafeRoutePlanner.plan(
      origin: _origin,
      destination: _dest,
      hazards: const [],
      mode: 'manual',
      fetcher: _fakeFetcher,
    );
    expect(r.avoidedCount, 0);
    expect(r.detourMeters, 0);
    expect(r.hazardsOnRoute, isEmpty);
  });

  test('수동휠체어는 큰 단차를 우회한다', () async {
    final r = await SafeRoutePlanner.plan(
      origin: _origin,
      destination: _dest,
      hazards: [_hazardOnPath()],
      mode: 'manual',
      fetcher: _fakeFetcher,
    );
    expect(r.avoidedCount, 1);
    expect(r.hazardsOnRoute, isEmpty);
    expect(r.detourMeters, greaterThan(0));
  });

  test('우회 비용이 위험 페널티보다 크면 우회하지 않는다', () async {
    // 보행자 + 낮은 심각도 파손(페널티 약 20m)인데 우회로가 800m 이상 더 길다
    Future<List<PedestrianRouteResult>> longDetour(List<LatLng> via, bool alt) async {
      if (via.isEmpty) return [_route([_origin, _dest])];
      return [_route([_origin, const LatLng(37.5340, 126.7245), _dest])];
    }

    final r = await SafeRoutePlanner.plan(
      origin: _origin,
      destination: _dest,
      hazards: [_hazardOnPath(type: 'damage', severity: 'low')],
      mode: 'pedestrian',
      fetcher: longDetour,
    );
    expect(r.avoidedCount, 0);
    expect(r.hazardsOnRoute, hasLength(1));
    expect(r.detourMeters, 0);
  });

  test('이동 수단에 따라 같은 단차의 페널티가 달라진다', () {
    final h = _hazardOnPath();
    final ped = SafeRoutePlanner.hazardPenalty(h, 'pedestrian');
    final manual = SafeRoutePlanner.hazardPenalty(h, 'manual');
    expect(manual, greaterThan(ped));
  });

  test('경로에서 멀리 떨어진 위험 요소는 무시한다', () async {
    final far = RouteHazard(
      point: const LatLng(37.5340, 126.7245), // 약 440m 북쪽
      type: 'step',
      severity: 'high',
      stepHeightCm: 15,
    );
    final r = await SafeRoutePlanner.plan(
      origin: _origin,
      destination: _dest,
      hazards: [far],
      mode: 'manual',
      fetcher: _fakeFetcher,
    );
    expect(r.hazardsOnRoute, isEmpty);
    expect(r.detourMeters, 0);
  });
}

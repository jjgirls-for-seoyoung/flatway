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
    // 보행자 + 낮은 심각도 파손(페널티 약 20m)인데 우회로가 약 400m 더 길다
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

  group('이동 수단별 회피 강도', () {
    // 경유점이 있으면 약 400m 더 긴 우회로, 없으면 직선
    Future<List<PedestrianRouteResult>> longDetour(List<LatLng> via, bool alt) async {
      if (via.isEmpty) return [_route([_origin, _dest])];
      return [_route([_origin, const LatLng(37.5340, 126.7245), _dest])];
    }

    test('보행자는 중간 정도 위험 때문에 멀리 돌아가지 않는다', () async {
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'damage', severity: 'medium')],
        mode: 'pedestrian',
        fetcher: longDetour,
      );
      expect(r.detourMeters, 0);
      expect(r.hazardsOnRoute, hasLength(1));
    });

    test('수동휠체어는 위험이 있으면 아무리 멀어도 위험 없는 경로를 고른다', () async {
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'damage', severity: 'low')],
        mode: 'manual',
        fetcher: longDetour,
      );
      expect(r.hazardsOnRoute, isEmpty);
      expect(r.detourMeters, greaterThan(300));
    });

    test('전동휠체어는 단차는 아무리 멀어도 피하고, 경사는 멀리 돌아가면서까지 피하지 않는다', () async {
      final step = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'step', severity: 'low', height: 3)],
        mode: 'electric',
        fetcher: longDetour,
      );
      expect(step.hazardsOnRoute, isEmpty);
      expect(step.detourMeters, greaterThan(300));

      final slope = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'slope', severity: 'low')],
        mode: 'electric',
        fetcher: longDetour,
      );
      expect(slope.detourMeters, 0);
      expect(slope.unavoidableHardCount, 0);
    });

    test('전동휠체어: 피할 길이 없는 단차는 unavoidableHardCount로 알려 준다', () async {
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'step')],
        mode: 'electric',
        fetcher: (via, alt) async => [_route([_origin, _dest])], // 우회로 없음
      );
      expect(r.unavoidableHardCount, 1);
    });

    test('전동휠체어는 같은 경사를 수동휠체어보다 덜 피한다', () {
      final slope = _hazardOnPath(type: 'slope', severity: 'medium');
      expect(
        SafeRoutePlanner.hazardPenalty(slope, 'electric'),
        lessThan(SafeRoutePlanner.hazardPenalty(slope, 'manual')),
      );
      final step = _hazardOnPath();
      expect(
        SafeRoutePlanner.hazardPenalty(step, 'pedestrian'),
        lessThan(SafeRoutePlanner.hazardPenalty(step, 'electric')),
      );
    });

    test('수동휠체어는 서로 다른 위치의 위험 2건을 경유지를 합쳐 모두 피한다', () async {
      final h1 = RouteHazard(point: const LatLng(37.5300, 126.7230), type: 'step', severity: 'high', stepHeightCm: 10);
      final h2 = RouteHazard(point: const LatLng(37.5300, 126.7260), type: 'damage', severity: 'high');
      // 경유점들을 순서대로 지나가는 경로
      Future<List<PedestrianRouteResult>> viaRoute(List<LatLng> via, bool alt) async {
        return [_route([_origin, ...via, _dest])];
      }

      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [h1, h2],
        mode: 'manual',
        fetcher: viaRoute,
      );
      expect(r.hazardsOnRoute, isEmpty);
      expect(r.avoidedCount, 2);
    });
  });
}

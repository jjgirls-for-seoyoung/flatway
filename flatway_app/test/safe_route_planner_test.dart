import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flatway_app/services/mobility_profile.dart';
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

    test('수동휠체어는 중간 이상의 파손이 있으면 돌아가서 피한다', () async {
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'damage', severity: 'medium')],
        mode: 'manual',
        fetcher: longDetour,
      );
      expect(r.hazardsOnRoute, isEmpty);
      expect(r.detourMeters, greaterThan(300));
    });

    test('수동휠체어도 경미한 파손 때문에 멀리 돌아가지는 않는다', () async {
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath(type: 'damage', severity: 'low')],
        mode: 'manual',
        fetcher: longDetour,
      );
      expect(r.detourMeters, 0);
      expect(r.unavoidableHardCount, 0);
    });

    test('단차 높이 기준: 수동 1.3cm, 전동 2cm를 넘으면 통과 불가로 본다', () async {
      // 우회로가 없을 때, 통과 불가(절대 회피) 위험이 남았는지로 기준을 확인한다.
      Future<int> blocked(String mode, double cm) async {
        final r = await SafeRoutePlanner.plan(
          origin: _origin,
          destination: _dest,
          hazards: [_hazardOnPath(type: 'step', severity: 'medium', height: cm)],
          mode: mode,
          fetcher: (via, alt) async => [_route([_origin, _dest])],
        );
        return r.unavoidableHardCount;
      }

      expect(await blocked('manual', 1.0), 0);
      expect(await blocked('manual', 1.5), 1);
      expect(await blocked('electric', 1.5), 0);
      expect(await blocked('electric', 3.0), 1);
      expect(await blocked('pedestrian', 10), 0);
    });

    test('길을 막는 적치물은 두 휠체어 모두 피하고, 가파른 경사는 수동만 절대 피한다', () {
      final obstacle = _hazardOnPath(type: 'obstacle', severity: 'medium');
      expect(MobilityProfile.electric.isHard(obstacle), isTrue);
      expect(MobilityProfile.manual.isHard(obstacle), isTrue);
      expect(MobilityProfile.pedestrian.isHard(obstacle), isFalse);

      final steepSlope = _hazardOnPath(type: 'slope', severity: 'high');
      expect(MobilityProfile.manual.isHard(steepSlope), isTrue);
      expect(MobilityProfile.electric.isHard(steepSlope), isFalse);
    });

    test('우회 허용 거리는 전동휠체어가 수동휠체어보다 길다', () async {
      // 800m 직선 대신 약 2.2km를 도는 우회로만 있다(수동 한도 2.0km, 전동 한도 2.5km).
      Future<List<PedestrianRouteResult>> farDetour(List<LatLng> via, bool alt) async {
        if (via.isEmpty) return [_route([_origin, _dest])];
        return [_route([_origin, const LatLng(37.5392, 126.7245), _dest])];
      }

      Future<SafeRouteResult> run(String mode) => SafeRoutePlanner.plan(
            origin: _origin,
            destination: _dest,
            hazards: [_hazardOnPath(type: 'step', severity: 'high', height: 5)],
            mode: mode,
            fetcher: farDetour,
          );

      final electric = await run('electric');
      expect(electric.hazardsOnRoute, isEmpty);
      final manual = await run('manual');
      expect(manual.unavoidableHardCount, 1); // 너무 멀어서 우회하지 못한다
    });

    test('예상 속도는 전동 > 보행자 > 수동 순서다', () {
      expect(MobilityProfile.electric.speedKmh, greaterThan(MobilityProfile.pedestrian.speedKmh));
      expect(MobilityProfile.pedestrian.speedKmh, greaterThan(MobilityProfile.manual.speedKmh));
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

  group('불필요한 우회 방지', () {
    test('같은 길을 갔다 되돌아오는 경로는 왕복으로 감지한다', () {
      const a = LatLng(37.5300, 126.7200);
      const out = LatLng(37.5300, 126.7260); // 약 530m 동쪽
      const b = LatLng(37.5300, 126.7200);
      expect(SafeRoutePlanner.retraceMeters([a, out, b]), greaterThan(300));
      expect(SafeRoutePlanner.retraceMeters([a, out]), lessThan(20));
    });

    test('수동휠체어라도 곁길을 왕복하는 우회는 쓰지 않는다', () async {
      // 경유점이 있으면 위험을 비켜 곁길 끝까지 갔다 되돌아오는 경로가 나온다
      Future<List<PedestrianRouteResult>> spur(List<LatLng> via, bool alt) async {
        if (via.isEmpty) return [_route([_origin, _dest])];
        return [_route([_origin, const LatLng(37.5300, 126.7230), via.first, const LatLng(37.5300, 126.7230), _dest])];
      }

      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath()],
        mode: 'manual',
        fetcher: spur,
      );
      expect(r.detourMeters, 0); // 왕복 우회는 버리고 최단 경로 유지
      expect(r.unavoidableHardCount, 1);
    });

    test('최단 경로의 2.5배를 넘게 돌아가는 우회는 쓰지 않는다', () async {
      Future<List<PedestrianRouteResult>> huge(List<LatLng> via, bool alt) async {
        if (via.isEmpty) return [_route([_origin, _dest])];
        // 위로 크게 돌아가는 경로(총 약 4.5km)
        return [_route([_origin, const LatLng(37.5700, 126.7245), _dest])];
      }

      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [_hazardOnPath()],
        mode: 'manual',
        fetcher: huge,
      );
      expect(r.detourMeters, 0);
    });
  });

  group('경로 선택 오류 방지', () {
    const midLng = 126.7245;

    test('더 길게 돌아가는데 지나는 위험 수가 줄지 않으면 짧은 경로를 쓴다', () async {
      // 위험(수동 기준 통과 불가인 높은 단차)이 직선 한가운데에 있다.
      final hazard = RouteHazard(point: const LatLng(37.5300, midLng), type: 'step', severity: 'high', stepHeightCm: 10);
      // 우회로는 위험 옆 약 20m를 지나지만(25m 안이라 여전히 지나가는 것) 양 끝에서 더 돌아간다.
      const wiggle = [
        LatLng(37.5306, 126.7215),
        LatLng(37.53018, midLng), // 위험에서 북쪽으로 약 20m
        LatLng(37.5306, 126.7275),
      ];
      Future<List<PedestrianRouteResult>> fetcher(List<LatLng> via, bool alt) async {
        if (via.isEmpty) return [_route([_origin, _dest])];
        return [_route([_origin, ...wiggle, _dest])];
      }

      final r = await SafeRoutePlanner.plan(origin: _origin, destination: _dest, hazards: [hazard], mode: 'manual', fetcher: fetcher);
      // 위험 1건은 어느 쪽으로 가도 지나가므로 돌아가는 값을 치를 이유가 없다.
      expect(r.detourMeters, 0);
      expect(r.hazardsOnRoute, hasLength(1));
    });

    test('위험이 25m보다 멀면 어떤 이동 수단에서도 경로 위 위험으로 세지 않는다', () async {
      // 직선 경로에서 북쪽으로 약 30m 떨어진 위험
      final far = RouteHazard(point: const LatLng(37.53027, midLng), type: 'step', severity: 'high', stepHeightCm: 10);
      for (final mode in ['pedestrian', 'electric', 'manual']) {
        final r = await SafeRoutePlanner.plan(origin: _origin, destination: _dest, hazards: [far], mode: mode, fetcher: _fakeFetcher);
        expect(r.hazardsOnRoute, isEmpty, reason: mode);
      }
    });

    test('같은 경로면 이동 수단이 달라도 지나는 위험 개수가 같다 (위험 판정 거리 통일)', () async {
      // 경로에서 약 28m 떨어진 위험: 예전에는 보행자만 35m 기준으로 1건으로 셌다.
      final h = RouteHazard(point: const LatLng(37.53025, midLng), type: 'damage', severity: 'low');
      final counts = <int>[];
      for (final mode in ['pedestrian', 'electric', 'manual']) {
        final r = await SafeRoutePlanner.plan(origin: _origin, destination: _dest, hazards: [h], mode: mode, fetcher: _fakeFetcher);
        counts.add(r.hazardsOnRoute.length);
      }
      expect(counts.toSet(), hasLength(1));
    });

    test('돌아가서 피한 통과 불가 위험 수를 알려 준다 (왜 돌아갔는지 설명용)', () async {
      final blocked = _hazardOnPath(type: 'step', severity: 'high', height: 10);
      Future<List<PedestrianRouteResult>> fetcher(List<LatLng> via, bool alt) async {
        if (via.isEmpty) return [_route([_origin, _dest])];
        return [_route([_origin, const LatLng(37.5340, 126.7245), _dest])]; // 위험에서 멀리 돌아가는 길
      }

      final r = await SafeRoutePlanner.plan(origin: _origin, destination: _dest, hazards: [blocked], mode: 'manual', fetcher: fetcher);
      expect(r.detourMeters, greaterThan(300));
      expect(r.avoidedImpassableCount, 1);
      expect(r.impassableOnRoute, isEmpty);

      // 같은 위험이라도 보행자에게는 통과 불가가 아니므로 돌아가지 않고, 피한 통과 불가도 0이다.
      final ped = await SafeRoutePlanner.plan(origin: _origin, destination: _dest, hazards: [blocked], mode: 'pedestrian', fetcher: fetcher);
      expect(ped.detourMeters, 0);
      expect(ped.avoidedImpassableCount, 0);
    });

    test('남은 위험을 통과 불가와 주의로 나눠서 알려 준다', () async {
      final blocked = _hazardOnPath(type: 'step', severity: 'high', height: 10); // 수동 기준 통과 불가
      final caution = RouteHazard(point: const LatLng(37.5300, 126.7270), type: 'slope', severity: 'low'); // 수동도 지나갈 수 있음
      final r = await SafeRoutePlanner.plan(
        origin: _origin,
        destination: _dest,
        hazards: [blocked, caution],
        mode: 'manual',
        fetcher: (via, alt) async => [_route([_origin, _dest])], // 우회로 없음
      );
      expect(r.hazardsOnRoute, hasLength(2));
      expect(r.impassableOnRoute, hasLength(1));
      expect(r.impassableOnRoute.single.type, 'step');
      expect(r.cautionOnRoute, hasLength(1));
      expect(r.cautionOnRoute.single.type, 'slope');
      expect(r.unavoidableHardCount, r.impassableOnRoute.length);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flatway_app/services/nav_tracker.dart';
import 'package:flatway_app/services/route_service.dart';

// 동쪽으로 1km 직진 후(경도 방향) 북쪽으로 500m 꺾이는 ㄱ자 경로
const _a = LatLng(37.5300, 126.7200);
const _b = LatLng(37.5300, 126.7312); // 약 1km 동쪽
const _c = LatLng(37.5345, 126.7312); // 약 500m 북쪽

List<LatLng> _pts() {
  // 약 100m 간격으로 점을 촘촘히 만든다
  final pts = <LatLng>[_a];
  for (var i = 1; i <= 10; i++) {
    pts.add(LatLng(_a.latitude, _a.longitude + (_b.longitude - _a.longitude) * i / 10));
  }
  for (var i = 1; i <= 5; i++) {
    pts.add(LatLng(_b.latitude + (_c.latitude - _b.latitude) * i / 5, _b.longitude));
  }
  return pts;
}

List<RouteStep> _steps() => [
      RouteStep(instruction: '출발', modifier: 'straight', distanceMeters: 1000, location: _a, type: 'depart'),
      RouteStep(instruction: '좌회전', modifier: 'left', distanceMeters: 500, location: _b, type: 'turn', name: '계양대로'),
      RouteStep(instruction: '도착', modifier: 'straight', distanceMeters: 0, location: _c, type: 'arrive'),
    ];

void main() {
  test('출발 직후: 다음 안내는 1km 앞 좌회전, 남은 거리는 약 1.5km', () {
    final t = NavTracker(_pts(), _steps());
    final s = t.update(_a);
    expect(s.nextStepIndex, 1);
    expect(s.metersToNextStep, closeTo(1000, 40));
    expect(s.remainingMeters, closeTo(1500, 60));
    expect(s.offRouteMeters, lessThan(5));
    expect(s.arrived, isFalse);
  });

  test('걸어가면 다음 안내까지 거리와 남은 거리가 줄어든다', () {
    final t = NavTracker(_pts(), _steps());
    final mid = LatLng(_a.latitude, _a.longitude + (_b.longitude - _a.longitude) * 0.6);
    final s = t.update(mid);
    expect(s.nextStepIndex, 1);
    expect(s.metersToNextStep, closeTo(400, 40));
    expect(s.remainingMeters, closeTo(900, 60));
  });

  test('회전 지점을 지나면 다음 안내가 도착으로 넘어간다', () {
    final t = NavTracker(_pts(), _steps());
    t.update(_a);
    final past = LatLng(_b.latitude + 0.001, _b.longitude); // 회전 후 약 110m
    final s = t.update(past);
    expect(s.nextStepIndex, 2);
    expect(s.metersToNextStep, closeTo(390, 40));
  });

  test('도착지 근처면 도착으로 판단한다', () {
    final t = NavTracker(_pts(), _steps());
    final s = t.update(const LatLng(37.53445, 126.7312));
    expect(s.arrived, isTrue);
  });

  test('경로에서 멀리 떨어지면 이탈 거리가 크게 나온다', () {
    final t = NavTracker(_pts(), _steps());
    final s = t.update(const LatLng(37.5340, 126.7240)); // 경로에서 약 440m 북쪽
    expect(s.offRouteMeters, greaterThan(300));
    expect(s.arrived, isFalse);
  });

  test('maneuverLabel: 회전 방향을 한국어로 바꾼다', () {
    expect(maneuverLabel('turn', 'right'), '우회전');
    expect(maneuverLabel('turn', 'left'), '좌회전');
    expect(maneuverLabel('turn', 'uturn'), '유턴');
    expect(maneuverLabel('arrive', 'straight'), '목적지 도착');
    expect(maneuverLabel('roundabout', 'right'), '회전교차로 진입');
    expect(maneuverLabel('new name', 'straight'), '직진');
  });
}

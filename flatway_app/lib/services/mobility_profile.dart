import 'safe_route_planner.dart' show RouteHazard;

/// 이동 수단(보행자·전동휠체어·수동휠체어)별 길찾기 기준.
///
/// 근거와 가정은 `docs/이동수단별_경로_기준.md`에 정리했다.
/// 제보 데이터에는 경사도(%) 값이 없어서 경사는 제보의 심각도(severity)를 대신 쓴다.
/// - low: 완만(약 1/18 이하), medium: 1/18~1/12, high: 1/12보다 가파름
class MobilityProfile {
  final String mode;
  final String label;

  /// 예상 소요 시간 계산에 쓰는 평균 속도(km/h)
  final double speedKmh;

  /// 이 높이(cm)를 넘는 단차는 지나갈 수 없다고 본다. null이면 단차를 장애로 보지 않는다(보행자).
  /// 높이를 모르는 단차는 심각도가 low가 아니면 지나갈 수 없다고 본다.
  final double? stepPassMaxCm;

  /// 이 심각도 이상이면 절대 지나지 않는 위험(종류별). 여기 없으면 페널티만 준다.
  final Set<String> hardDamage;
  final Set<String> hardObstacle;
  final Set<String> hardSlope;

  /// 우회 경로는 최단 경로의 [maxDetourFactor]배 + [maxDetourExtraMeters]m를 넘으면 쓰지 않는다.
  final double maxDetourFactor;
  final double maxDetourExtraMeters;

  /// 우회 탐색 반복 횟수
  final int maxRounds;

  /// 종류별 페널티 가중치(클수록 더 피한다)
  final Map<String, double> weights;

  const MobilityProfile({
    required this.mode,
    required this.label,
    required this.speedKmh,
    required this.stepPassMaxCm,
    this.hardDamage = const {},
    this.hardObstacle = const {},
    this.hardSlope = const {},
    required this.maxDetourFactor,
    required this.maxDetourExtraMeters,
    required this.maxRounds,
    required this.weights,
  });

  /// 보행자: 위험 제보를 참고만 한다. 심각한 것만 약하게 피한다.
  static const pedestrian = MobilityProfile(
    mode: 'pedestrian',
    label: '보행자',
    speedKmh: 4.0,
    stepPassMaxCm: null,
    maxDetourFactor: 2.5,
    maxDetourExtraMeters: 500,
    maxRounds: 1,
    weights: {'step': 0.1, 'damage': 0.1, 'obstacle': 0.15, 'slope': 0.05},
  );

  /// 전동휠체어: 속도가 빠르고 힘이 들지 않아 더 돌아가도 되고 완만한 경사는 괜찮다.
  /// 대신 단차는 2cm까지만 넘고, 심한 파손과 길을 막는 적치물은 지나지 않는다.
  static const electric = MobilityProfile(
    mode: 'electric',
    label: '전동휠체어',
    speedKmh: 4.5,
    stepPassMaxCm: 2.0,
    hardDamage: {'high'},
    hardObstacle: {'medium', 'high'},
    hardSlope: {},
    maxDetourFactor: 2.5,
    maxDetourExtraMeters: 500,
    maxRounds: 8,
    weights: {'step': 2.0, 'damage': 1.3, 'obstacle': 1.3, 'slope': 0.4},
  );

  /// 수동휠체어: 단차는 1.3cm까지만 넘고, 팔 힘으로 가야 하므로 가파른 경사와 파손을 피하며,
  /// 너무 멀리 돌아가면 체력이 들어서 우회 허용 거리는 더 짧다.
  static const manual = MobilityProfile(
    mode: 'manual',
    label: '수동휠체어',
    speedKmh: 3.0,
    stepPassMaxCm: 1.3,
    hardDamage: {'medium', 'high'},
    hardObstacle: {'medium', 'high'},
    hardSlope: {'high'},
    maxDetourFactor: 2.0,
    maxDetourExtraMeters: 400,
    maxRounds: 8,
    weights: {'step': 3.0, 'damage': 1.6, 'obstacle': 1.3, 'slope': 2.5},
  );

  static MobilityProfile of(String mode) => switch (mode) {
        'electric' => electric,
        'manual' => manual,
        _ => pedestrian,
      };

  /// 이 이동 수단이 [h]를 절대 지나면 안 되는지.
  bool isHard(RouteHazard h) {
    switch (h.type) {
      case 'step':
        final limit = stepPassMaxCm;
        if (limit == null) return false;
        if (h.stepHeightCm > 0) return h.stepHeightCm > limit;
        return h.severity != 'low';
      case 'damage':
        return hardDamage.contains(h.severity);
      case 'obstacle':
        return hardObstacle.contains(h.severity);
      case 'slope':
        return hardSlope.contains(h.severity);
      default:
        return false;
    }
  }
}

import 'package:flutter/material.dart';

/// 위험 요소 종류. 지도 마커, 카테고리 칩, 제보 화면이 모두 이 정의를 공유한다.
class HazardType {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const HazardType(this.key, this.label, this.icon, this.color);

  static const step = HazardType('step', '단차', Icons.stairs_rounded, Color(0xFFEA580C));
  static const damage = HazardType('damage', '파손', Icons.construction_rounded, Color(0xFFDC2626));
  static const obstacle = HazardType('obstacle', '적치물', Icons.block_rounded, Color(0xFF7C3AED));

  static const slope = HazardType('slope', '경사', Icons.trending_up_rounded, Color(0xFF0284C7));

  static const all = [step, damage, obstacle, slope];

  /// 알 수 없는 타입은 파손으로 취급하지 않고 null을 돌려준다.
  static HazardType? of(Object? key) {
    for (final t in all) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// 웹이 아닌 플랫폼용 스텁. (모바일은 flutter_compass 사용)
class WebCompass {
  static Future<bool> requestPermission() async => false;

  /// 북쪽 기준 시계방향 방위각(0~360). 웹 외 플랫폼에서는 이벤트가 없음.
  static Stream<double> get headings => const Stream.empty();
}

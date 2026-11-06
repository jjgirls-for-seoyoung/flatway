import 'package:flutter/foundation.dart';

/// 빌드할 때 `--dart-define`으로 넘기는 설정. 키가 없으면 해당 기능은 꺼진다.
///
/// 예) flutter build web --release --dart-define-from-file=dart_defines.json
/// (dart_defines.json 은 Git에 올리지 않는다. 형식은 dart_defines.example.json 참고)
class AppConfig {
  /// 카카오 로컬(장소 검색) REST API 키. 있으면 네이버·카카오맵 수준의 장소 검색을 쓴다.
  static const _kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_API_KEY');

  /// 테스트에서 키를 바꿔 끼우기 위한 값.
  @visibleForTesting
  static String? kakaoRestApiKeyOverride;

  static String get kakaoRestApiKey => kakaoRestApiKeyOverride ?? _kakaoRestApiKey;
  static bool get hasKakao => kakaoRestApiKey.isNotEmpty;
}

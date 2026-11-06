import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 길안내 음성(TTS). 속도 값의 의미가 플랫폼마다 달라서 따로 정한다.
/// - 웹: 1.0이 보통 속도 (0.5는 절반 속도라 매우 느리고 낮게 들린다)
/// - 안드로이드: 플러그인이 값을 2배로 써서 0.5가 보통 속도
/// - iOS: 0.5가 보통 속도
/// 길안내답게 보통보다 약간 빠르게 맞춘다.
class VoiceGuidance {
  /// 선호하는 한국어 목소리 이름(소문자 일부). 앞쪽일수록 우선한다.
  static const preferredVoiceKeys = ['sunhi', 'heami', 'yuna', 'google 한국의', 'female', 'woman'];

  /// 낮고 무겁게 들리지 않도록 음높이를 살짝 올린다.
  static const pitch = 1.1;

  final FlutterTts _tts;
  bool _prepared = false;

  VoiceGuidance([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  /// 플랫폼별 말하기 속도.
  static double speechRateFor({required bool isWeb, required TargetPlatform platform}) {
    if (isWeb) return 1.1;
    if (platform == TargetPlatform.iOS) return 0.54;
    return 0.58; // 안드로이드 등 (내부에서 2배 → 약 1.16배속)
  }

  /// 기기에 있는 한국어 목소리 중 선호 목록에서 가장 앞선 것을 고른다. 없으면 null.
  static Map<String, String>? pickVoice(List<dynamic> voices) {
    final korean = voices
        .whereType<Map>()
        .where((v) => '${v['locale']}'.toLowerCase().replaceAll('_', '-').startsWith('ko'))
        .toList();
    for (final key in preferredVoiceKeys) {
      for (final v in korean) {
        if ('${v['name']}'.toLowerCase().contains(key)) {
          return {'name': '${v['name']}', 'locale': '${v['locale']}'};
        }
      }
    }
    return null;
  }

  Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(speechRateFor(isWeb: kIsWeb, platform: defaultTargetPlatform));
    await _tts.setPitch(pitch);
    await _tts.setVolume(1.0);
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final voice = pickVoice(voices);
        if (voice != null) await _tts.setVoice(voice);
      }
    } catch (e) {
      debugPrint('TTS voice selection skipped: $e');
    }
  }

  Future<void> speak(String text) async {
    try {
      await _prepare();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }
}

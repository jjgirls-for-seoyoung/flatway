import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flatway_app/services/voice_guidance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('속도: 웹은 보통 속도(1.0) 이상, 안드로이드/iOS는 0.5(보통)보다 약간 빠르다', () {
    final web = VoiceGuidance.speechRateFor(isWeb: true, platform: TargetPlatform.android);
    final android = VoiceGuidance.speechRateFor(isWeb: false, platform: TargetPlatform.android);
    final ios = VoiceGuidance.speechRateFor(isWeb: false, platform: TargetPlatform.iOS);

    expect(web, greaterThanOrEqualTo(1.0)); // 예전 값 0.5는 웹에서 절반 속도였다
    expect(web, lessThanOrEqualTo(1.3));
    expect(android, inInclusiveRange(0.52, 0.65));
    expect(ios, inInclusiveRange(0.52, 0.6));
  });

  test('목소리 고르기: 한국어 + 선호 목록 순서, 없으면 null', () {
    final voices = [
      {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
      {'name': 'ko-kr-x-koc-local', 'locale': 'ko-KR'},
      {'name': 'Yuna', 'locale': 'ko_KR'},
      {'name': 'Microsoft SunHi Online (Natural)', 'locale': 'ko-KR'},
    ];
    // sunhi가 yuna보다 선호 순서가 앞선다
    expect(VoiceGuidance.pickVoice(voices), {'name': 'Microsoft SunHi Online (Natural)', 'locale': 'ko-KR'});
    // 영어 목소리만 있으면 고르지 않는다
    expect(VoiceGuidance.pickVoice([{'name': 'Samantha', 'locale': 'en-US'}]), isNull);
    // 한국어지만 선호 목록에 없으면 기본 목소리를 유지한다
    expect(VoiceGuidance.pickVoice([{'name': 'ko-kr-x-koc-local', 'locale': 'ko-KR'}]), isNull);
  });

  test('speak: 한 번만 설정하고(언어, 속도, 음높이, 목소리) 그 뒤 말한다', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('flutter_tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getVoices') {
        return [
          {'name': 'Yuna', 'locale': 'ko-KR'},
        ];
      }
      return 1;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final voice = VoiceGuidance(FlutterTts());
    await voice.speak('100m 앞 우회전');
    await voice.speak('목적지에 도착했습니다.');

    final methods = calls.map((c) => c.method).toList();
    expect(methods.where((m) => m == 'setSpeechRate'), hasLength(1)); // 설정은 한 번만
    expect(methods.where((m) => m == 'speak'), hasLength(2));
    expect(calls.firstWhere((c) => c.method == 'setPitch').arguments, VoiceGuidance.pitch);
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments, {'name': 'Yuna', 'locale': 'ko-KR'});
    // 속도는 항상 말하기 전에 정해진다
    expect(methods.indexOf('setSpeechRate'), lessThan(methods.indexOf('speak')));
  });
}

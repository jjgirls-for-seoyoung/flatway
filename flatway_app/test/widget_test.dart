import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatway_app/main.dart';

void main() {
  testWidgets('FlatWayApp shows the splash screen on launch', (WidgetTester tester) async {
    await tester.pumpWidget(const FlatWayApp());

    expect(find.text('FlatWay'), findsOneWidget);
    expect(find.text('이동 약자 전용 안전 경로 지도 서비스'), findsOneWidget);

    // 스플래시의 대기 타이머가 끝나도록 화면을 치우고 시간을 흘려 보낸다.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 9));
  });
}

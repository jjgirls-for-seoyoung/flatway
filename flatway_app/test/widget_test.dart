import 'package:flutter_test/flutter_test.dart';
import 'package:flatway_app/main.dart';

void main() {
  testWidgets('FlatWayApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FlatWayApp());
    expect(find.text('FlatWay - 2단계 준비 완료'), findsOneWidget);
  });
}

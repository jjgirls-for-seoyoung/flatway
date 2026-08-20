import 'package:flutter_test/flutter_test.dart';
import 'package:flatway_app/main.dart';

void main() {
  testWidgets('FlatWayApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FlatWayApp());
    expect(find.text('FlatWay - 보행 및 이동 수집 지도'), findsOneWidget);
  });
}

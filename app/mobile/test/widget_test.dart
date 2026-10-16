import 'package:flutter_test/flutter_test.dart';
import 'package:smart_agri/main.dart';

void main() {
  testWidgets('renders the Smart Agri mobile app', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Smart Agri mobile app'), findsOneWidget);
  });
}

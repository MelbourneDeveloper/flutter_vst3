import 'package:flutter_test/flutter_test.dart';
import 'package:echo/main.dart';
import 'package:echo/ui/echo_ui.dart';

void main() {
  testWidgets('EchoApp renders EchoUI and EchoWaveformVisualizer',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EchoApp());
    expect(find.byType(EchoUI), findsOneWidget);
    expect(find.byType(EchoWaveformVisualizer), findsOneWidget);
    expect(find.text('Echo Effect'), findsOneWidget);
  });
}

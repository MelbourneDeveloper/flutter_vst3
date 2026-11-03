import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vst3/src/rotary_knob.dart';

void main() {
  group('knobValueAfterDrag', () {
    test('dragging up by the full range sweeps 0 to 1', () {
      expect(knobValueAfterDrag(0.0, -knobDragRangePixels), 1.0);
    });
    test('dragging down decreases the value', () {
      expect(knobValueAfterDrag(0.5, 12.0), closeTo(0.4, 1e-12));
    });
    test('clamps to the normalized range', () {
      expect(knobValueAfterDrag(0.9, -1000.0), 1.0);
      expect(knobValueAfterDrag(0.1, 1000.0), 0.0);
    });
  });

  testWidgets('every drag delta lands even without a rebuild between '
      'updates [PARAM-GESTURE-VALUE-OPENS]', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RotaryKnob(
            label: 'Mix',
            value: 0.5,
            display: '50',
            onChanged: values.add,
            onChangeStart: () {},
            onChangeEnd: () {},
          ),
        ),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('50')));
    await gesture.moveBy(const Offset(0, -12));
    await gesture.moveBy(const Offset(0, -12));
    await gesture.moveBy(const Offset(0, -12));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(values.length, 3);
    expect(values[0], closeTo(0.6, 1e-12));
    expect(values[1], closeTo(0.7, 1e-12));
    expect(values[2], closeTo(0.8, 1e-12));
  });
  testWidgets('a drag fires one start, updates, then one end', (tester) async {
    final events = <String>[];
    final values = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RotaryKnob(
            label: 'Mix',
            value: 0.5,
            display: '50',
            onChanged: values.add,
            onChangeStart: () => events.add('start'),
            onChangeEnd: () => events.add('end'),
          ),
        ),
      ),
    ));
    expect(find.text('Mix'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await tester.drag(find.text('50'), const Offset(0, -60));
    await tester.pump();
    expect(events, ['start', 'end']);
    expect(values, isNotEmpty);
    expect(values.every((v) => v > 0.5), isTrue);
  });
}

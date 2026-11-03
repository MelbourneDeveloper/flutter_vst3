import 'package:flutter_test/flutter_test.dart';
import 'package:echo/src/echo_parameters.dart';

void _assertParameters() {
  final parameters = EchoParameters();
  for (final (id, value) in [(0, 0.1), (1, 0.2), (2, 0.7), (3, 1.0)]) {
    parameters.setParameter(id, value);
    expect(parameters.getParameter(id), value);
  }
  expect(parameters.delayTime, 0.1);
  expect(parameters.feedback, 0.2);
  expect(parameters.mix, 0.7);
  expect(parameters.bypass, 1);
  parameters.setParameter(1, -2);
  expect(parameters.feedback, 0);
  parameters.setParameter(1, 2);
  expect(parameters.feedback, 1);
  expect(parameters.mix, 0.7);
}

void main() {
  test('each parameter routes and clamps independently', _assertParameters);
}

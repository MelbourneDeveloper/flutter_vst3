// Copyright (c) 2025
// Shared DSP setup for the echo plugin tests.

import 'package:echo/src/echo_parameters.dart';
import 'package:echo/src/echo_processor.dart';

/// An echo running at [rate] Hz with [block]-sample blocks, the given delay
/// and feedback, and [mix] wet level.
(EchoProcessor, EchoParameters) echoDsp(
  double rate,
  int block, {
  required double delayTime,
  required double feedback,
  double mix = 1,
}) {
  final processor = EchoProcessor()..initialize(rate, block);
  final parameters = EchoParameters()
    ..delayTime = delayTime
    ..feedback = feedback
    ..mix = mix;
  return (processor, parameters);
}

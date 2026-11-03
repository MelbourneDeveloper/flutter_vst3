import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vertical drag distance, in logical pixels, that sweeps the full range.
const double knobDragRangePixels = 120.0;

/// Returns the normalized knob value after a vertical drag of [deltaY] pixels.
///
/// Dragging up (negative [deltaY]) increases the value. The result is clamped
/// to the normalized VST3 parameter range of 0..1.
double knobValueAfterDrag(double value, double deltaY) =>
    (value - deltaY / knobDragRangePixels).clamp(0.0, 1.0).toDouble();

/// Rotary control for a normalized (0..1) parameter.
///
/// [onChangeStart] and [onChangeEnd] bracket a drag so that callers can map it
/// to a single VST3 beginEdit/performEdit/endEdit automation gesture.
class RotaryKnob extends StatefulWidget {
  /// Creates a knob showing [value] with [display] as the centre readout.
  const RotaryKnob({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
    this.color = const Color(0xFF00E5FF),
    this.size = 100.0,
  });

  /// Caption shown above the knob.
  final String label;

  /// Current normalized value.
  final double value;

  /// Formatted value shown in the centre of the knob.
  final String display;

  /// Called with the new normalized value for every drag update.
  final ValueChanged<double> onChanged;

  /// Called once when a drag gesture starts.
  final VoidCallback onChangeStart;

  /// Called once when a drag gesture ends or is cancelled.
  final VoidCallback onChangeEnd;

  /// Colour of the value arc and readout.
  final Color color;

  /// Width and height of the knob.
  final double size;

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

/// Accumulates drag deltas from the gesture start, so updates arriving before
/// a rebuild still move the value by their full distance.
class _RotaryKnobState extends State<RotaryKnob> {
  double? _dragValue;

  void _startDrag() {
    _dragValue = widget.value;
    widget.onChangeStart();
  }

  void _updateDrag(DragUpdateDetails details) {
    final value =
        knobValueAfterDrag(_dragValue ?? widget.value, details.delta.dy);
    _dragValue = value;
    widget.onChanged(value);
  }

  void _endDrag() {
    _dragValue = null;
    widget.onChangeEnd();
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GestureDetector(
            onPanStart: (_) => _startDrag(),
            onPanUpdate: _updateDrag,
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _KnobPainter(value: widget.value, color: widget.color),
              child: SizedBox.square(
                dimension: widget.size,
                child: Center(
                    child: Text(widget.display,
                        style: TextStyle(color: widget.color))),
              ),
            ),
          ),
        ],
      );
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({required this.value, required this.color});

  static const double _startAngle = 0.75 * math.pi;
  static const double _sweepAngle = 1.5 * math.pi;

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false,
        stroke..color = color.withValues(alpha: 0.15));
    canvas.drawArc(rect, _startAngle, _sweepAngle * value, false,
        stroke..color = color);
    final angle = _startAngle + _sweepAngle * value;
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      6,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.value != value || old.color != color;
}

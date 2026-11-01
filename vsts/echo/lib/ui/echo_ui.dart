/// Flutter UI for Echo VST3 plugin
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vst3/ui.dart';
import '../src/echo_parameters.dart';

/// Main UI screen for the Echo VST3 plugin.
class EchoUI extends StatefulWidget {
  const EchoUI({super.key});

  @override
  State<EchoUI> createState() => _EchoUIState();
}

class _EchoUIState extends State<EchoUI> {
  final VST3ParameterBinding _binding = VST3ParameterBinding.getInstance();

  @override
  void initState() {
    super.initState();
    _binding.addListener(_onParametersChanged);
    _binding.loadInitialParameters();
  }

  @override
  void dispose() {
    _binding.removeListener(_onParametersChanged);
    super.dispose();
  }

  void _onParametersChanged() {
    setState(() {});
  }

  Widget _buildParameterSlider(int paramId, String label) {
    final value = _binding.getParameter(paramId);
    return RotaryKnob(
      label: label,
      value: value,
      display: formatEchoParameter(paramId, value),
      onChangeStart: () => _binding.beginEdit(paramId),
      onChanged: (value) => _binding.setParameter(paramId, value),
      onChangeEnd: () => _binding.endEdit(paramId),
    );
  }

  Widget _buildBypassToggle() {
    final isBypassed = _binding.getParameter(EchoParameters.kBypassParam) > 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Bypass',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Switch(
            value: isBypassed,
            onChanged: (value) async {
              await _binding.beginEdit(EchoParameters.kBypassParam);
              await _binding.setParameter(
                EchoParameters.kBypassParam,
                value ? 1.0 : 0.0,
              );
              await _binding.endEdit(EchoParameters.kBypassParam);
            },
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Echo VST3'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'Echo Effect',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildParameterSlider(
                              EchoParameters.kDelayTimeParam,
                              'Delay Time',
                            ),
                            _buildParameterSlider(
                              EchoParameters.kFeedbackParam,
                              'Feedback',
                            ),
                            _buildParameterSlider(
                              EchoParameters.kMixParam,
                              'Mix',
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        _buildBypassToggle(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const EchoWaveformVisualizer(height: 150.0),
        ],
      ),
    );
  }
}

/// Custom oscilloscope visualizer widget displaying real-time audio waveform.
class EchoWaveformVisualizer extends StatefulWidget {
  final double height;
  final Color waveColor;

  const EchoWaveformVisualizer({
    super.key,
    this.height = 150.0,
    this.waveColor = const Color(0xFF00E5FF),
  });

  @override
  State<EchoWaveformVisualizer> createState() => _EchoWaveformVisualizerState();
}

class _EchoWaveformVisualizerState extends State<EchoWaveformVisualizer> {
  Timer? _timer;
  Vst3AudioBufferReader? _reader;
  List<double> _samples = const [];
  bool _fetchingReader = false;
  bool _attached = true;

  @override
  void initState() {
    super.initState();
    _initReader();
    _timer = Timer.periodic(
        const Duration(milliseconds: 33), (_) => _pollWaveform());
    VST3ParameterBinding.getInstance().addListener(_onBindingUpdated);
  }

  void _onBindingUpdated() {
    if (!VST3ParameterBinding.getInstance().isHostAttached) {
      _attached = false;
      _reader = null;
      if (mounted && _samples.isNotEmpty) {
        setState(() {
          _samples = const [];
        });
      }
      return;
    }
    final attached = VST3ParameterBinding.getInstance().isHostAttached;
    attached && !_attached ? _initReader() : null;
    _attached = attached;
  }

  void _initReader() async {
    if (!VST3ParameterBinding.getInstance().isHostAttached) return;
    if (_fetchingReader) return;
    _fetchingReader = true;
    try {
      final reader = await VST3ParameterBinding.getInstance()
          .getAudioBufferReader(forceRefresh: true);
      if (mounted) {
        _reader = (reader != null && reader.isValid) ? reader : null;
      }
    } finally {
      _fetchingReader = false;
    }
  }

  void _pollWaveform() {
    if (!VST3ParameterBinding.getInstance().isHostAttached) return;
    final reader = _reader;
    if (reader == null) return;
    if (!reader.isValid || !mounted) {
      _reader = null;
      _initReader();
      return;
    }
    final samples = reader.getLatestOutputSamples(maxCount: 256);
    if (mounted) {
      setState(() => _samples = samples);
    }
  }

  @override
  void dispose() {
    VST3ParameterBinding.getInstance().removeListener(_onBindingUpdated);
    _timer?.cancel();
    _timer = null;
    _reader = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: widget.height,
      color: Colors.black,
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _EchoWaveformPainter(
          samples: _samples,
          color: widget.waveColor,
        ),
      ),
    );
  }
}

class _EchoWaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  _EchoWaveformPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawWave(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );
  }

  void _drawWave(Canvas canvas, Size size) {
    switch (samples.isEmpty) {
      case true:
        final idlePaint = Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          idlePaint,
        );
        return;
      case false:
        final path = buildEchoWaveformPath(samples, size);
        _renderPath(canvas, path);
    }
  }

  void _renderPath(Canvas canvas, Path path) {
    final glow = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _EchoWaveformPainter oldDelegate) => true;
}

/// Builds a finite waveform path, including empty and single-sample blocks.
Path buildEchoWaveformPath(List<double> samples, Size size) {
  final path = Path();
  final slice = samples.length < 2 ? 0.0 : size.width / (samples.length - 1);
  final centerY = size.height / 2;

  for (var i = 0; i < samples.length; i++) {
    final x = i * slice;
    final y = centerY - (samples[i].clamp(-1.0, 1.0) * (size.height * 0.44));
    switch (i == 0) {
      case true:
        path.moveTo(x, y);
      case false:
        path.lineTo(x, y);
    }
  }
  return path;
}

/// Formats normalized Echo parameters in their physical units.
String formatEchoParameter(int id, double value) =>
    id == EchoParameters.kDelayTimeParam
        ? '${(value * 1000).toStringAsFixed(1)}ms'
        : '${(value * 100).toStringAsFixed(1)}%';

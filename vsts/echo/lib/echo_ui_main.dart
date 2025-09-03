import 'package:flutter/material.dart';
import 'dart:math';
import 'package:dart_vst3_bridge/dart_vst3_bridge.dart';
import 'echo_parameters.dart';
import 'src/echo_bridge.dart';

/// Main entry point for Echo VST3 Flutter UI
/// This runs as a native Flutter app that directly controls VST parameters
void main() {
  // Initialize the Echo VST3 bridge
  EchoBridge.initialize();
  runApp(const EchoVSTApp());
}

class EchoVSTApp extends StatelessWidget {
  const EchoVSTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo VST3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const EchoControlPanel(),
    );
  }
}

class EchoControlPanel extends StatefulWidget {
  const EchoControlPanel({super.key});

  @override
  State<EchoControlPanel> createState() => _EchoControlPanelState();
}

class _EchoControlPanelState extends State<EchoControlPanel> 
    with SingleTickerProviderStateMixin {
  
  final EchoParameters _parameters = EchoParameters();
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    // Register for parameter change notifications from DAW/host
    VST3Bridge.registerParameterChangeCallback(_onParameterChanged);
  }
  
  void _onParameterChanged(int paramId, double value) {
    if (mounted) {
      setState(() {
        _parameters.setParameter(paramId, value);
      });
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  void _updateParameter(int paramId, double value) {
    setState(() {
      _parameters.setParameter(paramId, value);
    });
    // Send parameter change to VST host/DAW
    VST3Bridge.sendParameterToHost(paramId, value);
  }

  Widget _buildRotaryKnob({
    required String label,
    required int paramId,
    required double value,
    required String unit,
    required Color primaryColor,
    required Color accentColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        
        // Rotary knob
        GestureDetector(
          onPanUpdate: (details) {
            final delta = -details.delta.dy / 120;
            final newValue = (value + delta).clamp(0.0, 1.0);
            _updateParameter(paramId, newValue);
          },
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                // Background circle
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2A2A3A),
                        const Color(0xFF1A1A2A),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 8,
                        offset: const Offset(2, 2),
                      ),
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.2),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                
                // Value arc and indicator
                CustomPaint(
                  size: const Size(100, 100),
                  painter: _KnobPainter(
                    value: value,
                    primaryColor: primaryColor,
                    accentColor: accentColor,
                  ),
                ),
                
                // Center value display
                Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0A0A1A),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(value * 100).toStringAsFixed(0)}',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (unit.isNotEmpty)
                          Text(
                            unit,
                            style: TextStyle(
                              color: primaryColor.withValues(alpha: 0.6),
                              fontSize: 8,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF0A0A1A),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 520,
            height: 380,
            decoration: BoxDecoration(
              color: const Color(0xFF16213E).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.cyan.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.cyan.withValues(alpha: 0.1),
                  blurRadius: 40,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Header with animated title
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.withValues(alpha: 0.15),
                        Colors.blue.withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Text(
                          'ECHO FX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 10,
                            shadows: [
                              Shadow(
                                color: Colors.cyan.withValues(
                                  alpha: 0.8 * sin(_pulseController.value * 2 * pi).abs(),
                                ),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 50),
                
                // Knobs row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildRotaryKnob(
                        label: 'Delay',
                        paramId: EchoParameters.kDelayTimeParam,
                        value: _parameters.delayTime,
                        unit: 'ms',
                        primaryColor: Colors.cyan,
                        accentColor: Colors.blue,
                      ),
                      _buildRotaryKnob(
                        label: 'Feedback',
                        paramId: EchoParameters.kFeedbackParam,
                        value: _parameters.feedback,
                        unit: '%',
                        primaryColor: Colors.purple,
                        accentColor: Colors.pink,
                      ),
                      _buildRotaryKnob(
                        label: 'Mix',
                        paramId: EchoParameters.kMixParam,
                        value: _parameters.mix,
                        unit: '%',
                        primaryColor: Colors.orange,
                        accentColor: Colors.yellow,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 50),
                
                // Bypass toggle
                GestureDetector(
                  onTap: () {
                    final newValue = _parameters.bypass > 0.5 ? 0.0 : 1.0;
                    _updateParameter(EchoParameters.kBypassParam, newValue);
                  },
                  child: Container(
                    width: 140,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: _parameters.bypass > 0.5
                            ? [
                                Colors.red.withValues(alpha: 0.3),
                                Colors.red.withValues(alpha: 0.1),
                              ]
                            : [
                                Colors.green.withValues(alpha: 0.3),
                                Colors.green.withValues(alpha: 0.1),
                              ],
                      ),
                      border: Border.all(
                        color: (_parameters.bypass > 0.5 ? Colors.red : Colors.green)
                            .withValues(alpha: 0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_parameters.bypass > 0.5 ? Colors.red : Colors.green)
                              .withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _parameters.bypass > 0.5 ? 'BYPASSED' : 'ACTIVE',
                        style: TextStyle(
                          color: _parameters.bypass > 0.5 ? Colors.red : Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for rotary knob with value arc
class _KnobPainter extends CustomPainter {
  final double value;
  final Color primaryColor;
  final Color accentColor;

  _KnobPainter({
    required this.value,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    
    // Draw background arc
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    
    const startAngle = 0.75 * pi;
    const sweepAngle = 1.5 * pi;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );
    
    // Draw value arc
    if (value > 0) {
      final valuePaint = Paint()
        ..shader = SweepGradient(
          colors: [primaryColor, accentColor, primaryColor],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * value,
        false,
        valuePaint,
      );
    }
    
    // Draw indicator dot
    final indicatorAngle = startAngle + sweepAngle * value;
    final dotRadius = 6.0;
    final dotDistance = radius - 2;
    final dotX = center.dx + dotDistance * cos(indicatorAngle);
    final dotY = center.dy + dotDistance * sin(indicatorAngle);
    
    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);
    
    // Glow effect for indicator
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    
    canvas.drawCircle(Offset(dotX, dotY), dotRadius + 2, glowPaint);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) => 
      oldDelegate.value != value ||
      oldDelegate.primaryColor != primaryColor;
}
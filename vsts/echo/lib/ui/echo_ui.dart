/// Flutter UI for Echo VST3 plugin
/// This runs in the SAME process/isolate as the audio processing
import 'package:flutter/material.dart';
import 'package:flutter_vst3/flutter_vst3.dart';
import '../src/echo_parameters.dart';

class EchoUI extends StatefulWidget {
  const EchoUI({super.key});

  @override
  State<EchoUI> createState() => _EchoUIState();
}

class _EchoUIState extends State<EchoUI> {
  late final VST3ParameterBinding _binding;
  
  @override
  void initState() {
    super.initState();
    _binding = VST3ParameterBinding.getInstance();
    
    // Listen for parameter changes from DAW
    _binding.addListener(_onParametersChanged);
  }
  
  @override
  void dispose() {
    _binding.removeListener(_onParametersChanged);
    super.dispose();
  }
  
  void _onParametersChanged() {
    // Rebuild UI when parameters change from DAW
    setState(() {});
  }
  
  Widget _buildParameterSlider(int paramId, String label) {
    final value = _binding.getParameter(paramId);
    final units = _binding.getParameterUnits(paramId);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${(value * 100).toStringAsFixed(1)}$units',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            onChanged: (newValue) {
              // Update parameter in SAME process - no IPC!
              _binding.setParameter(paramId, newValue);
            },
            activeColor: Theme.of(context).colorScheme.primary,
            inactiveColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
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
            onChanged: (value) {
              _binding.setParameter(
                EchoParameters.kBypassParam,
                value ? 1.0 : 0.0,
              );
            },
            activeColor: Theme.of(context).colorScheme.primary,
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
      body: Center(
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
                const Divider(height: 32),
                _buildBypassToggle(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
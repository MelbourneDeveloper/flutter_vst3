import 'package:dart_vst3_bridge/dart_vst3_bridge.dart';
import 'reverb_processor.dart';
import 'reverb_parameters.dart';

/// VST3 processor adapter for the Flutter Reverb plugin
/// This connects the pure Dart reverb processor to the VST3 bridge
class ReverbVST3Processor extends VST3Processor {
  ReverbProcessor? _reverbProcessor;
  
  @override
  void initialize(double sampleRate, int maxBlockSize) {
    _reverbProcessor = ReverbProcessor();
    _reverbProcessor!.initialize(sampleRate, maxBlockSize);
  }

  @override
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR) {
    _reverbProcessor?.processStereo(inputL, inputR, outputL, outputR);
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    _reverbProcessor?.setParameter(paramId, normalizedValue);
  }

  @override
  double getParameter(int paramId) {
    return _reverbProcessor?.getParameter(paramId) ?? 0.0;
  }

  @override
  int getParameterCount() {
    return ReverbParameters.numParameters;
  }

  @override
  void reset() {
    _reverbProcessor?.reset();
  }

  @override
  void dispose() {
    _reverbProcessor?.dispose();
    _reverbProcessor = null;
  }
}
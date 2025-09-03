import 'package:flutter_vst3/flutter_vst3.dart';
import 'echo_processor.dart';
import 'echo_parameters.dart';

/// VST3 processor adapter for the Echo plugin
/// This connects the pure Dart echo processor to the VST3 bridge
class EchoVST3Processor extends VST3Processor {
  EchoProcessor? _echoProcessor;
  final EchoParameters _parameters = EchoParameters();
  
  @override
  void initialize(double sampleRate, int maxBlockSize) {
    _echoProcessor = EchoProcessor();
    _echoProcessor!.initialize(sampleRate, maxBlockSize);
  }

  @override
  void processStereo(List<double> inputL, List<double> inputR,
                    List<double> outputL, List<double> outputR) {
    _echoProcessor?.processStereo(inputL, inputR, outputL, outputR, _parameters);
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    _parameters.setParameter(paramId, normalizedValue);
  }

  @override
  double getParameter(int paramId) {
    return _parameters.getParameter(paramId);
  }

  @override
  int getParameterCount() {
    return EchoParameters.numParameters;
  }

  @override
  void reset() {
    _echoProcessor?.reset();
  }

  @override
  void dispose() {
    _echoProcessor?.dispose();
    _echoProcessor = null;
  }
}
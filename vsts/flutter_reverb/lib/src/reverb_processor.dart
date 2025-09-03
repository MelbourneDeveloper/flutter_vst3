import '../flutter_reverb_parameters.dart';

/// Comb filter implementation for reverb
class CombFilter {
  final List<double> _buffer;
  int _bufferIndex = 0;
  double _feedback = 0.5;
  double _dampening = 0.5;
  double _filterStore = 0.0;

  CombFilter(int bufferSize) : _buffer = List.filled(bufferSize, 0.0);

  double process(double input) {
    final output = _buffer[_bufferIndex];
    _filterStore = (output * (1.0 - _dampening)) + (_filterStore * _dampening);
    _buffer[_bufferIndex] = input + (_filterStore * _feedback);
    
    _bufferIndex = (_bufferIndex + 1) % _buffer.length;
    return output;
  }

  void setFeedback(double feedback) => _feedback = feedback;
  void setDampening(double dampening) => _dampening = dampening;
  
  void reset() {
    _buffer.fillRange(0, _buffer.length, 0.0);
    _bufferIndex = 0;
    _filterStore = 0.0;
  }
}

/// Allpass filter implementation for reverb
class AllpassFilter {
  final List<double> _buffer;
  int _bufferIndex = 0;
  final double _feedback = 0.5;

  AllpassFilter(int bufferSize) : _buffer = List.filled(bufferSize, 0.0);

  double process(double input) {
    final bufout = _buffer[_bufferIndex];
    final output = -input + bufout;
    _buffer[_bufferIndex] = input + (bufout * _feedback);
    
    _bufferIndex = (_bufferIndex + 1) % _buffer.length;
    return output;
  }
  
  void reset() {
    _buffer.fillRange(0, _buffer.length, 0.0);
    _bufferIndex = 0;
  }
}

/// Pure Dart reverb processor using Freeverb algorithm
class ReverbProcessor {
  static const int _kNumCombs = 8;
  static const int _kNumAllpass = 4;
  
  // Tuning values for 44.1kHz
  static const List<int> _combTuning = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const List<int> _allpassTuning = [556, 441, 341, 225];
  
  final List<CombFilter> _combFiltersL = [];
  final List<CombFilter> _combFiltersR = [];
  final List<AllpassFilter> _allpassFiltersL = [];
  final List<AllpassFilter> _allpassFiltersR = [];
  
  final ReverbParameters _parameters = ReverbParameters();
  double _sampleRate = 44100.0;
  bool _initialized = false;

  /// Initialize the reverb processor
  void initialize(double sampleRate, int maxBlockSize) {
    _sampleRate = sampleRate;
    _initializeFilters();
    _initialized = true;
  }

  void _initializeFilters() {
    final scale = _sampleRate / 44100.0;
    
    _combFiltersL.clear();
    _combFiltersR.clear();
    _allpassFiltersL.clear();
    _allpassFiltersR.clear();
    
    // Initialize comb filters
    for (int i = 0; i < _kNumCombs; i++) {
      final bufferSizeL = (_combTuning[i] * scale).round();
      final bufferSizeR = ((_combTuning[i] + 23) * scale).round();
      
      _combFiltersL.add(CombFilter(bufferSizeL));
      _combFiltersR.add(CombFilter(bufferSizeR));
    }
    
    // Initialize allpass filters  
    for (int i = 0; i < _kNumAllpass; i++) {
      final bufferSizeL = (_allpassTuning[i] * scale).round();
      final bufferSizeR = ((_allpassTuning[i] + 23) * scale).round();
      
      _allpassFiltersL.add(AllpassFilter(bufferSizeL));
      _allpassFiltersR.add(AllpassFilter(bufferSizeR));
    }
    
    _updateCombFilterParameters();
  }

  void _updateCombFilterParameters() {
    final feedback = _parameters.roomSize * 0.28 + 0.7;
    
    for (final filter in _combFiltersL) {
      filter.setFeedback(feedback);
      filter.setDampening(_parameters.damping);
    }
    
    for (final filter in _combFiltersR) {
      filter.setFeedback(feedback);
      filter.setDampening(_parameters.damping);
    }
  }

  /// Set parameter value
  void setParameter(int paramId, double value) {
    _parameters.setParameter(paramId, value);
    
    if (_initialized && (paramId == ReverbParameters.kRoomSizeParam || 
                        paramId == ReverbParameters.kDampingParam)) {
      _updateCombFilterParameters();
    }
  }

  /// Get parameter value
  double getParameter(int paramId) {
    return _parameters.getParameter(paramId);
  }

  /// Process stereo audio block
  void processStereo(List<double> inputL, List<double> inputR, 
                    List<double> outputL, List<double> outputR) {
    if (!_initialized || inputL.length != inputR.length ||
        outputL.length != inputL.length || outputR.length != inputL.length) {
      return;
    }
    
    for (int i = 0; i < inputL.length; i++) {
      // Mix to mono for reverb input
      final monoIn = (inputL[i] + inputR[i]) * 0.5;
      
      // Process through comb filters
      double combOutL = 0.0;
      double combOutR = 0.0;
      
      for (int j = 0; j < _kNumCombs; j++) {
        combOutL += _combFiltersL[j].process(monoIn);
        combOutR += _combFiltersR[j].process(monoIn);
      }
      
      // Process through allpass filters
      for (int j = 0; j < _kNumAllpass; j++) {
        combOutL = _allpassFiltersL[j].process(combOutL);
        combOutR = _allpassFiltersR[j].process(combOutR);
      }
      
      // Mix dry and wet signals
      outputL[i] = inputL[i] * _parameters.dryLevel + combOutL * _parameters.wetLevel;
      outputR[i] = inputR[i] * _parameters.dryLevel + combOutR * _parameters.wetLevel;
    }
  }

  /// Reset all filters
  void reset() {
    for (final filter in _combFiltersL) {
      filter.reset();
    }
    for (final filter in _combFiltersR) {
      filter.reset();
    }
    for (final filter in _allpassFiltersL) {
      filter.reset();
    }
    for (final filter in _allpassFiltersR) {
      filter.reset();
    }
  }

  /// Dispose resources
  void dispose() {
    _initialized = false;
    _combFiltersL.clear();
    _combFiltersR.clear();
    _allpassFiltersL.clear();
    _allpassFiltersR.clear();
  }
}
/// Parameter binding between Flutter UI and VST3 controller
library;

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'shared_memory_reader.dart';

/// Manages bidirectional parameter and audio streaming synchronization between
/// the Flutter UI and the VST3 EditController across macOS, Windows, and Linux.
class VST3ParameterBinding {
  static const MethodChannel _channel = MethodChannel('flutter_vst3/parameters');
  static VST3ParameterBinding? _instance;
  final List<void Function()> _listeners = [];
  final List<void Function(List<double>)> _waveformListeners = [];
  
  final Map<int, double> _parameters = {};
  final Map<int, String> _parameterNames = {};
  final Map<int, String> _parameterUnits = {};
  final int parameterCount;
  
  /// Returns the singleton binding instance.
  static VST3ParameterBinding getInstance({int paramCount = 64}) {
    _instance ??= VST3ParameterBinding._(paramCount);
    return _instance!;
  }
  
  VST3ParameterBinding._(this.parameterCount) {
    _initChannel();
    for (var i = 0; i < parameterCount; i++) {
      _parameters[i] = 0.0;
    }
  }

  bool _isHostAttached = true;
  /// Whether the plugin GUI is currently attached to an active OS window.
  bool get isHostAttached => _isHostAttached;

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onParameterChanged':
          _handleParamChanged(call.arguments);
        case 'onAudioWaveform':
          _handleWaveform(call.arguments);
        case 'onHostDetached':
          _isHostAttached = false;
          _audioReader = null;
          // ignore: avoid_print
          print('[flutter_vst3] onHostDetached received, audioReader invalidated');
          notifyListeners();
        case 'onHostAttached':
          _isHostAttached = true;
          _audioReader = null;
          // ignore: avoid_print
          print('[flutter_vst3] onHostAttached received, reloading parameters');
          await loadInitialParameters();
          notifyListeners();
        default:
          break;
      }
    });
    loadInitialParameters();
  }

  /// Loads current parameter values from the VST3 EditController.
  Future<void> loadInitialParameters() async {
    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getInitialParameters',
      );
      if (map != null) {
        map.forEach((k, v) {
          final id = k is num ? k.toInt() : int.tryParse(k.toString());
          final val = (v as num?)?.toDouble();
          if (id != null && val != null) {
            _parameters[id] = val;
          }
        });
        notifyListeners();
      }
    } catch (_) {}
  }

  void _handleParamChanged(dynamic arguments) {
    final args = arguments as Map?;
    final id = args?['id'] as int?;
    final val = (args?['value'] as num?)?.toDouble();
    if (id != null && val != null) {
      _parameters[id] = val;
      notifyListeners();
    }
  }

  void _handleWaveform(dynamic arguments) {
    final list = arguments as List<dynamic>?;
    if (list != null) {
      final samples = list.map((e) => (e as num).toDouble()).toList();
      for (final listener in _waveformListeners) {
        listener(samples);
      }
    }
  }
  
  /// Adds a listener for parameter updates.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }
  
  /// Removes a listener.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Adds a listener for real-time waveform frames.
  void addWaveformListener(void Function(List<double>) listener) {
    _waveformListeners.add(listener);
  }

  /// Removes a waveform listener.
  void removeWaveformListener(void Function(List<double>) listener) {
    _waveformListeners.remove(listener);
  }
  
  /// Notifies all registered listeners of parameter changes.
  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
  
  /// Returns current parameter value (0.0 to 1.0).
  double getParameter(int id) {
    return _parameters[id] ?? 0.0;
  }
  
  /// Sets parameter value from UI and notifies the VST3 EditController.
  void setParameter(int id, double value) {
    final clamped = value.clamp(0.0, 1.0);
    _parameters[id] = clamped;
    _channel.invokeMethod<void>('setParameter', {
      'id': id,
      'value': clamped,
    });
    notifyListeners();
  }
  
  void setParameterName(int id, String name) {
    _parameterNames[id] = name;
  }
  
  String getParameterName(int id) {
    return _parameterNames[id] ?? 'Parameter $id';
  }
  
  void setParameterUnits(int id, String units) {
    _parameterUnits[id] = units;
  }
  
  String getParameterUnits(int id) {
    return _parameterUnits[id] ?? '';
  }
  
  Map<int, double> getAllParameters() {
    return Map.from(_parameters);
  }

  Vst3AudioBufferReader? _audioReader;

  /// Obtains direct zero-copy read access to the audio buffers in shared memory.
  Future<Vst3AudioBufferReader?> getAudioBufferReader({bool forceRefresh = false}) async {
    if (_audioReader != null && !forceRefresh) return _audioReader;
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getSharedMemoryInfo');
      if (info != null) {
        final addr = (info['address'] as num?)?.toInt() ?? 0;
        _audioReader = Vst3AudioBufferReader.fromAddress(addr);
      }
    } catch (_) {}
    return _audioReader;
  }

  /// Invalidates and clears the cached shared memory audio buffer reader.
  void invalidateAudioReader() {
    _audioReader = null;
  }
}


/// Audio processor base class that uses shared parameters
/// This runs in the SAME isolate as the UI!
abstract class VST3AudioProcessor {
  VST3AudioProcessor();
  
  /// Get parameter value for audio processing
  @pragma('vm:prefer-inline')
  double getParameter(int id) {
    return VST3ParameterBinding.getInstance().getParameter(id);
  }
  
  /// Check if parameter changed
  @pragma('vm:prefer-inline')
  bool hasParameterChanged(int id) {
    return false;
  }
  
  /// Process audio - to be implemented by plugin
  /// This is called via FFI from the audio thread
  @pragma('vm:entry-point')
  void processAudio(
    Float32List inputL,
    Float32List inputR,
    Float32List outputL,
    Float32List outputR,
    int sampleFrames,
  );
  
  /// Initialize processor
  @pragma('vm:entry-point')
  void initialize(double sampleRate, int maxBlockSize);
  
  /// Reset processor state
  @pragma('vm:entry-point')
  void reset();
}
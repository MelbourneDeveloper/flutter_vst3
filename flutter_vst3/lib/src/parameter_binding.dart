/// Parameter binding between Flutter UI and VST3 controller
library;

import 'package:flutter/services.dart';
import 'shared_memory_reader.dart';

/// Manages bidirectional parameter and audio streaming synchronization between
/// the Flutter UI and the VST3 EditController across macOS, Windows, and Linux.
class VST3ParameterBinding {
  static const MethodChannel _channel =
      MethodChannel('flutter_vst3/parameters');
  static VST3ParameterBinding? _instance;
  final List<void Function()> _listeners = [];
  final List<void Function(List<double>)> _waveformListeners = [];

  final Map<int, double> _parameters = {};
  final Map<int, String> _parameterNames = {};
  final Map<int, String> _parameterUnits = {};
  final Set<int> _pendingBegins = {};
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
  bool _dspStopped = false;

  /// Whether the DSP worker died: the host still names a memory block, but the
  /// block no longer reads as valid. Audio is silent until the next activation.
  bool get dspStopped => _dspStopped;

  void _setDspStopped(bool stopped) {
    final changed = stopped != _dspStopped;
    _dspStopped = stopped;
    changed ? notifyListeners() : null;
  }

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
          _pendingBegins.clear();
          notifyListeners();
        case 'onHostAttached':
          _isHostAttached = true;
          _audioReader = null;
          await loadInitialParameters();
          notifyListeners();
        default:
          break;
      }
    });
    loadInitialParameters();
  }

  /// Loads current parameter values from the VST3 EditController.
  ///
  /// Running without a host, as `flutter run` does, is not an error: there's
  /// no channel, and the cache stays as it is. A bad reply from a host throws.
  Future<void> loadInitialParameters() async {
    try {
      _applyInitial(
        await _channel.invokeMethod<Object?>('getInitialParameters'),
      );
    } on MissingPluginException {
      return;
    }
  }

  void _applyInitial(Object? reply) {
    final map = switch (reply) {
      Map value => value,
      _ => throw ArgumentError('Expected initial parameter map'),
    };
    final validated = <int, double>{};
    for (final entry in map.entries) {
      validated[_initialId(entry.key)] = _validatedValue(entry.value);
    }
    _parameters.addAll(validated);
    notifyListeners();
  }

  void _handleParamChanged(dynamic arguments) {
    final args = switch (arguments) {
      Map value => value,
      _ => throw ArgumentError('Expected parameter message map'),
    };
    final id = _validatedId(args['id']);
    final value = _validatedValue(args['value']);
    _parameters[id] = value;
    notifyListeners();
  }

  int _initialId(Object? key) => switch (key) {
    String text when RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(text) =>
      _validatedId(int.tryParse(text)),
    _ => _validatedId(key),
  };

  int _validatedId(Object? id) => switch (id) {
    int value when value >= 0 && value < parameterCount => value,
    _ => throw ArgumentError.value(id, 'id', 'Invalid parameter ID'),
  };

  double _validatedValue(Object? value) => switch (value) {
    num number when number.isFinite && number >= 0 && number <= 1 =>
      number.toDouble(),
    _ => throw ArgumentError.value(value, 'value', 'Expected normalized value'),
  };

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

  /// Begins one host automation gesture.
  ///
  /// The host hears of it at the first value, so that a tap, or a stray pointer
  /// event, leaves no empty gesture on the host.
  Future<void> beginEdit(int id) async => _pendingBegins.add(id);

  /// Ends one host automation gesture.
  Future<void> endEdit(int id) async => _pendingBegins.remove(id)
      ? null
      : await _send('endEdit', {'id': id});

  /// Without a host there's no channel to send to, which isn't an error.
  Future<void> _send(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    }
  }

  /// Sets parameter value from UI and notifies the VST3 EditController.
  Future<void> setParameter(int id, double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _parameters[id] = clamped;
    _pendingBegins.remove(id) ? await _send('beginEdit', {'id': id}) : null;
    await _send('setParameter', {'id': id, 'value': clamped});
    notifyListeners();
  }

  /// Stores the display name for [id].
  void setParameterName(int id, String name) {
    _parameterNames[id] = name;
  }

  /// Returns the display name for [id].
  String getParameterName(int id) {
    return _parameterNames[id] ?? 'Parameter $id';
  }

  /// Stores the display units for [id].
  void setParameterUnits(int id, String units) {
    _parameterUnits[id] = units;
  }

  /// Returns the display units for [id].
  String getParameterUnits(int id) {
    return _parameterUnits[id] ?? '';
  }

  /// Returns a snapshot of all cached normalized parameters.
  Map<int, double> getAllParameters() {
    return Map.from(_parameters);
  }

  Vst3AudioBufferReader? _audioReader;

  /// Obtains direct zero-copy read access to the audio buffers in shared memory.
  Future<Vst3AudioBufferReader?> getAudioBufferReader(
      {bool forceRefresh = false}) async {
    if (_audioReader != null && !forceRefresh) return _audioReader;
    try {
      final info = await _channel
          .invokeMapMethod<String, dynamic>('getSharedMemoryInfo');
      if (info != null) {
        final addr = (info['address'] as num?)?.toInt() ?? 0;
        _audioReader = Vst3AudioBufferReader.fromAddress(addr);
        _setDspStopped(addr != 0 && _audioReader == null);
      }
    } on MissingPluginException {
      // Standalone Flutter has no host channel.
    }
    return _audioReader;
  }

  /// Invalidates and clears the cached shared memory audio buffer reader.
  void invalidateAudioReader() {
    _audioReader = null;
  }
}

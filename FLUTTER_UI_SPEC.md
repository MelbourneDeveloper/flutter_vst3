# Plugin UI and DSP design

The VST3 module runs in the audio host process. Its editor embeds a Flutter
engine in the host-provided native window (Cocoa on macOS, Win32 on Windows,
GTK/X11 on Linux). The Flutter editor is not the audio processor.

DSP runs in a separate compiled Dart worker process for each plugin instance.
The native processor exchanges audio blocks and parameter commands with that
worker through shared memory and platform synchronization primitives. Audio
is copied between the host buffers and shared memory; this is not zero-copy.

The controller connects Flutter parameter gestures to VST3 host automation.
The editor reads the instance's shared-memory telemetry for visualization.
Saved parameter state belongs to the VST3 processor and must be replayed to
the worker when restoring a session. Closing an editor must not stop DSP;
disposing a processor must release its worker and IPC resources.

Linux embedded editors require X11. Launch Flutter hosts with
`GDK_BACKEND=x11 flutter run`; Wayland embedding is not supported.

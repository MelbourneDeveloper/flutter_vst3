# Echo

A stereo VST3 delay effect with an embedded Flutter editor. DSP runs in a
separate worker process connected to the host through shared memory.

Parameters from `plugin_metadata.json` (values are normalized 0–1):

| Parameter | Meaning | Default |
|---|---|---|
| Delay Time | 0–1000 ms | 0.5 (500 ms) |
| Feedback | 0–100% | 0.3 (30%) |
| Mix | Dry to wet, 0–100% | 0.5 (50%) |
| Bypass | Enables bypass | 0 (off) |

From the repository root, with Flutter, CMake, a C++ toolchain and
`VST3_SDK_DIR` pointing at the Steinberg SDK:

```sh
make echo
cd vsts/echo
flutter test
```

The bundle is produced at `vsts/echo/build/VST3/Release/echo.vst3`.
On Windows use `build.bat echo`. Linux editors require an X11 host environment.

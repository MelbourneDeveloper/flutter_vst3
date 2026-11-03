# AGENTS.md

Steinberg VST® 3 toolkit for Dart and Flutter: build plugins and hosts with no hand-written C++. *VST® is a trademark of Steinberg Media Technologies GmbH.*

## Workflow
- ❌ subagents, linked worktrees, git hooks. Primary checkout only; git = commit/push.
- **Offload legwork (repetitive, simple work) to pi agents** — exact ids only, in this precedence: `kimi-coding/k3.1-pro-highspeed` → `zai/glm-5.3` → `zai/glm-5.3-flash` → `deepseek/deepseek-flash`. `pi auth check --model <id>` first; out of credit → tell user, fall to the next. You own their output: review and fix it.
- **Tokens:** check file size before reading, grep first, smallest diff.
- **Entry points = make targets.** `make help` + [`Makefile`](Makefile) first. Windows: `build.bat <target>`.

## Duplication
- 🐛 **Duplication and superfluous code are bugs** — copies, parallel versions, dead code, stale comments. Fix on sight; move code, ❌ copy it.
- 🛑 Run [deslop](https://deslop.live/docs/for-ai/) before writing (is it already there?) and after (`make deslop`). Install: `brew install nimblesite/tap/deslop`.
- `make deslop` and the CI `duplication` job fail above `max_duplication_percent` in [`.deslop.toml`](.deslop.toml). That ceiling only goes ⬇️. ❌ raise it, or add `exclude`/`report_hide` entries to hide a finding; fix the code.

## Correctness
- **Fail hard, in the open.** ❌ placeholders, fallbacks, fake values, warnings instead of failures. Not implemented → throw.
- 🛑 **A plugin never takes down the DAW.** ❌ `abort()` in plugin code. Native failures go through the VST3 API: `setActive` returns an error, `process` returns `kNotInitialized` with silence.
- 🛑 **The audio thread never starts a process.** A dead worker restarts at the next activation.
- **Test before fix.** If only one, write the test. A red test is correct: ❌ weaken, skip, delete or drop assertions.

## Tests
- ✅ E2E tests driving real use cases: many input permutations, many interactions per test, many assertions per interaction. Unit tests only when isolation is needed.
- Tests fail hard: ❌ allowances, printed warnings.
- `make test` runs everything and needs the native libraries, which it builds. `make test-native`, `test-host` and `test-graph` run one part. Per package: `(cd vsts/echo && flutter test)`.
- Validate built plugins: `./validate_echo.sh`, `./validate_flutter_reverb.sh`.

## CI
- `make ci` = deslop, lint, test, build. `.github/workflows/ci.yml` has one root `CI` job (`if: always()`, `needs:` every job); a new job goes in its `needs:`.
- ❌ weaken gates or merge red — fix the code.

## Code
- Files < 400 LOC, tests too. Functions < 20 LOC.
- FP: pure functions, named constants. Classes and mutable state only where Flutter, the VST3 SDK or per-sample DSP state need them.
- **Dart:** ❌ `late`; ❌ `if` — use pattern matching or ternaries; `///` docs on all public functions.
- **Shipped DSP is native machine code:** a `dart compile exe` worker. ❌ `dart run`, JIT, or anything needing an installed Dart SDK.
- Spec IDs: hierarchical slugs (`[GROUP-TOPIC-DETAIL]`), ❌ numbers; cite them in code and tests.

## Architecture
- **`flutter_vst3/`** — the plugin framework. `native/cmake/VST3Bridge.cmake` provides `add_dart_vst3_plugin`, which generates all C++ from `native/templates/` and a Dart parameter file. New plugin: [`flutter_vst3/create_plugin_guide.md`](flutter_vst3/create_plugin_guide.md).
- **`vsts/`** — self-contained plugins, each building its own `.vst3`: `flutter_reverb`, `echo`. Echo's editor is the interactive test UI: `cd vsts/echo && flutter run`.
- **`dart_vst_host/`, `dart_vst_graph/`** — Dart FFI over C++ in each package's `native/`. C APIs: `native/include/dart_vst_host.h`, `native/include/dvh_graph.h`. The graph connects plugin, mixer, splitter and gain nodes.
- **Plugin process model** — read [`docs/FLUTTER_UI_SPEC.md`](docs/FLUTTER_UI_SPEC.md) before touching it. The VST3 module and Flutter editor run in the host; DSP runs in one worker process per instance, over shared memory.
- **Setup:** `make setup` fetches the SDK; `VST3_SDK_DIR` overrides the default `vst3sdk/`. Needs CMake 3.20+, C++17, Dart, Flutter.
- **Linux:** editors embed through X11 only: `GDK_BACKEND=x11 flutter run`. ❌ Wayland.

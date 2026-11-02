# agent-pmo:372ce7f
# Flutter VST3 toolkit: run from the repository root.
.DEFAULT_GOAL := reverb
.SHELLFLAGS := -ec
VST3_SDK_DIR ?= $(CURDIR)/vst3sdk
export VST3_SDK_DIR
FLUTTER_BUILD_MODE ?= release
.PHONY: all lint fmt ci setup build native plugin test test-native test-host test-graph dart-deps reverb-deps echo-deps flutter-deps reverb reverb-vst reverb-build-only echo echo-vst echo-build-only echo-flutter install clean clean-native clean-plugin check-env help

all: reverb
build: native dart-deps plugin
native:
	test -d "$(VST3_SDK_DIR)"
	cmake -S dart_vst_host/native -B dart_vst_host/native/build -DCMAKE_BUILD_TYPE=Release
	cmake --build dart_vst_host/native/build --parallel
	cp dart_vst_host/native/build/libdart_vst_host.* .
	cp dart_vst_host/native/build/libdart_vst_host.* dart_vst_host/
	cmake -S dart_vst_graph/native -B dart_vst_graph/native/build -DCMAKE_BUILD_TYPE=Release
	cmake --build dart_vst_graph/native/build --parallel
	cp dart_vst_graph/native/build/libdart_vst_graph.* .
	cp dart_vst_graph/native/build/libdart_vst_graph.* dart_vst_graph/

dart-deps:
	cd dart_vst_host && dart pub get
	cd dart_vst_graph && dart pub get
	cd flutter_vst3 && flutter pub get
	cd vsts/echo && flutter pub get
	cd vsts/flutter_reverb && flutter pub get
reverb-deps:
	cd flutter_vst3 && flutter pub get
	cd vsts/flutter_reverb && flutter pub get
echo-deps:
	cd flutter_vst3 && flutter pub get
	cd vsts/echo && flutter pub get
flutter-deps: dart-deps

reverb reverb-vst reverb-build-only: reverb-deps
	cmake -S vsts/flutter_reverb -B vsts/flutter_reverb/build -DCMAKE_BUILD_TYPE=Release
	cmake --build vsts/flutter_reverb/build --parallel
echo-flutter: echo-deps
	case "$$(uname)" in Darwin) platform=macos;; Linux) platform=linux;; MINGW*|MSYS*|CYGWIN*) platform=windows;; *) echo 'Unsupported platform' >&2; exit 1;; esac; \
	cd vsts/echo && flutter build $$platform --$(FLUTTER_BUILD_MODE)
echo echo-vst echo-build-only: echo-flutter
	cmake -S vsts/echo -B vsts/echo/build -DCMAKE_BUILD_TYPE=Release
	cmake --build vsts/echo/build --parallel
plugin: reverb echo

lint: dart-deps
	cd dart_vst_host && dart analyze
	cd dart_vst_graph && dart analyze
	cd flutter_vst3 && flutter analyze
	cd vsts/flutter_reverb && flutter analyze
	cd vsts/echo && flutter analyze
fmt:
	dart format dart_vst_host/lib dart_vst_host/test dart_vst_graph/lib dart_vst_graph/test flutter_vst3/lib flutter_vst3/test vsts/echo/lib vsts/echo/test vsts/flutter_reverb/lib vsts/flutter_reverb/test
ci: lint test build
setup:
	./setup.sh
test: native dart-deps test-native
	cd dart_vst_host && dart test
	cd dart_vst_graph && dart test
	cd flutter_vst3 && flutter test
	cd vsts/flutter_reverb && flutter test
	cd vsts/echo && flutter test
test-native:
	bash flutter_vst3/test/native/run.sh
test-host: native
	cd dart_vst_host && dart pub get && dart test
test-graph: native
	cd dart_vst_graph && dart pub get && dart test

install: plugin
	case "$$(uname)" in Darwin) dest="$$HOME/Library/Audio/Plug-Ins/VST3";; Linux) dest="$$HOME/.vst3";; MINGW*|MSYS*|CYGWIN*) dest="$$LOCALAPPDATA/Programs/Common/VST3";; *) echo 'Unsupported platform' >&2; exit 1;; esac; \
	mkdir -p "$$dest"; \
	for name in echo flutter_reverb; do rm -rf "$$dest/$$name.vst3"; cp -R "vsts/$$name/build/VST3/Release/$$name.vst3" "$$dest/"; done
clean: clean-native clean-plugin
	rm -f libdart_vst_host.* libdart_vst_graph.* dart_vst_host/libdart_vst_host.* dart_vst_graph/libdart_vst_graph.*
clean-native:
	rm -rf dart_vst_host/native/build dart_vst_graph/native/build
clean-plugin:
	rm -rf vsts/echo/build vsts/flutter_reverb/build
check-env:
	test -d "$(VST3_SDK_DIR)"
	command -v cmake
	command -v dart
	command -v flutter
help:
	@echo 'Targets: lint, fmt, ci, setup, native, dart-deps, reverb, echo, plugin, test, test-native, test-host, test-graph, install, clean'
	@echo 'Set VST3_SDK_DIR to the Steinberg SDK root. Flutter is required for plugin packages.'

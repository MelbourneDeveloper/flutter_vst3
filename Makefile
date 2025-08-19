# Dart VST3 Toolkit Makefile
# Builds VST3 plugins from pure Dart source code

.PHONY: all build test clean clean-native clean-plugin help dart-deps flutter-deps reverb-vst install

# Default target - build the Flutter Dart Reverb VST3
all: reverb-vst

# Build all components (host, graph, and reverb VST)
build: native plugin dart-deps flutter-deps reverb-vst

# Build the Flutter Dart Reverb VST3 plugin
reverb-vst: native reverb-deps
	@echo "Building Flutter Dart Reverb VST3 plugin..."
	@mkdir -p plugin/build
	@cd plugin/build && cmake .. && make
	@echo "✅ VST3 plugin built: plugin/build/FlutterDartReverb.vst3"

# Run all tests
test: build
	@echo "Running dart_vst3_bridge tests..."
	cd dart_vst3_bridge && dart test || true
	@echo "Running flutter_reverb tests..."
	cd flutter_reverb && dart test || true
	@echo "Running dart_vst_host tests..."
	cd dart_vst_host && dart test
	@echo "Running dart_vst_graph tests..."
	cd dart_vst_graph && dart test

# Build native library (required for all Dart components)
native: clean-native
	@echo "Building native library..."
	@test -n "$(VST3_SDK_DIR)" || (echo "Error: VST3_SDK_DIR environment variable not set" && echo "Please set it to the root of Steinberg VST3 SDK" && exit 1)
	mkdir -p /workspace/native/build
	cmake -S /workspace/native -B /workspace/native/build
	make -C /workspace/native/build
	@echo "Copying native library to all required locations..."
	cp /workspace/native/build/libdart_vst_host.* /workspace/ 2>/dev/null || true
	cp /workspace/native/build/libdart_vst_host.* /workspace/dart_vst_host/ 2>/dev/null || true
	cp /workspace/native/build/libdart_vst_host.* /workspace/dart_vst_graph/ 2>/dev/null || true

# Build VST3 plugin
plugin: native clean-plugin
	@echo "Building VST3 plugin..."
	@test -n "$(VST3_SDK_DIR)" || (echo "Error: VST3_SDK_DIR environment variable not set" && echo "Please set it to the root of Steinberg VST3 SDK" && exit 1)
	mkdir -p /workspace/plugin/build
	cmake -S /workspace/plugin -B /workspace/plugin/build
	make -C /workspace/plugin/build

# Install Dart dependencies for all packages
dart-deps:
	@echo "Installing dart_vst3_bridge dependencies..."
	dart pub get --directory=/workspace/dart_vst3_bridge
	@echo "Installing dart_vst_host dependencies..."
	dart pub get --directory=/workspace/dart_vst_host
	@echo "Installing dart_vst_graph dependencies..."
	dart pub get --directory=/workspace/dart_vst_graph

# Install reverb plugin dependencies
reverb-deps:
	@echo "Installing Flutter Dart Reverb dependencies..."
	dart pub get --directory=/workspace/dart_vst3_bridge
	dart pub get --directory=/workspace/flutter_reverb

# Install Flutter dependencies
flutter-deps:
	@echo "Installing Flutter dependencies..."
	flutter pub get --directory=/workspace/flutter_ui

# Install VST3 plugin to system location (macOS/Linux)
install: reverb-vst
	@echo "Installing FlutterDartReverb.vst3..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		mkdir -p ~/Library/Audio/Plug-Ins/VST3/; \
		cp -r plugin/build/FlutterDartReverb.vst3 ~/Library/Audio/Plug-Ins/VST3/; \
		echo "✅ Installed to ~/Library/Audio/Plug-Ins/VST3/"; \
	elif [ "$$(uname)" = "Linux" ]; then \
		mkdir -p ~/.vst3/; \
		cp plugin/build/FlutterDartReverb.vst3 ~/.vst3/; \
		echo "✅ Installed to ~/.vst3/"; \
	else \
		echo "⚠️  Manual installation required on this platform"; \
	fi

# Clean all build artifacts
clean: clean-native clean-plugin
	@echo "Removing native libraries from all locations..."
	rm -f libdart_vst_host.*
	rm -f *.dylib *.so *.dll
	rm -f dart_vst_host/libdart_vst_host.*
	rm -f dart_vst_graph/libdart_vst_host.*

# Clean native library build
clean-native:
	@echo "Cleaning native build..."
	rm -rf /workspace/native/build

# Clean plugin build
clean-plugin:
	@echo "Cleaning plugin build..."
	rm -rf /workspace/plugin/build

# Run Flutter app
run-flutter: flutter-deps
	cd flutter_ui && flutter run

# Run dart_vst_host tests only
test-host: native dart-deps
	cd dart_vst_host && dart test

# Run dart_vst_graph tests only
test-graph: native dart-deps
	cd dart_vst_graph && dart test

# Check environment
check-env:
	@echo "Checking environment..."
	@test -n "$(VST3_SDK_DIR)" && echo "✅ VST3_SDK_DIR = $(VST3_SDK_DIR)" || echo "❌ VST3_SDK_DIR not set"
	@command -v cmake >/dev/null 2>&1 && echo "✅ CMake available" || echo "❌ CMake not found"
	@command -v dart >/dev/null 2>&1 && echo "✅ Dart available" || echo "❌ Dart not found"
	@command -v flutter >/dev/null 2>&1 && echo "✅ Flutter available" || echo "❌ Flutter not found"

# Help
help:
	@echo "Dart VST3 Toolkit Build System"
	@echo "==============================="
	@echo ""
	@echo "🎯 PRIMARY TARGET:"
	@echo "  all (default)   - Build Flutter Dart Reverb VST3 plugin"
	@echo ""
	@echo "🎛️ REVERB VST TARGETS:"
	@echo "  reverb-vst      - Build Flutter Dart Reverb VST3 plugin"
	@echo "  reverb-deps     - Install reverb plugin dependencies only" 
	@echo "  install         - Build and install VST3 plugin to system"
	@echo ""
	@echo "🏗️ BUILD TARGETS:"
	@echo "  build           - Build all components (host, graph, reverb)"
	@echo "  native          - Build native library with VST3 bridge"
	@echo "  plugin          - Build generic VST3 plugin (old)"
	@echo ""
	@echo "📦 DEPENDENCY TARGETS:"
	@echo "  dart-deps       - Install all Dart package dependencies"
	@echo "  flutter-deps    - Install Flutter UI dependencies"
	@echo ""
	@echo "🧪 TESTING TARGETS:"
	@echo "  test            - Run all tests (bridge, reverb, host, graph)"
	@echo "  test-host       - Run dart_vst_host tests only"
	@echo "  test-graph      - Run dart_vst_graph tests only"
	@echo ""
	@echo "🧹 CLEANUP TARGETS:"
	@echo "  clean           - Clean all build artifacts"
	@echo "  clean-native    - Clean native library build only"
	@echo "  clean-plugin    - Clean plugin build only"
	@echo ""
	@echo "🔧 UTILITY TARGETS:"
	@echo "  run-flutter     - Run Flutter UI application"
	@echo "  check-env       - Check build environment setup"
	@echo "  help            - Show this help message"
	@echo ""
	@echo "📋 EXAMPLES:"
	@echo "  make                    # Build FlutterDartReverb.vst3"
	@echo "  make clean reverb-vst   # Clean build and rebuild reverb VST"
	@echo "  make install            # Build and install to DAW plugins folder"
	@echo ""
	@echo "🔧 PREREQUISITES:"
	@echo "  • Set VST3_SDK_DIR environment variable (or use bundled SDK)"
	@echo "  • Install CMake 3.20+, Dart SDK 3.0+, and Flutter"
	@echo ""
	@echo "📁 PACKAGES:"
	@echo "  • dart_vst3_bridge/     - FFI bridge for any Dart VST3 plugin"
	@echo "  • flutter_reverb/       - Pure Dart reverb VST3 implementation"
	@echo "  • dart_vst_host/        - VST3 hosting for Dart applications"
	@echo "  • dart_vst_graph/       - Audio graph system with VST routing"
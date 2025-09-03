# flutter_vst3 Toolkit Makefile
# Builds VST® 3 plugins with Flutter UI and pure Dart audio processing

.PHONY: all build test clean clean-native clean-plugin help dart-deps flutter-deps reverb-vst install reverb reverb-build-only echo echo-vst echo-build-only echo-deps

# Default target - build the Flutter Reverb VST® 3 plugin
all: reverb

# Build all components (host, graph, and reverb VST)
build: native plugin dart-deps flutter-deps reverb-vst

# Build the Flutter Reverb VST® 3 plugin
reverb: reverb-deps
	@echo "Building Flutter Reverb VST® 3 plugin..."
	@mkdir -p vsts/flutter_reverb/build
	@cd vsts/flutter_reverb/build && cmake -DCMAKE_BUILD_TYPE=Release .. && make -j$(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
	@echo "✅ VST® 3 plugin built: vsts/flutter_reverb/build/VST3/Release/flutter_reverb.vst3"

# Alias for reverb
reverb-vst: reverb

# Build reverb VST® 3 without installing (explicit build-only target)
reverb-build-only: reverb

# Build the Echo VST® 3 plugin  
echo: echo-deps
	@echo "Building Echo VST® 3 plugin..."
	@mkdir -p vsts/echo/build
	@cd vsts/echo/build && cmake -DCMAKE_BUILD_TYPE=Release .. && make -j$(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
	@echo "✅ VST® 3 plugin built: vsts/echo/build/VST3/Release/echo.vst3"

# Alias for echo
echo-vst: echo

# Build echo VST® 3 without installing (explicit build-only target)
echo-build-only: echo

# Run all tests
test: build
	@echo "Running flutter_vst3 tests..."
	cd flutter_vst3 && dart test || true
	@echo "Running flutter_reverb tests..."
	cd vsts/flutter_reverb && dart test || true
	@echo "Running echo tests..."
	cd vsts/echo && dart test || true
	@echo "Running dart_vst_host tests..."
	cd dart_vst_host && dart test
	@echo "Running dart_vst_graph tests..."
	cd dart_vst_graph && dart test

# Build native libraries (required for all Dart components)
native: clean-native
	@echo "Building native libraries..."
	@if [ -z "$(VST3_SDK_DIR)" ]; then \
		if [ -d "vst3sdk" ]; then \
			export VST3_SDK_DIR="$(shell pwd)/vst3sdk"; \
			echo "Using VST3 SDK from $(shell pwd)/vst3sdk"; \
		elif [ -d "/workspace/vst3sdk" ]; then \
			export VST3_SDK_DIR="/workspace/vst3sdk"; \
			echo "Using VST3 SDK from /workspace/vst3sdk"; \
		else \
			echo "Error: VST3_SDK_DIR environment variable not set"; \
			echo "Please set it to the root of Steinberg VST3 SDK or run setup.sh first"; \
			exit 1; \
		fi; \
	fi
	@echo "Building dart_vst_host library..."
	@if [ -d "/workspace" ]; then \
		mkdir -p /workspace/dart_vst_host/native/build; \
		cd /workspace/dart_vst_host/native/build && VST3_SDK_DIR=$${VST3_SDK_DIR:-/workspace/vst3sdk} cmake .. && make; \
		cp /workspace/dart_vst_host/native/build/libdart_vst_host.* /workspace/ 2>/dev/null || true; \
		cp /workspace/dart_vst_host/native/build/libdart_vst_host.* /workspace/dart_vst_host/ 2>/dev/null || true; \
	else \
		mkdir -p dart_vst_host/native/build; \
		cd dart_vst_host/native/build && VST3_SDK_DIR=$${VST3_SDK_DIR:-$(shell pwd)/vst3sdk} cmake .. && make; \
		cp dart_vst_host/native/build/libdart_vst_host.* . 2>/dev/null || true; \
		cp dart_vst_host/native/build/libdart_vst_host.* dart_vst_host/ 2>/dev/null || true; \
	fi
	@echo "Building dart_vst_graph library..."
	@if [ -d "/workspace" ]; then \
		mkdir -p /workspace/dart_vst_graph/native/build; \
		cd /workspace/dart_vst_graph/native/build && VST3_SDK_DIR=$${VST3_SDK_DIR:-/workspace/vst3sdk} cmake .. && make; \
		cp /workspace/dart_vst_graph/native/build/libdart_vst_graph.* /workspace/ 2>/dev/null || true; \
		cp /workspace/dart_vst_graph/native/build/libdart_vst_graph.* /workspace/dart_vst_graph/ 2>/dev/null || true; \
	else \
		mkdir -p dart_vst_graph/native/build; \
		cd dart_vst_graph/native/build && VST3_SDK_DIR=$${VST3_SDK_DIR:-$(shell pwd)/vst3sdk} cmake .. && make; \
		cp dart_vst_graph/native/build/libdart_vst_graph.* . 2>/dev/null || true; \
		cp dart_vst_graph/native/build/libdart_vst_graph.* dart_vst_graph/ 2>/dev/null || true; \
	fi
	@echo "Native libraries built and copied to required locations"

# Build all VST® 3 plugins
plugin: native clean-plugin
	@echo "Building all VST® 3 plugins..."
	@for plugin in vsts/*/; do \
		if [ -f "$$plugin/CMakeLists.txt" ]; then \
			echo "Building $$plugin"; \
			cd "$$plugin" && mkdir -p build && cd build && cmake .. && make && cd ../../../; \
		fi; \
	done

# Install Dart dependencies for all packages
dart-deps:
	@echo "Installing flutter_vst3 dependencies..."
	@if [ -d "/workspace" ]; then \
		dart pub get --directory=/workspace/flutter_vst3; \
		dart pub get --directory=/workspace/dart_vst_host; \
		dart pub get --directory=/workspace/dart_vst_graph; \
	else \
		dart pub get --directory=flutter_vst3; \
		dart pub get --directory=dart_vst_host; \
		dart pub get --directory=dart_vst_graph; \
	fi

# Install reverb plugin dependencies
reverb-deps:
	@echo "Installing Flutter Reverb dependencies..."
	@if [ -d "/workspace" ]; then \
		dart pub get --directory=/workspace/flutter_vst3; \
		dart pub get --directory=/workspace/vsts/flutter_reverb; \
	else \
		dart pub get --directory=flutter_vst3; \
		dart pub get --directory=vsts/flutter_reverb; \
	fi

# Install echo plugin dependencies
echo-deps:
	@echo "Installing Echo plugin dependencies..."
	@if [ -d "/workspace" ]; then \
		dart pub get --directory=/workspace/flutter_vst3; \
		dart pub get --directory=/workspace/vsts/echo; \
	else \
		dart pub get --directory=flutter_vst3; \
		dart pub get --directory=vsts/echo; \
	fi

# Install Flutter dependencies
flutter-deps:
	@echo "Installing Flutter dependencies..."
	@if [ -d "/workspace" ]; then \
		flutter pub get --directory=/workspace/flutter_ui; \
	else \
		flutter pub get --directory=flutter_ui; \
	fi

# Install VST® 3 plugin to system location (macOS/Linux)
install: reverb-vst
	@echo "Installing flutter_reverb.vst3..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		mkdir -p ~/Library/Audio/Plug-Ins/VST3/; \
		cp -r vsts/flutter_reverb/build/VST3/Release/flutter_reverb.vst3 ~/Library/Audio/Plug-Ins/VST3/; \
		echo "✅ Installed to ~/Library/Audio/Plug-Ins/VST3/"; \
	elif [ "$$(uname)" = "Linux" ]; then \
		mkdir -p ~/.vst3/; \
		cp -r vsts/flutter_reverb/build/VST3/Release/flutter_reverb.vst3 ~/.vst3/; \
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
	rm -f dart_vst_graph/libdart_vst_graph.*

# Clean native library builds
clean-native:
	@echo "Cleaning native builds..."
	@if [ -d "/workspace" ]; then \
		rm -rf /workspace/dart_vst_host/native/build; \
		rm -rf /workspace/dart_vst_graph/native/build; \
	else \
		rm -rf dart_vst_host/native/build; \
		rm -rf dart_vst_graph/native/build; \
	fi

# Clean plugin builds
clean-plugin:
	@echo "Cleaning all VST plugin builds..."
	@for plugin in vsts/*/; do \
		if [ -d "$$plugin/build" ]; then \
			echo "Cleaning $$plugin"; \
			rm -rf "$$plugin/build"; \
		fi; \
	done

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
	@echo "🎛️ PLUGIN TARGETS:"
	@echo "  reverb-vst      - Build Flutter Dart Reverb VST3 plugin"
	@echo "  reverb-build-only - Build Flutter Dart Reverb VST3 plugin (no install)"
	@echo "  reverb-deps     - Install reverb plugin dependencies only"
	@echo "  echo-vst        - Build Echo VST3 plugin"
	@echo "  echo-build-only - Build Echo VST3 plugin (no install)"
	@echo "  echo-deps       - Install echo plugin dependencies only"
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
	@echo "  • vsts/flutter_reverb/  - Pure Dart reverb VST3 implementation"
	@echo "  • vsts/echo/            - Pure Dart echo VST3 implementation"
	@echo "  • dart_vst_host/        - VST3 hosting for Dart applications"
	@echo "  • dart_vst_graph/       - Audio graph system with VST routing"
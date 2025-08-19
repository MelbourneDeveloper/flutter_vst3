# VST Project Makefile
# Builds native libraries and runs all tests

.PHONY: all build test clean clean-native clean-plugin help dart-deps flutter-deps

# Default target
all: build test

# Build all components
build: native plugin dart-deps flutter-deps

# Run all tests
test: build
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

# Install Dart dependencies
dart-deps:
	@echo "Installing dart_vst_host dependencies..."
	dart pub get --directory=/workspace/dart_vst_host
	@echo "Installing dart_vst_graph dependencies..."
	dart pub get --directory=/workspace/dart_vst_graph

# Install Flutter dependencies
flutter-deps:
	@echo "Installing Flutter dependencies..."
	flutter pub get --directory=/workspace/flutter_ui

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
	@echo "VST Project Build System"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Set VST3_SDK_DIR environment variable to Steinberg VST3 SDK root"
	@echo "  - Ensure CMake 3.20+, Dart SDK 3.0+, and Flutter are installed"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build everything and run tests (default)"
	@echo "  build       - Build native library, plugin, and install dependencies"
	@echo "  test        - Run all Dart tests (requires native library)"
	@echo "  clean       - Clean all build artifacts and libraries"
	@echo ""
	@echo "Component-specific targets:"
	@echo "  native      - Build native library (deletes and regenerates)"
	@echo "  plugin      - Build VST3 plugin"
	@echo "  dart-deps   - Install Dart package dependencies"
	@echo "  flutter-deps- Install Flutter dependencies"
	@echo ""
	@echo "Testing targets:"
	@echo "  test-host   - Run dart_vst_host tests only"
	@echo "  test-graph  - Run dart_vst_graph tests only"
	@echo ""
	@echo "Other targets:"
	@echo "  run-flutter - Run Flutter UI application"
	@echo "  check-env   - Check build environment setup"
	@echo "  clean-native- Clean native library build only"
	@echo "  clean-plugin- Clean plugin build only"
	@echo "  help        - Show this help message"
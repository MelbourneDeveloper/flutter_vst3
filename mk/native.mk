# Private targets for a package with a native library. Set NATIVE_LIB first.
PACKAGE_TOOL ?= dart
include $(dir $(lastword $(MAKEFILE_LIST)))package.mk
.PHONY: _native _clean

_native:
	test -d "$(VST3_SDK_DIR)"
	cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release
	cmake --build native/build --parallel
	cp native/build/lib$(NATIVE_LIB).* "$(REPO_ROOT)/"
	cp native/build/lib$(NATIVE_LIB).* .
_clean:
	rm -rf native/build
	rm -f "$(REPO_ROOT)"/lib$(NATIVE_LIB).* lib$(NATIVE_LIB).*

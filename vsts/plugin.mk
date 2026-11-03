# Targets every plugin has. Set PLUGIN first.
PACKAGE_TOOL ?= flutter
BUNDLE ?= build/VST3/Release/$(PLUGIN).vst3
include ../../mk/package.mk
.DEFAULT_GOAL := build
.PHONY: build deploy _framework-deps _clean

## build: Build this plugin's .vst3 bundle.
build: _deps
	cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
	cmake --build build --parallel

## deploy: Build this plugin, then copy it to the folder VST3 hosts scan.
deploy: build
	test -d "$(BUNDLE)"
	case "$$(uname)" in Darwin) dest="$$HOME/Library/Audio/Plug-Ins/VST3";; Linux) dest="$$HOME/.vst3";; MINGW*|MSYS*|CYGWIN*) dest="$$LOCALAPPDATA/Programs/Common/VST3";; *) echo 'Unsupported platform' >&2; exit 1;; esac; \
	mkdir -p "$$dest" && \
	rm -rf "$$dest/$(PLUGIN).vst3" && \
	cp -R "$(BUNDLE)" "$$dest/" && \
	echo "Deployed $(PLUGIN) to $$dest"

_deps: _framework-deps
_framework-deps:
	$(MAKE) -C ../../flutter_vst3 _deps
_clean:
	rm -rf build

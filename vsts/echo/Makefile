PLUGIN ?= echo
FLUTTER_BUILD_MODE ?= release
include ../plugin.mk
.PHONY: _flutter-ui

# Echo's editor is a Flutter app, which goes inside the bundle.
build: _flutter-ui
_flutter-ui: _deps
	case "$$(uname)" in Darwin) platform=macos;; Linux) platform=linux;; MINGW*|MSYS*|CYGWIN*) platform=windows;; *) echo 'Unsupported platform' >&2; exit 1;; esac; \
	flutter build $$platform --$(FLUTTER_BUILD_MODE)

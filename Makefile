# agent-pmo:372ce7f
# Flutter VST3 toolkit: run from the repository root. Each package has its own
# Makefile; targets starting with _ are private to the build.
.DEFAULT_GOAL := reverb
include mk/common.mk
PACKAGES ?= dart_vst_host dart_vst_graph flutter_vst3 vsts/flutter_reverb vsts/echo
.PHONY: help deploy deploy-echo deploy-reverb echo reverb build native dart-deps lint fmt deslop test coverage-check ci setup clean _plugin _test-native _test-host _test-graph _check-env

## deploy: Build Echo and Reverb, then copy both to the folder VST3 hosts scan.
## deploy-echo: Build Echo, then copy it to that folder.
## deploy-reverb: Build Reverb, then copy it to that folder.
## echo: Build echo.vst3.
## reverb: Build flutter_reverb.vst3.
deploy deploy-echo deploy-reverb echo reverb:
	$(MAKE) -C vsts $@

## build: Build the native libraries and both plugins.
build: native dart-deps _plugin
_plugin:
	$(MAKE) -C vsts build

## native: Build the host and graph libraries.
native:
	$(MAKE) -C dart_vst_graph _native

## dart-deps: Resolve dependencies in every package.
dart-deps:
	for package in $(PACKAGES); do $(MAKE) -C "$$package" _deps || exit 1; done

## lint: Analyze every package.
lint: dart-deps
	for package in $(PACKAGES); do $(MAKE) -C "$$package" _lint || exit 1; done

## fmt: Format every package.
fmt:
	dart format dart_vst_host/lib dart_vst_host/test dart_vst_graph/lib dart_vst_graph/test flutter_vst3/lib flutter_vst3/test vsts/echo/lib vsts/echo/test vsts/flutter_reverb/lib vsts/flutter_reverb/test

## deslop: Fail if duplication is above the ceiling in .deslop.toml.
deslop:
	deslop . --nohtml --nojson --no-color --log-level error

## test: Run every test with coverage.
test: native dart-deps _test-native
	for package in $(PACKAGES); do $(MAKE) -C "$$package" _test || exit 1; done
_test-native:
	bash flutter_vst3/test/native/run.sh
_test-host: native
	$(MAKE) -C dart_vst_host _deps _test
_test-graph: native
	$(MAKE) -C dart_vst_graph _deps _test

## coverage-check: Check coverage reports against coverage-thresholds.json. Runs no tests.
coverage-check:
	python3 flutter_vst3/test/native/coverage_check.py

## ci: Run the same phases as CI: build, test, coverage.
ci: deslop lint build test coverage-check

## setup: Fetch the VST3 SDK and build the native libraries.
setup:
	./setup.sh

## clean: Delete all build output.
clean:
	$(MAKE) -C dart_vst_host _clean
	$(MAKE) -C dart_vst_graph _clean
	$(MAKE) -C vsts _clean

_check-env:
	test -d "$(VST3_SDK_DIR)"
	command -v cmake
	command -v dart
	command -v flutter

## help: List the public targets.
help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST)
	@echo 'Set VST3_SDK_DIR to the Steinberg SDK root. Flutter is required for plugin packages.'

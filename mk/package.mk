# Private targets every Dart package has. Set PACKAGE_TOOL to dart or flutter first.
include $(dir $(lastword $(MAKEFILE_LIST)))common.mk
PACKAGE ?= $(patsubst $(REPO_ROOT)/%,%,$(CURDIR))
.PHONY: _deps _lint _test

_deps:
	$(PACKAGE_TOOL) pub get
_lint:
	$(PACKAGE_TOOL) analyze
_test:
	bash "$(REPO_ROOT)/flutter_vst3/test/native/run_package_coverage.sh" "$(PACKAGE)"

# Settings every Makefile shares. macOS ships Make 3.81, which ignores .SHELLFLAGS,
# so a recipe line that runs several commands has to stop on failure itself.
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
VST3_SDK_DIR ?= $(REPO_ROOT)/vst3sdk
export VST3_SDK_DIR
.SHELLFLAGS = -ec

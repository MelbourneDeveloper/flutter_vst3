NATIVE_LIB ?= dart_vst_graph
include ../mk/native.mk
.PHONY: _host-native

# The graph library links against the host library.
_native: _host-native
_host-native:
	$(MAKE) -C ../dart_vst_host _native

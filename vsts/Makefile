# Every plugin. Each has its own Makefile in its folder.
.DEFAULT_GOAL := build
.PHONY: build deploy echo reverb deploy-echo deploy-reverb _clean

build: echo reverb
deploy: deploy-echo deploy-reverb
echo:
	$(MAKE) -C echo build
reverb:
	$(MAKE) -C flutter_reverb build
deploy-echo:
	$(MAKE) -C echo deploy
deploy-reverb:
	$(MAKE) -C flutter_reverb deploy
_clean:
	$(MAKE) -C echo _clean
	$(MAKE) -C flutter_reverb _clean

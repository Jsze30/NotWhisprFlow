APP_NAME    := WhisperFlow
BUILD_DIR   := .build
APP_BUNDLE  := $(APP_NAME).app
CONFIG      := release

# Prefer a stable Apple Development identity so the bundle's code identity stays
# constant across rebuilds. Ad-hoc signing (`--sign -`) changes identity every
# build, which makes macOS revoke Microphone / Accessibility / Input Monitoring
# grants each time. Override with `make SIGN_IDENTITY=...`; falls back to ad-hoc
# when no Apple Development identity is present.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | awk '/Apple Development/{print $$2; exit}')

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c $(CONFIG) --arch arm64 --arch x86_64

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp Resources/waveform.svg $(APP_BUNDLE)/Contents/Resources/waveform.svg
	cp Resources/click.mp3 $(APP_BUNDLE)/Contents/Resources/click.mp3
	cp $(BUILD_DIR)/apple/Products/Release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) \
	  || cp $(BUILD_DIR)/$(CONFIG)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
	  echo "Signing $(APP_BUNDLE) with stable identity $(SIGN_IDENTITY)"; \
	  codesign --force --deep --sign $(SIGN_IDENTITY) $(APP_BUNDLE); \
	else \
	  echo "No Apple Development identity found — ad-hoc signing (TCC grants reset each build)"; \
	  codesign --force --deep --sign - $(APP_BUNDLE); \
	fi
	@echo "Built $(APP_BUNDLE). Open it with: open $(APP_BUNDLE)"

run: bundle
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) $(APP_BUNDLE)

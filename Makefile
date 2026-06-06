APP_NAME    := WhisperFlow
BUILD_DIR   := .build
APP_BUNDLE  := $(APP_NAME).app
CONFIG      := release

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
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE). Open it with: open $(APP_BUNDLE)"

run: bundle
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) $(APP_BUNDLE)

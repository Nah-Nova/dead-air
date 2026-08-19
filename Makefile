APP_NAME = Dead Air
PROJECT = DeadAir.xcodeproj
SCHEME = Dead Air

DERIVED_DATA = $(PWD)/build/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app

.PHONY: build sign install run clean

build:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
	xcodebuild \
		-project $(PROJECT) \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		build

sign:
	codesign --force --deep -s - "$(APP_PATH)"

install:
	mkdir -p ~/Applications
	rm -rf ~/Applications/"$(APP_NAME).app"
	cp -R "$(APP_PATH)" ~/Applications/

# Prefers the installed copy, so `make install run` runs what it just installed rather
# than the build directory binary. Accessibility approval follows the installed path.
run:
	@if [ -d ~/Applications/"$(APP_NAME).app" ]; then \
		open ~/Applications/"$(APP_NAME).app"; \
	else \
		open "$(APP_PATH)"; \
	fi

clean:
	rm -rf "$(PWD)/build"

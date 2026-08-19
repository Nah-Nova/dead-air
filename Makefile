APP_NAME = Dead Air
PROJECT = DeadAir.xcodeproj
SCHEME = Dead Air

DERIVED_DATA = $(PWD)/build/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app

.PHONY: build sign install run test package clean

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

test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
	xcodebuild test \
		-project $(PROJECT) \
		-scheme "$(SCHEME)" \
		-destination 'platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO

# The release artefact, plus the checksum beside it. Auto-update refuses a release with no
# checksum, so the two are produced together and never separately.
package: sign
	@VERSION=$$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$(APP_PATH)/Contents/Info.plist"); \
	ZIP="$(PWD)/build/DeadAir-$$VERSION-universal.zip"; \
	rm -f "$$ZIP" "$$ZIP.sha256"; \
	ditto -c -k --sequesterRsrc --keepParent "$(APP_PATH)" "$$ZIP"; \
	cd "$(PWD)/build" && shasum -a 256 "DeadAir-$$VERSION-universal.zip" > "DeadAir-$$VERSION-universal.zip.sha256"; \
	echo "packaged:"; ls -lh "$$ZIP" "$$ZIP.sha256" | awk '{print "  " $$5 "  " $$9}'; \
	cat "$$ZIP.sha256"

clean:
	rm -rf "$(PWD)/build"

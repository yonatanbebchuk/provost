# Provost macOS app — build helpers.
# `xcode-select` on the demo Mac points at Command Line Tools, so we point xcodebuild
# at Xcode.app explicitly. Override with `make DEVELOPER_DIR=... build` if needed.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

SCHEME      := Provost
PROJECT     := Provost.xcodeproj
CONFIG      := Debug
DERIVED     := build
APP         := $(DERIVED)/Build/Products/$(CONFIG)/Provost.app
XCB         := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

.PHONY: gen build run test fixtures clean

gen:            ## Regenerate Provost.xcodeproj from project.yml
	xcodegen generate --quiet

$(PROJECT): project.yml
	xcodegen generate --quiet

build: gen      ## Regenerate project (picks up new files) and build Debug
	$(XCB) build | tail -n 5

run: build      ## Build and open the app
	open $(APP)

test: gen       ## Run unit tests
	$(XCB) test | grep -E "Test Suite|Test Case|error:|passed|failed" | tail -n 40

fixtures:       ## Regenerate Resources/fixtures from scripts/make_fixtures.py
	python3 scripts/make_fixtures.py && python3 scripts/import_diff_studio.py

clean:
	rm -rf $(DERIVED) $(PROJECT)

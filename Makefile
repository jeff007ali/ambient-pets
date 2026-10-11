# Ambient Pets — build entry points.
#   make app        build build/AmbientPets.app (SwiftPM + bundle + codesign)
#   make run        (re)launch the app bundle
#   make run-fg     run in the foreground with logs in this terminal
#   make test       PetCore unit tests
#   make validate-packs
#   make art        build pet sprite sheets from the downloaded source art
#   make placeholder-art   original placeholder sprites (pipeline testing)

CONFIG     ?= debug
APP_NAME    = AmbientPets
BUILD_DIR   = build
APP         = $(BUILD_DIR)/$(APP_NAME).app
PETKIT      = Packages/PetKit
DEV_DIR    := $(shell xcode-select -p 2>/dev/null)

# The Command Line Tools don't find their own swift-testing macro plugin; point at it explicitly.
ifneq (,$(findstring CommandLineTools,$(DEV_DIR)))
TEST_FLAGS  = -Xswiftc -plugin-path -Xswiftc $(DEV_DIR)/usr/lib/swift/host/plugins/testing
endif

# A stable signing identity keeps TCC grants (Accessibility, Screen Recording) across rebuilds.
# Falls back to ad-hoc signing ("-") when no Apple Development certificate is installed.
SIGN_ID    ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/')
ifeq ($(SIGN_ID),)
SIGN_ID     = -
endif

SHEETS      = $(wildcard Pets/*/sprites/atlas.json)

.PHONY: all app art build run run-fg test validate-packs placeholder-art petpack clean

all: app

build:
	swift build -c $(CONFIG) --product $(APP_NAME)

petpack:
	swift build --package-path $(PETKIT) --product petpack
PETPACK = $$(swift build --package-path $(PETKIT) --show-bin-path)/petpack

# Sprite sheets are built locally from the downloaded source art (never committed; see docs/ART_SOURCES.md).
IRONMAN_SRC  = ThirdParty/source-assets/cosmic-ironman/default
SPIDEY_SRC   = ThirdParty/source-assets/cosmic-spiderman/default
BATMAN_SRC   = ThirdParty/source-assets/snes-batman

Pets/ironman/sprites/sheet.png: $(IRONMAN_SRC)/Idle_00.png Pets/ironman/sprites/labels.json
	@$(MAKE) --no-print-directory petpack
	$(PETPACK) frames Pets/ironman/sprites/labels.json --out Pets/ironman/sprites

$(BATMAN_SRC)/work/candidates.json: $(BATMAN_SRC)/sheet.png
	@$(MAKE) --no-print-directory petpack
	$(PETPACK) slice $(BATMAN_SRC)/sheet.png --out $(BATMAN_SRC)/work --bg '#A34D4D' --merge 1 --min-pixels 40

Pets/batman/sprites/sheet.png: $(BATMAN_SRC)/work/candidates.json Pets/batman/sprites/labels.json
	$(PETPACK) pack $(BATMAN_SRC)/work/candidates.json Pets/batman/sprites/labels.json --out Pets/batman/sprites --facing right

$(IRONMAN_SRC)/Idle_00.png $(SPIDEY_SRC)/Idle_00.png $(BATMAN_SRC)/sheet.png:
	@echo "missing source art: $@ — download it first (docs/ART_SOURCES.md)"; exit 1

Pets/spiderman/sprites/sheet.png: $(SPIDEY_SRC)/Idle_00.png Pets/spiderman/sprites/labels.json
	@$(MAKE) --no-print-directory petpack
	$(PETPACK) frames Pets/spiderman/sprites/labels.json --out Pets/spiderman/sprites

art: Pets/ironman/sprites/sheet.png Pets/spiderman/sprites/sheet.png Pets/batman/sprites/sheet.png

# Original placeholder art (no download needed), for testing the pipeline.
placeholder-art: petpack
	$(PETPACK) placeholder Pets/ironman

app: build art
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" $(APP)/Contents/MacOS/
	@cp App/Info.plist $(APP)/Contents/
	@rsync -a --exclude '.DS_Store' --exclude '*.suggested.json' Pets $(APP)/Contents/Resources/
	@codesign --force --sign "$(SIGN_ID)" --entitlements App/AmbientPets.entitlements $(APP)
	@echo "built $(APP) (signed: $(SIGN_ID))"

run: app
	@pkill -x $(APP_NAME) || true
	@open $(APP)

run-fg: app
	@pkill -x $(APP_NAME) || true
	$(APP)/Contents/MacOS/$(APP_NAME)

test:
	swift test --package-path $(PETKIT) $(TEST_FLAGS)

validate-packs: petpack
	@ok=0; for d in Pets/*/pet.json; do $(PETPACK) validate $$(dirname $$d) || ok=1; done; \
	if [ -d Pets/_ensembles ]; then $(PETPACK) validate Pets/_ensembles || ok=1; fi; exit $$ok

clean:
	rm -rf $(BUILD_DIR) .build $(PETKIT)/.build

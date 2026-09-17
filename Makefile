BUILD_DIR := build

ifeq ($(OS),Windows_NT)
APP := $(BUILD_DIR)/Silo.exe
else ifeq ($(shell uname -s),Darwin)
APP := $(BUILD_DIR)/Silo.app/Contents/MacOS/Silo
else
APP := $(BUILD_DIR)/Silo
endif

.PHONY: build clean run rerun icons web-assets

build:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Debug
	cmake --build $(BUILD_DIR) --parallel

clean:
	cmake -E remove_directory $(BUILD_DIR)

run: build
	"$(APP)"

rerun: build
	"$(APP)"

icons:
	./scripts/fetch-icons.sh

# xterm.js / Ace bundles used by the Live mode terminal and text editor
web-assets:
	./scripts/fetch-web-assets.sh

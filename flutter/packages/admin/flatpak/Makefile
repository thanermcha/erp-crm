APP_ID = io.growerp.crm.blah
BUILD_DIR = build-dir
REPO_DIR = repo

all: build

build:
	flatpak-builder --force-clean --ccache $(BUILD_DIR) $(APP_ID).yml

install: build
	flatpak-builder --user --install --force-clean $(BUILD_DIR) $(APP_ID).yml

repo: build
	flatpak build-export $(REPO_DIR) $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(REPO_DIR)

publish: repo
	@echo "tar -czf $(APP_ID).flatpak repo/"
	@echo "scp $(APP_ID).flatpak user@host:"
	@echo "# Client: flatpak install $(APP_ID).flatpak"

BUILD_DIR=$(shell pwd)/build
BIN_DIR=$(BUILD_DIR)/bin
MINISHIFT_LATEST_URL=$(shell python tests/utils/minishift_latest_version.py)
MINISHIFT_UNTAR_DIR=$(shell echo $(ARCHIVE_FILE) | sed 's/.tgz//')
ARCHIVE_FILE=$(shell echo $(MINISHIFT_LATEST_URL) | rev | cut -d/ -f1 | rev)

.PHONY: init
init: 
	mkdir -p $(BUILD_DIR)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

$(BIN_DIR)/minishift:
	@echo "Downloading latest minishift binary at $(BIN_DIR)/minishift..."
	@mkdir -p $(BIN_DIR)
	@cd $(BIN_DIR) && \
	curl -LO --progress-bar $(MINISHIFT_LATEST_URL) && \
	tar xzf $(ARCHIVE_FILE) && \
	mv $(MINISHIFT_UNTAR_DIR)/minishift .
	@echo "Done."

.PHONY: test
test: $(BIN_DIR)/minishift
	sh tests/test.sh

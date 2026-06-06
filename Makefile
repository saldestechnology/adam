# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker-based build and run operations

IMAGE_NAME := compiled-ai
OUTPUT_DIR := $(shell pwd)/output

.PHONY: all build run clean logs artifacts stop

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  build     — Build the Docker image"
	@echo "  run       — Run the autonomous agent once"
	@echo "  run-tty   — Run with pseudo-TTY (interactive logs)"
	@echo "  artifacts — List generated specs and code in $(OUTPUT_DIR)"
	@echo "  logs      — Tail the last run log"
	@echo "  stop      — Stop any running container"
	@echo "  clean     — Remove output artifacts, cache, and build cruft"
	@echo "  rebuild   — Force rebuild the Docker image from scratch"

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Force rebuild without cache
rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

# Run the autonomous agent once (detached, saves output)
run: build
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		-v $(OUTPUT_DIR):/output \
		$(IMAGE_NAME) \
		2>&1 | tee $(OUTPUT_DIR)/run_$(shell date +%Y%m%d_%H%M%S).log

# Run with TTY (for interactive progress display)
run-tty: build
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm -t \
		-v $(OUTPUT_DIR):/output \
		$(IMAGE_NAME) \
		2>&1 | tee $(OUTPUT_DIR)/run_$(shell date +%Y%m%d_%H%M%S).log

# List generated artifacts (specs, code, cache)
artifacts:
	@if [ -d $(OUTPUT_DIR) ]; then \
		echo "=== Specs ==="; \
		ls -la $(OUTPUT_DIR)/spec_*.md 2>/dev/null || echo "  (none)"; \
		echo "=== Code ==="; \
		ls -la $(OUTPUT_DIR)/lib_*.rs 2>/dev/null || echo "  (none)"; \
		echo "=== Failed specs ==="; \
		ls -la $(OUTPUT_DIR)/spec_failed_*.md 2>/dev/null || echo "  (none)"; \
		echo "=== Cache ==="; \
		ls -la $(OUTPUT_DIR)/compiled_cache.json 2>/dev/null || echo "  (none)"; \
	else \
		echo "No output directory yet."; \
	fi

# Tail the latest run log
logs:
	@LATEST_LOG=$$(ls -t $(OUTPUT_DIR)/run_*.log 2>/dev/null | head -n1); \
	if [ -n "$$LATEST_LOG" ]; then \
		tail -n 50 "$$LATEST_LOG"; \
	else \
		echo "No run logs found in $(OUTPUT_DIR)."; \
	fi

# Stop any running container
stop:
	@CONTAINER=$$(docker ps -q --filter ancestor=$(IMAGE_NAME)); \
	if [ -n "$$CONTAINER" ]; then \
		docker stop $$CONTAINER; \
		echo "Stopped."; \
	else \
		echo "No running container found."; \
	fi

# Clean output artifacts
clean:
	@docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned."

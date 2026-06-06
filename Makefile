# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker-based build and run operations

IMAGE_NAME := compiled-ai
OUTPUT_DIR := $(shell pwd)/output
CONTAINER_NAME := compiled-ai-run

.PHONY: all build run logs status artifacts stop clean rebuild

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  build     — Build the Docker image"
	@echo "  run       — Start the autonomous agent in the background"
	@echo "  logs      — Follow live logs from the running container"
	@echo "  status    — Check if the agent is running and for how long"
	@echo "  artifacts — List generated specs, code, and cache in $(OUTPUT_DIR)"
	@echo "  stop      — Stop the running container"
	@echo "  clean     — Stop container, remove image, and delete all output"
	@echo "  rebuild   — Force rebuild the Docker image from scratch"

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Force rebuild without cache
rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

# Run the autonomous agent in the background (non-blocking)
run: build
	@mkdir -p $(OUTPUT_DIR)
	@echo "Starting container $(CONTAINER_NAME)..."
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@docker run -d \
		--name $(CONTAINER_NAME) \
		-v $(OUTPUT_DIR):/output \
		$(IMAGE_NAME) \
		> /dev/null 2>&1
	@echo "Agent is running in the background."
	@echo "  Follow logs:  make logs"
	@echo "  Check status: make status"
	@echo "  Stop:         make stop"

# Follow live logs from the running container (blocks until container exits)
logs:
	@docker logs -f $(CONTAINER_NAME) 2>&1 | tee $(OUTPUT_DIR)/run_$(shell date +%Y%m%d_%H%M%S).log

# Check if the container is running and show its runtime
status:
	@RUNNING=$$(docker ps -q --filter name=$(CONTAINER_NAME) | wc -l); \
	if [ "$$RUNNING" -eq 1 ]; then \
		STARTED=$$(docker inspect -f '{{.State.StartedAt}}' $(CONTAINER_NAME) 2>/dev/null); \
		echo "Container $(CONTAINER_NAME) is RUNNING (started: $$STARTED)"; \
		echo "Run 'make logs' to follow progress."; \
	else \
		EXIT_CODE=$$(docker inspect -f '{{.State.ExitCode}}' $(CONTAINER_NAME) 2>/dev/null || echo "?"); \
		echo "Container $(CONTAINER_NAME) is NOT RUNNING (exit code: $$EXIT_CODE)"; \
	fi

# List generated artifacts (specs, code, cache)
artifacts:
	@if [ -d $(OUTPUT_DIR) ]; then \
		echo "=== Successful Artifacts ==="; \
		ls -la $(OUTPUT_DIR)/spec_*.md 2>/dev/null || echo "  (none)"; \
		ls -la $(OUTPUT_DIR)/lib_*.rs 2>/dev/null || echo "  (none)"; \
		echo "=== Failed/Debug Artifacts ==="; \
		ls -la $(OUTPUT_DIR)/spec_failed_*.md 2>/dev/null || echo "  (none)"; \
		ls -la $(OUTPUT_DIR)/lib_failed_*.rs 2>/dev/null || echo "  (none)"; \
		ls -la $(OUTPUT_DIR)/errors_*.log 2>/dev/null || echo "  (none)"; \
		ls -la $(OUTPUT_DIR)/debug_response_*.txt 2>/dev/null || echo "  (none)"; \
		echo "=== Cache ==="; \
		ls -la $(OUTPUT_DIR)/compiled_cache.json 2>/dev/null || echo "  (none)"; \
		echo "=== Run Logs ==="; \
		ls -la $(OUTPUT_DIR)/run_*.log 2>/dev/null || echo "  (none)"; \
	else \
		echo "No output directory yet."; \
	fi

# Stop the running container
stop:
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@echo "Stopped and removed $(CONTAINER_NAME)."

# Clean everything
# Clean everything
clean: stop
	@docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned."

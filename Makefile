# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker-based build and run operations
#
# With --dangerously-skip-permissions, opencode auto-approves all tool
# calls, removing the need for a real TTY. The container runs detached
# (-d) for convenience. Use `make logs` to stream output in real time.

IMAGE_NAME := compiled-ai
CONTAINER_NAME := compiled-ai-agent
OUTPUT_DIR := $(shell pwd)/output

.PHONY: all build run logs artifacts stop clean rebuild

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  build     — Build the Docker image"
	@echo "  run       — Run the autonomous agent (detached, stream logs)"
	@echo "  logs      — Stream output from the running agent"
	@echo "  artifacts — List generated specs, code, and cache"
	@echo "  stop      — Kill the running agent container"
	@echo "  clean     — Stop container, remove image, and delete all output"
	@echo "  rebuild   — Force rebuild the Docker image from scratch"

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Force rebuild without cache
rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

# Run the autonomous agent in detached mode.
# Auto-approves all tool permissions so no TTY is required.
# Streams logs to both terminal and output/run_latest.log.
run: build
	@mkdir -p $(OUTPUT_DIR)
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@docker run -d --name $(CONTAINER_NAME) \
		-v $(OUTPUT_DIR):/output \
		$(IMAGE_NAME)
	@echo "Agent started in detached mode."
	@echo "Streaming logs to $(OUTPUT_DIR)/run_latest.log..."
	@echo "Run 'make logs' in another terminal to reattach."
	@echo "Run 'make stop' to kill the agent."
	@docker logs -f $(CONTAINER_NAME) | tee $(OUTPUT_DIR)/run_latest.log

# Stream logs from the running container
logs:
	@if docker ps -q --filter name=$(CONTAINER_NAME) | grep -q .; then \
		echo "Attaching to $(CONTAINER_NAME) logs..."; \
		docker logs -f $(CONTAINER_NAME); \
	else \
		echo "No running agent found. Start one with 'make run'."; \
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
		echo "=== Cache ==="; \
		ls -la $(OUTPUT_DIR)/compiled_cache.json 2>/dev/null || echo "  (none)"; \
		echo "=== Run Logs ==="; \
		ls -la $(OUTPUT_DIR)/run_*.log 2>/dev/null || echo "  (none)"; \
	else \
		echo "No output directory yet."; \
	fi

# Stop the running agent
stop:
	@if docker ps -q --filter name=$(CONTAINER_NAME) | grep -q .; then \
		docker kill $(CONTAINER_NAME); \
		echo "Killed agent."; \
	else \
		echo "No running agent found."; \
	fi

# Clean everything
 clean: stop
	@docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned."

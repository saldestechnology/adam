# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker-based build and run operations
# 
# CRITICAL: opencode requires a real TTY for --format json text events
# and tool access. Docker detached mode (-d) does NOT provide a real TTY.
# Therefore the container MUST run in foreground with -t (not -d).
# Output is redirected to a log file so you can tail it separately.

IMAGE_NAME := compiled-ai
OUTPUT_DIR := $(shell pwd)/output

.PHONY: all build run logs artifacts stop clean rebuild

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  build     — Build the Docker image"
	@echo "  run       — Run the autonomous agent (foreground, blocks terminal)"
	@echo "  logs      — Follow the latest run log (run in a separate terminal)"
	@echo "  artifacts — List generated specs, code, and cache in $(OUTPUT_DIR)"
	@echo "  stop      — Kill any running compiled-ai container"
	@echo "  clean     — Stop container, remove image, and delete all output"
	@echo "  rebuild   — Force rebuild the Docker image from scratch"
	@echo ""
	@echo "Usage:"
	@echo "  Terminal 1: make run        # starts the agent, writes to output/run_latest.log"
	@echo "  Terminal 2: make logs       # tails the log in real time"

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Force rebuild without cache
rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

# Run the autonomous agent in the foreground (required for TTY).
# Redirects all output to output/run_latest.log so you can tail it.
# This blocks the terminal until the agent completes.
run: build
	@mkdir -p $(OUTPUT_DIR)
	@echo "Starting agent in foreground (output goes to $(OUTPUT_DIR)/run_latest.log)..."
	@echo "Run 'make logs' in another terminal to follow progress."
	@docker run -t --rm \
		-v $(OUTPUT_DIR):/output \
		$(IMAGE_NAME) \
		> $(OUTPUT_DIR)/run_latest.log 2>&1
	@echo "Agent finished."

# Follow the latest run log (use in a separate terminal while 'make run' is active)
logs:
	@if [ -f $(OUTPUT_DIR)/run_latest.log ]; then \
		tail -n 50 -f $(OUTPUT_DIR)/run_latest.log; \
	else \
		echo "No run_latest.log found. Start the agent first with 'make run'."; \
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

# Stop any running compiled-ai container
stop:
	@CONTAINER=$$(docker ps -q --filter ancestor=$(IMAGE_NAME)); \
	if [ -n "$$CONTAINER" ]; then \
		docker kill $$CONTAINER; \
		echo "Killed running agent."; \
	else \
		echo "No running agent found."; \
	fi

# Clean everything
clean: stop
	@docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned."

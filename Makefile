# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker Compose operations
#
# Usage:
#   make up     → Build image and start Qdrant + miner (daemon mode)
#   make down   → Stop all services
#   make logs   → Stream miner logs
#   make db     → Open Qdrant dashboard in browser
#   make artifacts → List generated specs and cache
#   make clean  → Stop services and delete all output

IMAGE_NAME := compiled-ai
CONTAINER_NAME_MINER := compiled-ai-miner
CONTAINER_NAME_QDRANT := compiled-ai-qdrant
OUTPUT_DIR := $(shell pwd)/output

.PHONY: all build up down logs db artifacts stop clean rebuild

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  up        → Build image and start Qdrant + miner (docker-compose up -d)"
	@echo "  down      → Stop and remove all services"
	@echo "  logs      → Stream miner logs in real time"
	@echo "  db        → Open Qdrant dashboard (http://localhost:6333/dashboard)"
	@echo "  artifacts → List generated specs, code, and cache in $(OUTPUT_DIR)"
	@echo "  stop      → Kill the miner container only (Qdrant keeps running)"
	@echo "  clean     → Stop all services and delete output/"
	@echo "  rebuild   → Force rebuild Docker image from scratch"

# Bring up the full stack (Qdrant + miner)
up:
	@mkdir -p $(OUTPUT_DIR)
	@docker compose up --build -d
	@echo "Stack started."
	@echo "  Qdrant API:  http://localhost:6333"
	@echo "  Qdrant UI:   http://localhost:6333/dashboard"
	@echo "  Miner logs:  make logs"

# Take down the full stack
down:
	@docker compose down
	@echo "Stack stopped."

# Stream miner logs
logs:
	@docker logs -f $(CONTAINER_NAME_MINER) 2>&1 || echo "No miner logs found. Start with 'make up'."

# Open Qdrant dashboard
db:
	@echo "Opening Qdrant dashboard..."
	@open http://localhost:6333/dashboard || xdg-open http://localhost:6333/dashboard || echo "Open http://localhost:6333/dashboard manually"

# Build Docker image only (via docker-compose)
build:
	@docker compose build

# Force rebuild
rebuild:
	@docker compose build --no-cache

# List generated artifacts
artifacts:
	@if [ -d $(OUTPUT_DIR) ]; then \
		echo "=== Successful Artifacts ==="; \
		ls -la $(OUTPUT_DIR)/spec_*.md 2>/dev/null || echo "  (none)"; \
		ls -la $(OUTPUT_DIR)/lib_*.rs 2>/dev/null || echo "  (none)"; \
		echo "=== Cache ==="; \
		ls -la $(OUTPUT_DIR)/compiled_cache.json 2>/dev/null || echo "  (none)"; \
	else \
		echo "No output directory yet."; \
	fi

# Stop miner only
stop:
	@docker compose stop miner || docker kill $(CONTAINER_NAME_MINER) 2>/dev/null || true
	@echo "Miner stopped. Qdrant is still running."

# Clean everything
clean:
	@docker compose down -v
	@docker rmi -f $(IMAGE_NAME) 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned."

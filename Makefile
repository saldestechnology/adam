# Compiled AI — Autonomous Rust Spec Miner
# Makefile for Docker Compose operations
#
# Usage:
#   make up       → Build image and start Qdrant + miner (daemon mode)
#   make down     → Stop all services
#   make logs     → Stream miner logs
#   make db       → Open Qdrant dashboard in browser
#   make query    → Query Qdrant collection count
#   make stats    → Show miner statistics (specs generated, quality scores)
#   make artifacts → List generated specs, code, and cache
#   make clean    → Stop services and delete all output
#   make rebuild  → Force rebuild Docker image from scratch

IMAGE_NAME := compiled-ai-final
CONTAINER_NAME_MINER := compiled-ai-miner
CONTAINER_NAME_QDRANT := compiled-ai-qdrant
OUTPUT_DIR := $(shell pwd)/output

.PHONY: all up down logs db query stats artifacts stop clean rebuild

# Default: show help
all:
	@echo "Compiled AI — Available targets:"
	@echo "  up        → Build image and start Qdrant + miner (docker compose up -d)"
	@echo "  down      → Stop and remove all services"
	@echo "  logs      → Stream miner logs in real time"
	@echo "  db        → Open Qdrant dashboard (http://localhost:6333/dashboard)"
	@echo "  query     → Count points in Qdrant collection"
	@echo "  stats     → Show miner stats: total specs, avg audit score, categories"
	@echo "  artifacts → List generated specs, code, and cache in $(OUTPUT_DIR)"
	@echo "  stop      → Kill the miner container only (Qdrant keeps running)"
	@echo "  clean     → Stop all services, delete output/, prune images"
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

# Query Qdrant collection point count
query:
	@curl -s -X POST http://localhost:6333/collections/compiled_ai_specs/points/count \
		-H 'Content-Type: application/json' -d '{}' | \
		python3 -m json.tool 2>/dev/null || echo "Qdrant not responding. Is 'make up' running?"

# Show miner statistics from Qdrant payload data
stats:
	@echo "Miner Statistics (from Qdrant)..."
	@python3 scripts/show_stats.py 2>/dev/null || echo "  Qdrant not responding. Is 'make up' running?"

# Compile the whitepaper from Typst sources
paper:
	@typst compile docs/main.typ docs/whitepaper.pdf
	@echo "Done: docs/whitepaper.pdf"

# Watch-mode for live typst recompilation
paper-watch:
	@typst watch docs/main.typ docs/whitepaper.pdf

# Build Docker image only (via docker compose)
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

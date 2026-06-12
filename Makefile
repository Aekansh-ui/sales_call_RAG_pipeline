.PHONY: up down logs shell pull-models migrate reset-db help

# Default target — show help when `make` is run with no arguments
help:
	@echo "Sales Call RAG Pipeline — available targets:"
	@echo ""
	@echo "  make up           Build images and start all services (detached)"
	@echo "  make down         Stop and remove containers (data preserved)"
	@echo "  make reset-db     Stop containers AND delete all volumes (full wipe)"
	@echo "  make logs         Follow logs from all services"
	@echo "  make shell        Open a bash shell inside the app container"
	@echo "  make pull-models  Pull LLM and embedding models into Ollama"
	@echo "  make migrate      Run SQL migration files against the database"
	@echo "  make help         Show this message"

# Build images and start all services in the background.
# --build forces a rebuild of the app image (safe to run even if already built).
up:
	docker compose up -d --build

# Stop and remove containers. Named volumes (DB data, Ollama models) are kept.
down:
	docker compose down

# Follow logs from all services. Ctrl+C stops streaming but not the containers.
logs:
	docker compose logs -f

# Open an interactive shell inside the running app container.
# Useful for debugging imports, inspecting files, or running one-off scripts.
shell:
	docker compose exec app bash

# Pull the LLM and embedding models into the Ollama container.
# Models are stored in the ollama_data named volume and persist across restarts.
# This only needs to be run once (or after `make reset-db` wipes the volume).
# First run takes 5-10 minutes — llama3.2:3b is ~2 GB, nomic-embed-text ~270 MB.
pull-models:
	docker compose exec ollama ollama pull llama3.2:3b
	docker compose exec ollama ollama pull nomic-embed-text
	docker compose exec ollama ollama list

# Run all SQL migration files in order.
# Wired up properly in T-02 when we write db.py and the migration files.
migrate:
	docker compose exec app python -m app.db migrate

# Stop all services AND delete all named volumes.
# Effect: database wiped, Ollama models deleted. Use for a clean-slate restart.
# WARNING: you will need to run `make pull-models` again after this.
reset-db:
	docker compose down -v

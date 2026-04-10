.PHONY: help up down restart logs shell-php shell-db shell-nginx status ps \
		env-encrypt env-decrypt wp-cli db-backup db-restore clean nuke

SHELL := /bin/bash

# ─── Configuration ───────────────────────────────────────────────────────────
-include .env
export

COMPOSE := docker compose
PHP_CONTAINER := $(PROJECT_NAME)-php-1
DB_CONTAINER  := $(PROJECT_NAME)-db-1
TIMESTAMP     := $(shell date +%Y%m%d_%H%M%S)

# ─── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help message
	@echo ""
	@echo "  WordPress + Docker — available commands"
	@echo "  ────────────────────────────────────────"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ \
		{ printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ─── Containers ────────────────────────────────────────────────────────────────
up: ## Start containers in background
	$(COMPOSE) up -d

down: ## Stop and remove containers
	$(COMPOSE) down

restart: ## Restart all containers
	$(COMPOSE) restart

ps: ## Show container status
	$(COMPOSE) ps

status: ps ## Alias for ps

# ─── Env ──────────────────────────────────────────────────────────────────────
ENV_FILE     := .env
ENV_ENC_FILE := .env.encrypted

env-encrypt: ## Encrypt .env → .env.enc with passphrase (AES-256-CBC)
	@test -f $(ENV_FILE) || (echo "File $(ENV_FILE) not found." && exit 1)
	@read -s -p "  Passphrase: " pass; echo ""; \
	read -s -p "  Confirm passphrase: " pass2; echo ""; \
	[ "$$pass" = "$$pass2" ] || (echo "Passphrases do not match." && exit 1); \
	openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
		-in $(ENV_FILE) -out $(ENV_ENC_FILE) -pass pass:"$$pass"
	@echo "Encrypted to $(ENV_ENC_FILE) — add $(ENV_FILE) to .gitignore."
	
env-decrypt: ## Decrypt .env.enc → .env with passphrase (AES-256-CBC)
	@test -f $(ENV_ENC_FILE) || (echo "File $(ENV_ENC_FILE) not found." && exit 1)
	@test ! -f $(ENV_FILE) || (echo "$(ENV_FILE) already exists — rename or remove it first." && exit 1)
	@read -s -p "  Passphrase: " pass; echo ""; \
	openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
		-in $(ENV_ENC_FILE) -out $(ENV_FILE).tmp -pass pass:"$$pass" 2>/dev/null \
	&& mv $(ENV_FILE).tmp $(ENV_FILE) \
	|| (rm -f $(ENV_FILE).tmp; echo "Wrong passphrase or corrupted file."; exit 1)
	@echo "Decrypted to $(ENV_FILE)."

# ─── Logs ──────────────────────────────────────────────────────────────────────
logs: ## Follow logs of all services
	$(COMPOSE) logs -f

logs-nginx: ## Follow Nginx logs
	$(COMPOSE) logs -f nginx

logs-php: ## Follow PHP-FPM logs
	$(COMPOSE) logs -f php

logs-db: ## Follow MariaDB logs
	$(COMPOSE) logs -f db

# ─── Shell ────────────────────────────────────────────────────────────────────
shell-php: ## Open a bash shell in the PHP container
	$(COMPOSE) exec php bash

shell-db: ## Open the MariaDB client
	$(COMPOSE) exec db mariadb -u $(MYSQL_USER) -p$(MYSQL_PASSWORD) $(MYSQL_DATABASE)

shell-nginx: ## Open a bash shell in the Nginx container
	$(COMPOSE) exec nginx sh

# ─── WordPress ────────────────────────────────────────────────────────────────
wp-permissions: ## Restore correct permissions on public_html/
	@echo "Setting www-data permissions on public_html/..."
	sudo chown -R www-data:www-data public_html/
	sudo chmod -R gu+rws public_html
	@echo "Permissions restored."

wp-cli: ## Run a WP-CLI command (e.g.: make wp-cli CMD="plugin list")
	$(COMPOSE) exec php wp --allow-root $(CMD)

# ─── Database ─────────────────────────────────────────────────────────────────
db-backup: ## Perform dump and save it in root (for commit in production repo)
	$(COMPOSE) exec db mariadb-dump \
		-u $(MYSQL_USER) -p$(MYSQL_PASSWORD) $(MYSQL_DATABASE) \
		> ./$(MYSQL_DATABASE).sql
	@echo "Dump saved in ./$(MYSQL_DATABASE).sql — ready for commit."

db-restore: ## Restore a dump (e.g.: make db-restore FILE=backups/dump.sql)
	@test -n "$(FILE)" || (echo "Specify FILE=<path.sql>" && exit 1)
	$(COMPOSE) exec -T db mariadb \
		-u $(MYSQL_USER) -p$(MYSQL_PASSWORD) $(MYSQL_DATABASE) < $(FILE)
	@echo "Database restored from $(FILE)."

# ─── Cleanup ──────────────────────────────────────────────────────────────────
clean: ## Stop containers and remove logs
	$(COMPOSE) down
	rm -f logs/*.log

nuke: ## ⚠️  Remove containers, volumes (db), built PHP image, and logs — DESTRUCTIVE
	@echo ""
	@echo "  ⚠️  You are about to delete all containers AND the database volume."
	@read -p "  Are you sure? Type 'yes' to confirm: " confirm; \
	[ "$$confirm" = "yes" ] || (echo "Cancelled." && exit 1)
	$(COMPOSE) down -v --rmi local
	rm -f logs/*.log
	@echo "Cleanup completed."
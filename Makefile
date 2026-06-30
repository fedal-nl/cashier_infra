# Makefile for frontend project
# command to run: make {command name}

PRODUCTION_COMPOSE=docker compose -f docker-compose.production.yml
DEV_COMPOSE=docker compose -f docker-compose.yml
APP_SERVICES=backend backend-2 backend-3 reports autoheal api-stack-autoheal
BACKUP_FILE?=backup_cashier_20260629_130001.dump
DEV_DB_NAME?=cashier
PROD_DB_NAME?=cashier_app
RESTORE_OPTIONS=--clean --if-exists --no-owner --no-acl --exit-on-error

.PHONY: help check-nginx reload-nginx deploy start-monitoring stop-monitoring logs-monitoring logs-backend stop-containers restart-containers restart-db get-autoheal-log-path check-db-connection create-reporting-db-user backup import-dev-db restore-prod-db

help:
	@echo "Available commands:"
	@echo "  make help                  Show this help message"
	@echo "  make check-nginx           Check nginx configuration"
	@echo "  make reload-nginx          Reload nginx service"
	@echo "  make deploy                Stop, pull, and start the full production stack"
	@echo "  make restart-containers    Restart production app containers, excluding db"
	@echo "  make restart-db            Restart production Postgres container"
	@echo "  make stop-containers       Stop and remove production app containers, excluding db"
	@echo "  make start-monitoring      Start monitoring containers"
	@echo "  make stop-monitoring       Stop monitoring containers"
	@echo "  make logs-monitoring       Tail monitoring logs"
	@echo "  make logs-backend          Tail backend logs"
	@echo "  make get-autoheal-log-path Print autoheal Docker log file path"
	@echo "  make check-db-connection   Check Postgres readiness inside Docker"
	@echo "  make create-reporting-db-user Create/update read-only reporting DB user"
	@echo "  make backup                Run Postgres backup script"
	@echo "  make import-dev-db BACKUP_FILE=backup.dump"
	@echo "                             Import a backup into local dev Postgres"
	@echo "  make restore-prod-db BACKUP_FILE=backup.dump CONFIRM=restore-production"
	@echo "                             Restore a backup into production Postgres"

# command to check nginx configuration
check-nginx:
	sudo nginx -t

# command to reload nginx server
reload-nginx:
	sudo systemctl reload nginx

# on production stop the full stack, pull the latest images, and start everything again
deploy:
	$(PRODUCTION_COMPOSE) down --remove-orphans
	$(PRODUCTION_COMPOSE) pull
	$(PRODUCTION_COMPOSE) up -d

# start the monitoring containers using the docker-compose.monitoring.yml file
start-monitoring:
	docker compose -f docker-compose.monitoring.yml up -d

# stop the monitoring containers
stop-monitoring:
	docker compose -f docker-compose.monitoring.yml down

# tail the logs of the monitoring containers
logs-monitoring:
	docker compose -f docker-compose.monitoring.yml logs -f

# tail the logs of the backend container
logs-backend:
	$(PRODUCTION_COMPOSE) logs -f backend backend-2 backend-3

restart-containers:
	$(PRODUCTION_COMPOSE) restart $(APP_SERVICES)

restart-db:
	$(PRODUCTION_COMPOSE) restart db

stop-containers:
	$(PRODUCTION_COMPOSE) stop $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) rm -f $(APP_SERVICES)

get-autoheal-log-path:
	docker inspect cashier_autoheal --format='{{.LogPath}}'

check-db-connection:
	docker exec cashier_db pg_isready -U "$DB_USER" -d "$DB_NAME"

create-reporting-db-user:
	COMPOSE_FILE=docker-compose.production.yml ./devops/create_postgres_readonly_user.sh

backup:
	ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=/home/omar/apps/backups/backups ./devops/backup_postgres.sh

import-dev-db:
	@test -f "$(BACKUP_FILE)" || (echo "Missing backup file: $(BACKUP_FILE)" >&2; exit 1)
	$(DEV_COMPOSE) up -d db
	$(DEV_COMPOSE) exec -T db sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_restore $(RESTORE_OPTIONS) --host=localhost --username="$$POSTGRES_USER" --dbname="$(DEV_DB_NAME)"' < "$(BACKUP_FILE)"

restore-prod-db:
	@test "$(CONFIRM)" = "restore-production" || (echo "Refusing production restore. Re-run with CONFIRM=restore-production" >&2; exit 1)
	@test -f "$(BACKUP_FILE)" || (echo "Missing backup file: $(BACKUP_FILE)" >&2; exit 1)
	$(PRODUCTION_COMPOSE) stop $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) exec -T db sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_restore $(RESTORE_OPTIONS) --host=localhost --username="$$POSTGRES_USER" --dbname="$(PROD_DB_NAME)"' < "$(BACKUP_FILE)"
	$(PRODUCTION_COMPOSE) up -d --no-deps backend
	$(PRODUCTION_COMPOSE) up -d --no-deps backend-2 backend-3 reports autoheal api-stack-autoheal

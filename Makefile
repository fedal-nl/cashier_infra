# Makefile for frontend project
# command to run: make {command name}

PRODUCTION_COMPOSE=docker compose -f docker-compose.production.yml
DEV_COMPOSE=docker compose -f docker-compose.yml
DEV_BACKEND_SERVICES=backend backend-2 backend-3
APP_SERVICES=backend backend-2 backend-3 reports autoheal api-stack-autoheal
PRODUCTION_SERVICES=db db-replica-1 $(APP_SERVICES)
BACKUP_FILE?=backup_cashier_20260707_130001.dump
DEV_DB_NAME?=cashier
PROD_DB_NAME?=cashier-app
RESTORE_OPTIONS=--clean --if-exists --no-owner --no-acl --exit-on-error

.PHONY: help check-nginx reload-nginx deploy deploy-apps deploy-report deploy-report-dev dev-recreate-backends start-monitoring stop-monitoring logs-monitoring logs-backend stop-containers restart-containers restart-db get-autoheal-log-path check-db-connection create-reporting-db-user configure-prod-replication start-prod-replica backup import-dev-db restore-prod-db reset-local-replica-db docker-stats

help:
	@echo "Available commands:"
	@echo "  make help                  Show this help message"
	@echo "  make check-nginx           Check nginx configuration"
	@echo "  make reload-nginx          Reload nginx service"
	@echo "  make deploy                Pull, stop, and start the full production stack"
	@echo "  make deploy-apps           Pull and redeploy production apps without databases"
	@echo "  make deploy-report         Pull and redeploy only reports in production"
	@echo "  make deploy-report-dev     Build and redeploy only reports in development"
	@echo "  make dev-recreate-backends Build and recreate development backend containers"
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
	@echo "  make configure-prod-replication Create/update production replication user"
	@echo "  make start-prod-replica Start same-server production Postgres replica"
	@echo "  make backup                Run Postgres backup script"
	@echo "  make import-dev-db BACKUP_FILE=backup.dump"
	@echo "                             Import a backup into local dev Postgres"
	@echo "  make reset-local-replica-db Recreate local PG18 primary and replica volumes"
	@echo "  make restore-prod-db BACKUP_FILE=backup.dump CONFIRM=restore-production"
	@echo "                             Restore a backup into production Postgres"
	@echo "  make docker-stats          Show Docker container stats"

# command to check nginx configuration
check-nginx:
	sudo nginx -t

# command to reload nginx server
reload-nginx:
	sudo systemctl reload nginx

# Pull all production images before stopping containers so a registry failure
# leaves the currently running stack untouched.
deploy:
	$(PRODUCTION_COMPOSE) pull $(PRODUCTION_SERVICES)
	$(PRODUCTION_COMPOSE) stop $(PRODUCTION_SERVICES)
	$(PRODUCTION_COMPOSE) rm -f $(PRODUCTION_SERVICES)
	$(PRODUCTION_COMPOSE) up -d $(PRODUCTION_SERVICES)

# Redeploy production application services while leaving all database
# containers untouched. Pull first so registry failures do not stop live apps.
deploy-apps:
	$(PRODUCTION_COMPOSE) pull $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) stop $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) rm -f $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) up -d --no-deps $(APP_SERVICES)

# Redeploy only the reports service in production using the published image.
deploy-report:
	$(PRODUCTION_COMPOSE) pull reports
	$(PRODUCTION_COMPOSE) stop reports
	$(PRODUCTION_COMPOSE) rm -f reports
	$(PRODUCTION_COMPOSE) up -d --no-deps reports

# Redeploy only the reports service in development using a local image build.
deploy-report-dev:
	$(DEV_COMPOSE) stop reports
	$(DEV_COMPOSE) rm -f reports
	$(DEV_COMPOSE) build reports
	$(DEV_COMPOSE) up -d --no-deps reports

# Rebuild and force-recreate only the development backend containers.
dev-recreate-backends:
	$(DEV_COMPOSE) up -d --build --force-recreate --no-deps $(DEV_BACKEND_SERVICES)

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

configure-prod-replication:
	$(PRODUCTION_COMPOSE) exec -T db sh -c '/docker-entrypoint-initdb.d/00-create-replication-user.sh && psql --username "$$POSTGRES_USER" --dbname "$$POSTGRES_DB" --command "SELECT pg_reload_conf();"'

start-prod-replica:
	$(PRODUCTION_COMPOSE) up -d db-replica-1

backup:
	ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=/home/omar/apps/backups/backups ./devops/backup_postgres.sh

import-dev-db:
	@test -f "$(BACKUP_FILE)" || (echo "Missing backup file: $(BACKUP_FILE)" >&2; exit 1)
	$(DEV_COMPOSE) up -d db
	$(DEV_COMPOSE) exec -T db sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_restore $(RESTORE_OPTIONS) --host=localhost --username="$$POSTGRES_USER" --dbname="$(DEV_DB_NAME)"' < "$(BACKUP_FILE)"

reset-local-replica-db:
	$(DEV_COMPOSE) stop db-replica-1 db-replica-2 db
	$(DEV_COMPOSE) rm -f db-replica-1 db-replica-2 db
	-docker volume rm cashierapps_postgres_18_restored cashierapps_postgres_18_replica_1 cashierapps_postgres_18_replica_2
	$(DEV_COMPOSE) up -d db db-replica-1 db-replica-2

restore-prod-db:
	@test "$(CONFIRM)" = "restore-production" || (echo "Refusing production restore. Re-run with CONFIRM=restore-production" >&2; exit 1)
	@test -f "$(BACKUP_FILE)" || (echo "Missing backup file: $(BACKUP_FILE)" >&2; exit 1)
	$(PRODUCTION_COMPOSE) stop $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) exec -T db sh -c 'PGPASSWORD="$$POSTGRES_PASSWORD" pg_restore $(RESTORE_OPTIONS) --host=localhost --username="$$POSTGRES_USER" --dbname="$(PROD_DB_NAME)"' < "$(BACKUP_FILE)"
	$(PRODUCTION_COMPOSE) up -d --no-deps backend
	$(PRODUCTION_COMPOSE) up -d --no-deps backend-2 backend-3 reports autoheal api-stack-autoheal

docker-stats:
	docker stats --no-stream

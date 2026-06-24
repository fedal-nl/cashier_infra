# Makefile for frontend project
# command to run: make {command name}

PRODUCTION_COMPOSE=docker compose -f docker-compose.production.yml
APP_SERVICES=backend backend-2 backend-3 reports autoheal api-stack-autoheal

.PHONY: help check-nginx reload-nginx deploy start-monitoring stop-monitoring logs-monitoring logs-backend stop-containers restart-containers get-autoheal-log-path check-db-connection create-reporting-db-user backup

help:
	@echo "Available commands:"
	@echo "  make help                  Show this help message"
	@echo "  make check-nginx           Check nginx configuration"
	@echo "  make reload-nginx          Reload nginx service"
	@echo "  make deploy                Pull and start production app containers, excluding db"
	@echo "  make restart-containers    Restart production app containers, excluding db"
	@echo "  make stop-containers       Stop and remove production app containers, excluding db"
	@echo "  make start-monitoring      Start monitoring containers"
	@echo "  make stop-monitoring       Stop monitoring containers"
	@echo "  make logs-monitoring       Tail monitoring logs"
	@echo "  make logs-backend          Tail backend logs"
	@echo "  make get-autoheal-log-path Print autoheal Docker log file path"
	@echo "  make check-db-connection   Check Postgres readiness inside Docker"
	@echo "  make create-reporting-db-user Create/update read-only reporting DB user"
	@echo "  make backup                Run Postgres backup script"

# command to check nginx configuration
check-nginx:
	sudo nginx -t

# command to reload nginx server
reload-nginx:
	sudo systemctl reload nginx

# on production pull the latest images using the docker-compose.production.yml file and restart the containers
deploy:
	$(PRODUCTION_COMPOSE) pull $(APP_SERVICES)
	$(PRODUCTION_COMPOSE) up -d --no-deps backend
	$(PRODUCTION_COMPOSE) up -d --no-deps backend-2 backend-3 reports autoheal api-stack-autoheal

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
	./backup_postgres.sh ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=/home/omar/apps/backups/backups $0

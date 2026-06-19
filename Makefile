# Makefile for frontend project
# command to run: make {command name}

.PHONY: help check-nginx reload-nginx deploy start-monitoring stop-monitoring logs-monitoring logs-backend stop-containers restart-containers get-autoheal-log-path backup

help:
	@echo "Available commands:"
	@echo "  make help                  Show this help message"
	@echo "  make check-nginx           Check nginx configuration"
	@echo "  make reload-nginx          Reload nginx service"
	@echo "  make deploy                Pull and start production containers"
	@echo "  make restart-containers    Restart production containers"
	@echo "  make stop-containers       Stop and remove production containers"
	@echo "  make start-monitoring      Start monitoring containers"
	@echo "  make stop-monitoring       Stop monitoring containers"
	@echo "  make logs-monitoring       Tail monitoring logs"
	@echo "  make logs-backend          Tail backend logs"
	@echo "  make get-autoheal-log-path Print autoheal Docker log file path"
	@echo "  make backup                Run Postgres backup script"

# command to check nginx configuration
check-nginx:
	sudo nginx -t

# command to reload nginx server
reload-nginx:
	sudo systemctl reload nginx

# on production pull the latest images using the docker-compose.production.yml file and restart the containers
deploy:
	docker compose -f docker-compose.production.yml pull
	docker compose -f docker-compose.production.yml up -d

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
	docker compose -f docker-compose.production.yml logs -fd

restart-containers:
	docker compose -f docker-compose.production.yml restart

stop-containers:
	docker compose -f docker-compose.production.yml stop
	docker compose -f docker-compose.production.yml down

get-autoheal-log-path:
	docker inspect cashier_autoheal --format='{{.LogPath}}'

check-db-connection:
	docker exec cashier_db pg_isready -U "$DB_USER" -d "$DB_NAME"

backup:
	./backup_postgres.sh ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=/home/omar/apps/backups/backups $0

# Makefile for frontend project
# command to run: make {command name}

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

stop-containers:
	docker compose -f docker-compose.production.yml stop
	docker compose -f docker-compose.production.yml down

get-autoheal-log-path:
	docker inspect cashier_autoheal --format='{{.LogPath}}'

backup:
	./backup_postgres.sh ENV_FILE=.env APP_NAME=cashier BACKUP_DIR=/home/omar/apps/backups/backups $0

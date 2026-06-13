# Makefile for frontend project
# command to run: make {command name}

# command to check nginx configuration
check-nginx:
	sudo nginx -t

# command to reload nginx server
reload-nginx:
	sudo systemctl reload nginx

# on production pull the latest images using the docker-compose.production.yml file and restart the containers
deploy-containers:
	sudo docker compose -f docker-compose.production.yml pull
	sudo docker compose -f docker-compose.production.yml up -d

# tail the logs of the frontend container
logs-frontend:
	sudo docker compose -f docker-compose.production.yml logs -f frontend

# tail the logs of the backend container
logs-backend:
	sudo docker compose -f docker-compose.production.yml logs -f backend

stop-containers:
	sudo docker compose stop
	sudo docker compose down

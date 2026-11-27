# Makefile per debian-firefox-vnc-container
#
# Variabili sovrascrivibili, es.: make up VNC_PORT=6001 VNC_BIND=0.0.0.0

IMAGE          ?= debian-browser-app
GHCR_IMAGE     ?= ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest
CONTAINER_NAME ?= debian-browser
VNC_PORT       ?= 6000
VNC_BIND       ?= 127.0.0.1
HOSTS_FILE     ?= my-hosts

# Versione di Firefox da installare. Di default viene risolta l'ultima release
# (valutata solo dalle ricette di build, non a ogni `make`); se Mozilla non
# risponde si ripiega su "latest". Fissala con: make build FIREFOX_VERSION=161.0
FIREFOX_VERSION ?= $(shell curl -fsSL https://product-details.mozilla.org/1.0/firefox_versions.json 2>/dev/null \
	| sed -n 's/.*"LATEST_FIREFOX_VERSION": *"\([^"]*\)".*/\1/p')
FF_VERSION = $(or $(FIREFOX_VERSION),latest)

export IMAGE CONTAINER_NAME VNC_PORT VNC_BIND

# CUSTOM_HOSTS è multilinea: $(shell ...) di make appiattirebbe le righe,
# quindi lo leggiamo nella shell della ricetta.
COMPOSE = CUSTOM_HOSTS="$$(cat $(HOSTS_FILE) 2>/dev/null)" docker compose

.DEFAULT_GOAL := help
.PHONY: help hosts build rebuild up up-ghcr down restart logs ps shell hosts-check firefox-version vnc clean

help: ## Mostra questo aiuto
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

hosts: ## Crea my-hosts da my-hosts.example (se non esiste)
	@if [ -f $(HOSTS_FILE) ]; then echo "$(HOSTS_FILE) esiste già"; \
	else cp my-hosts.example $(HOSTS_FILE) && echo "Creato $(HOSTS_FILE): modificalo con le tue voci"; fi

build: ## Builda l'immagine locale (con l'ultima release di Firefox)
	@echo "Firefox: $(FF_VERSION)"
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) build

rebuild: ## Builda l'immagine senza cache
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) build --no-cache

up: ## Avvia il container (build se necessario) con le voci di my-hosts
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) up -d --build
	@echo "VNC disponibile su $(VNC_BIND):$(VNC_PORT) (senza password)"

up-ghcr: ## Avvia usando l'immagine pubblicata su GHCR invece della build locale
	IMAGE=$(GHCR_IMAGE) $(COMPOSE) pull
	IMAGE=$(GHCR_IMAGE) $(COMPOSE) up -d --no-build
	@echo "VNC disponibile su $(VNC_BIND):$(VNC_PORT) (senza password)"

down: ## Ferma e rimuove il container
	$(COMPOSE) down

restart: down up ## Riavvia il container (rilegge my-hosts)

logs: ## Segue i log del container
	$(COMPOSE) logs -f

ps: ## Stato del container
	$(COMPOSE) ps

shell: ## Apre una shell bash nel container
	docker exec -it $(CONTAINER_NAME) bash

hosts-check: ## Mostra /etc/hosts dentro il container
	docker exec $(CONTAINER_NAME) cat /etc/hosts

firefox-version: ## Mostra la versione di Firefox nel container in esecuzione
	docker exec $(CONTAINER_NAME) firefox --version

vnc: ## Apre un client VNC (vncviewer o remmina) su localhost
	@if command -v vncviewer >/dev/null; then vncviewer localhost:$(VNC_PORT) & \
	elif command -v remmina >/dev/null; then remmina -c vnc://localhost:$(VNC_PORT) & \
	else echo "Nessun client VNC trovato: collegati a localhost:$(VNC_PORT)"; fi

clean: ## Ferma il container e rimuove l'immagine locale
	$(COMPOSE) down --rmi all

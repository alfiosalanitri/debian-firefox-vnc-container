# Makefile per debian-firefox-vnc-container
#
# `make` (o `make help`) mostra il flusso d'uso e tutti i comandi, raggruppati.
# Le righe "##@ Titolo" aprono una sezione dell'aiuto; "target: ## testo" descrive un comando.
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

# Analyzer: container senza rete, download in sola lettura. -T: niente TTY,
# così l'output si può mandare in pipe (less, grep, file).
ANALYZE = $(COMPOSE) run --rm -T analyzer

.DEFAULT_GOAL := help
.PHONY: help hosts up vnc down restart up-ghcr \
	av-update files scan inspect analyzer-shell \
	logs proxy-logs ps shell shell-root hosts-check firefox-version \
	build rebuild analyzer-build clean

B := \033[1m
C := \033[36m
R := \033[0m

help: # Mostra questo aiuto (target di default)
	@printf "$(B)Sandbox per aprire link e allegati di phishing$(R) (Firefox via VNC, isolato dall'host)\n\n"
	@printf "$(B)Uso tipico$(R)\n"
	@printf "  1. $(C)make up$(R)                    avvia browser + gateway (la prima volta builda le immagini)\n"
	@printf "  2. $(C)make vnc$(R)                   apre Remmina/vncviewer su localhost:$(VNC_PORT) (senza password)\n"
	@printf "     incolla il link sospetto in Firefox; in un altro terminale $(C)make proxy-logs$(R) mostra gli host contattati\n"
	@printf "  3. scarica gli allegati in Firefox, poi:\n"
	@printf "     $(C)make files$(R)                 elenca i file scaricati\n"
	@printf "     $(C)make scan$(R)                  antivirus ClamAV (la prima volta: $(C)make av-update$(R))\n"
	@printf "     $(C)make inspect FILE=nome$(R)     report: tipo reale, hash, macro, script PDF, link, header e allegati delle mail\n"
	@printf "  4. $(C)make restart$(R) o $(C)make down$(R)  cancella tutto (profilo, cookie, download stanno solo in RAM)\n"
	@awk 'BEGIN {FS = ":.*?## "} \
		/^##@ / { printf "\n$(B)%s$(R)\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*?## / { printf "  $(C)%-16s$(R) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\n$(B)Variabili$(R) (es. $(C)make up VNC_PORT=6001$(R))\n"
	@printf "  VNC_PORT=$(VNC_PORT)  VNC_BIND=$(VNC_BIND)  HOSTS_FILE=$(HOSTS_FILE)  FILE=<nome file per scan/inspect>\n"
	@printf "  FIREFOX_VERSION (default: ultima release)  MEM_LIMIT=4g  CPUS=2  PIDS_LIMIT=1024\n"

##@ Avvio e connessione

hosts: ## Crea my-hosts da my-hosts.example: voci /etc/hosts custom (facoltativo)
	@if [ -f $(HOSTS_FILE) ]; then echo "$(HOSTS_FILE) esiste già"; \
	else cp my-hosts.example $(HOSTS_FILE) && echo "Creato $(HOSTS_FILE): modificalo con le tue voci"; fi

up: ## Avvia browser e gateway (build se necessario), VNC su 127.0.0.1:6000
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) up -d --build
	@echo "VNC disponibile su $(VNC_BIND):$(VNC_PORT) (senza password): make vnc"

vnc: ## Apre il client VNC (vncviewer o remmina) su localhost
	@if command -v vncviewer >/dev/null; then vncviewer localhost:$(VNC_PORT) & \
	elif command -v remmina >/dev/null; then remmina -c vnc://localhost:$(VNC_PORT) & \
	else echo "Nessun client VNC trovato: collegati a localhost:$(VNC_PORT)"; fi

restart: down up ## Ricrea i container da zero (sessione pulita, rilegge my-hosts)

down: ## Ferma e rimuove i container (download e profilo vengono cancellati)
	$(COMPOSE) down

up-ghcr: ## Come up, ma con l'immagine del browser pubblicata su GHCR
	IMAGE=$(GHCR_IMAGE) $(COMPOSE) pull browser
	IMAGE=$(GHCR_IMAGE) $(COMPOSE) build gateway
	IMAGE=$(GHCR_IMAGE) $(COMPOSE) up -d
	@echo "VNC disponibile su $(VNC_BIND):$(VNC_PORT) (senza password): make vnc"

##@ Analisi dei file scaricati (container senza rete, file mai eseguiti)

av-update: analyzer-build ## Scarica/aggiorna le firme ClamAV (prima volta, poi periodicamente)
	$(COMPOSE) run --rm av-update

files: analyzer-build ## Elenca i file scaricati in Firefox
	@$(ANALYZE) list

scan: analyzer-build ## Antivirus ClamAV su tutti i download (FILE=nome per uno solo)
	@$(ANALYZE) scan $(if $(FILE),"$(FILE)")

inspect: analyzer-build ## Report completo dei download (FILE=nome per uno solo)
	@$(ANALYZE) inspect $(if $(FILE),"$(FILE)") | less -F -X

analyzer-shell: analyzer-build ## Shell per analisi manuale (olevba, exiftool, pdfinfo, 7z...; file in /downloads)
	$(COMPOSE) run --rm analyzer bash

##@ Monitoraggio e debug

proxy-logs: ## Segue il traffico in uscita: ogni host contattato dalla pagina
	$(COMPOSE) logs -f --no-log-prefix gateway

logs: ## Segue i log di browser e gateway
	$(COMPOSE) logs -f

ps: ## Stato dei container
	$(COMPOSE) ps

shell: ## Shell nel browser come utente non privilegiato
	docker exec -it -u browser $(CONTAINER_NAME) bash

shell-root: ## Shell nel browser come root (solo per debug)
	docker exec -it $(CONTAINER_NAME) bash

hosts-check: ## Mostra /etc/hosts dentro il browser
	docker exec $(CONTAINER_NAME) cat /etc/hosts

firefox-version: ## Versione di Firefox nel container in esecuzione
	docker exec $(CONTAINER_NAME) firefox --version

##@ Build e pulizia

build: ## Builda le immagini di browser e gateway (ultima release di Firefox)
	@echo "Firefox: $(FF_VERSION)"
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) build

rebuild: ## Come build, ma senza cache
	FIREFOX_VERSION=$(FF_VERSION) $(COMPOSE) build --no-cache

analyzer-build: ## Builda l'immagine dell'analyzer (fatto in automatico dai comandi di analisi)
	@$(COMPOSE) build -q analyzer

clean: ## Ferma tutto e rimuove immagini locali e firme ClamAV
	$(COMPOSE) --profile tools down --rmi all --volumes

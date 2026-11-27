# CLAUDE.md — debian-firefox-vnc-container

Container Docker con Debian `bookworm-slim` + Firefox, desktop accessibile via VNC.
Serve per test web, navigazione isolata e accesso a siti interni che richiedono
risoluzioni DNS custom (voci aggiunte a `/etc/hosts` all'avvio, senza rebuild).

## File

| File | Ruolo |
|---|---|
| `Dockerfile` | Immagine: pacchetti X11/GTK via apt, Firefox scaricato da `download.mozilla.org` (build arg `FIREFOX_VERSION`, default `latest`) in `/opt/firefox`, symlink `/usr/bin/firefox`. Espone 5900. |
| `entrypoint.sh` | Due fasi. Da root: applica `CUSTOM_HOSTS` a `/etc/hosts`, crea `/tmp/.X11-unix`, poi `exec setpriv` all'utente `browser` (uid 1000) rieseguendo se stesso. Da utente: `Xvfb :1` (1440x900x16, attende il socket `/tmp/.X11-unix/X1` fino a 10 s) → `openbox` → `firefox` → `exec x11vnc` (PID 1, senza password, `-forever -shared`). |
| `compose.yaml` | Servizi `browser` (build locale, arg `FIREFOX_VERSION`, `shm_size: 2gb`, solo rete `sandbox` interna, env `CUSTOM_HOSTS` + `http(s)_proxy=http://gateway:3128`) e `gateway` (porta VNC `${VNC_BIND:-127.0.0.1}:${VNC_PORT:-6000}:5900`, reti `sandbox` + `egress`). Hardening su entrambi (vedi sotto). Con profilo `tools`: `analyzer` (`network_mode: none`, volume `downloads` in sola lettura, firme in `clamav-db:ro`) e `av-update` (stessa immagine, rete `egress`, solo `clamav-db`). Volume `downloads` = tmpfs (`driver_opts`, `noexec`, uid 1000) montato in `/home/browser/Downloads`. |
| `gateway/` | Immagine del gateway (Debian + squid + socat, utente `proxy`). `squid.conf`: blocca destinazioni private/loopback/link-local/CGNAT, logga ogni richiesta su stdout. `entrypoint.sh`: genera `/tmp/hosts` e l'ACL `custom_hosts` da `CUSTOM_HOSTS`, avvia `socat` (5900 → `browser:5900`) e `squid -N`. |
| `analyzer/` | Immagine di analisi offline (ClamAV, oletools in venv, exiftool, poppler, qpdf, 7z, msgconvert, utente `analyst` uid 1000). `analyze` (entrypoint): `list`, `scan`, `inspect`, `update` (freshclam); ogni altro argomento viene eseguito (`analyze bash`). `eml.py`: header, link con testo mostrato, allegati di un `.eml`. |
| `firefox/policies.json` | Policy enterprise copiate in `/opt/firefox/distribution/`: niente password/autofill/cronologia moduli, estensioni bloccate, proxy di sistema bloccato, DoH off, WebRTC off, Safe Browsing bloccato su on. |
| `Makefile` | Comandi di uso quotidiano. `make` = `make help`: flusso d'uso + comandi per sezione (righe `##@ Titolo`; ogni target documentato con `target: ## testo` nella sezione giusta, e va aggiunto anche alla tabella "Commands" del README). Legge `my-hosts` in `CUSTOM_HOSTS`. |
| `my-hosts.example` | Modello per `my-hosts` (formato `/etc/hosts`, `#` = commento). `my-hosts` è in `.gitignore`. |
| `.github/workflows/docker-publish.yml` | Risolve l'ultima versione di Firefox (product-details.mozilla.org) e la passa come build arg. Push su `main` → `ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest`; tag `vX.Y.Z` → tag semver. Cache GHA. |

## Comandi

```sh
make hosts      # crea my-hosts dall'esempio
make up         # build + avvio, VNC su 127.0.0.1:6000
make up-ghcr    # usa l'immagine pubblicata invece della build locale
make av-update  # firme ClamAV (prima volta), poi: make files | make scan | make inspect [FILE=x] | make analyzer-shell
make logs | make proxy-logs | make shell (utente browser) | make shell-root | make hosts-check | make firefox-version
make down | make clean
```

Variabili sovrascrivibili: `VNC_PORT`, `VNC_BIND`, `IMAGE`, `CONTAINER_NAME`, `HOSTS_FILE`,
`FIREFOX_VERSION`, `MEM_LIMIT`, `CPUS`, `PIDS_LIMIT` (es. `make up VNC_PORT=6001`, `make build FIREFOX_VERSION=126.0`).

## Scopo e modello di sicurezza

Uso principale: **aprire link sospetti (phishing) senza rischi per l'host**. Ogni modifica
deve preservare queste protezioni (in `compose.yaml`, `entrypoint.sh`, `gateway/`,
`firefox/policies.json`):

- **rete**: `browser` solo sulla rete `sandbox` (`internal: true`, nessuna uscita né DNS
  esterno); esce solo via squid del `gateway`, che nega le destinazioni private (verifica
  sull'IP risolto, quindi anche DNS rebinding). Gli IP di `CUSTOM_HOSTS` sono whitelistati.
  Non aggiungere `ports` al servizio `browser` (Docker non pubblica porte su reti interne:
  il VNC passa da `socat` nel gateway);
- Firefox prende il proxy dalle variabili `http_proxy`/`https_proxy` (modalità "system",
  bloccata dalle policy): per questo `setpriv` **non** usa `--reset-env`;
- il gateway gira come `proxy` senza alcuna capability, `read_only`, niente stato su disco;

- tutto il desktop gira come `browser` (uid 1000), mai root; root serve solo per `/etc/hosts`;
- `cap_drop: ALL` + `cap_add: SETUID, SETGID` (solo per `setpriv`) + `no-new-privileges`:
  i processi finali hanno CapEff/CapPrm = 0;
- `read_only: true`; scrivibili solo i tmpfs `/tmp` e `/home/browser`, montati `noexec`
  (quindi niente binari eseguibili scaricati, profilo sempre pulito al riavvio);
- limiti `mem_limit`/`cpus`/`pids_limit` (Firefox con una scheda usa ~200 thread);
- niente volumi dell'host, niente `privileged`, niente socket Docker;
- download: volume Docker tmpfs (mai su disco, sparisce quando nessun container lo usa),
  `noexec`; l'analyzer lo monta `:ro`, senza rete, senza capability, `read_only`. I file
  vengono solo parsati, mai eseguiti/renderizzati. `av-update` ha Internet ma non vede i
  download: non unire i due ruoli;
- l'output di `analyze` passa sempre da `sanitize` (toglie ESC/controlli C0/C1): nomi e
  contenuti dei file sono controllati dall'attaccante e finiscono nel terminale dell'host.

Limiti noti: kernel condiviso con l'host (per il massimo isolamento: Docker in una VM o
gVisor); i siti visitati vedono l'IP pubblico; i comandi `docker run` del README non hanno
l'isolamento di rete.

Test di regressione manuali (da `docker exec -u browser <browser> ...`): `curl --noproxy '*'
https://example.com` deve fallire; via proxy, IP di host/LAN/Tailscale/`169.254.169.254`
devono dare 403 e `https://example.com` 200. `docker cp` non legge i tmpfs: per estrarre
file usare `docker exec ... cat`.

## Vincoli e insidie

- **`CUSTOM_HOSTS` è multilinea.** Non leggerlo con `$(shell cat ...)` nel Makefile (make
  converte i newline in spazi e l'entrypoint vedrebbe una sola riga). Va letto nella shell
  della ricetta: `CUSTOM_HOSTS="$$(cat my-hosts)" docker compose ...`. `docker compose up`
  lanciato a mano senza la variabile avvia il container senza host custom.
- **VNC senza password**: per questo compose espone la porta solo su `127.0.0.1` di default.
  Non cambiare questo default; per esporla in LAN si usa `VNC_BIND=0.0.0.0`.
- **`shm_size` 2 GB** è necessario: con il default di Docker (64 MB) Firefox crasha le tab.
- **Versione di Firefox e cache Docker**: con `FIREFOX_VERSION=latest` il layer di download
  resta in cache anche quando esce una nuova release. Per questo Makefile (`$(shell curl ...)`,
  valutato solo nelle ricette di build) e CI risolvono `latest` nel numero di versione
  concreto. L'archivio è `.tar.xz` per le release recenti e `.tar.bz2` per le vecchie:
  servono `xz-utils` e `bzip2`, e `tar -xf` riconosce la compressione da solo.
  La build è solo `linux64` (amd64).
- Firefox e openbox girano in background: se Firefox viene chiuso nel desktop il container
  resta vivo (PID 1 è x11vnc). Il warning `Sandbox: CanCreateUserNamespace() ... EPERM` nei
  log è atteso: Firefox non può usare gli user namespace nel container (e non vanno
  concessi), ma la sua sandbox seccomp resta attiva.
- `docker exec` senza `-u` entra come root (con le sole cap SETUID/SETGID): `make shell`
  usa `-u browser`.
- Parsing di `CUSTOM_HOSTS` in `entrypoint.sh`: rimuove i commenti (anche in coda alla riga),
  divide su qualsiasi spazio/tab, scarta righe senza hostname. Una voce è "già presente" se
  `/etc/hosts` mappa già **tutti** i suoi hostname su quell'IP (confronto esatto via awk,
  niente regex).
- `/etc/hosts` è un bind mount di Docker e resta scrivibile anche con `read_only: true`;
  root ci scrive senza `CAP_DAC_OVERRIDE` perché ne è il proprietario.
- `.dockerignore` esclude `.git`, `.github`, docs, `my-hosts*`, `Makefile`, `compose.yaml`,
  `CLAUDE.md`, `gateway/`, `analyzer/`: nell'immagine del browser finiscono solo
  `entrypoint.sh` e `firefox/policies.json`.
- `clamscan` impiega ~8 s solo per caricare le firme: `inspect` fa una scansione unica
  (`clam_batch`) e poi legge i verdetti; non chiamare `clamscan` per singolo file.
- I servizi con profilo `tools` non partono con `up`; `docker compose run` li avvia lo
  stesso. `av-update` non ha `build`: usa l'immagine dell'`analyzer` (il Makefile la builda prima).
- `scan` esce con 1 se trova qualcosa (codice di clamscan), quindi make segnala "Error 1".
- `squid.conf` non supporta commenti a fine riga: vanno su righe proprie.
- La CI pubblica solo l'immagine del browser; gateway e analyzer sono sempre buildati in locale da Compose.

## Convenzioni

- README e codice in inglese; la CI pubblica a ogni push su `main`, quindi ogni commit su
  `main` produce una nuova `latest`.

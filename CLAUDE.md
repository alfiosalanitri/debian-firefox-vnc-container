# CLAUDE.md — debian-firefox-vnc-container

Container Docker con Debian `bookworm-slim` + Firefox, desktop accessibile via VNC.
Serve per test web, navigazione isolata e accesso a siti interni che richiedono
risoluzioni DNS custom (voci aggiunte a `/etc/hosts` all'avvio, senza rebuild).

## File

| File | Ruolo |
|---|---|
| `Dockerfile` | Immagine: pacchetti X11/GTK via apt, Firefox scaricato da `download.mozilla.org` (build arg `FIREFOX_VERSION`, default `latest`) in `/opt/firefox`, symlink `/usr/bin/firefox`. Espone 5900. |
| `entrypoint.sh` | Avvio: applica `CUSTOM_HOSTS` a `/etc/hosts`, poi `Xvfb :1` (1440x900x16, attende il socket `/tmp/.X11-unix/X1` fino a 10 s) → `openbox` → `firefox --no-sandbox` → `exec x11vnc` (PID 1, senza password, `-forever -shared`). |
| `compose.yaml` | Servizio `browser`: build locale (arg `FIREFOX_VERSION`), `shm_size: 2gb`, porta `${VNC_BIND:-127.0.0.1}:${VNC_PORT:-6000}:5900`, env `CUSTOM_HOSTS`. |
| `Makefile` | Comandi di uso quotidiano (`make help`). Legge `my-hosts` in `CUSTOM_HOSTS`. |
| `my-hosts.example` | Modello per `my-hosts` (formato `/etc/hosts`, `#` = commento). `my-hosts` è in `.gitignore`. |
| `.github/workflows/docker-publish.yml` | Risolve l'ultima versione di Firefox (product-details.mozilla.org) e la passa come build arg. Push su `main` → `ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest`; tag `vX.Y.Z` → tag semver. Cache GHA. |

## Comandi

```sh
make hosts      # crea my-hosts dall'esempio
make up         # build + avvio, VNC su 127.0.0.1:6000
make up-ghcr    # usa l'immagine pubblicata invece della build locale
make logs | make shell | make hosts-check | make firefox-version
make down | make clean
```

Variabili sovrascrivibili: `VNC_PORT`, `VNC_BIND`, `IMAGE`, `CONTAINER_NAME`, `HOSTS_FILE`,
`FIREFOX_VERSION` (es. `make up VNC_PORT=6001`, `make build FIREFOX_VERSION=126.0`).

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
  log è atteso (Firefox gira con `--no-sandbox` dentro Docker).
- Parsing di `CUSTOM_HOSTS` in `entrypoint.sh`: rimuove i commenti (anche in coda alla riga),
  divide su qualsiasi spazio/tab, scarta righe senza hostname. Una voce è "già presente" se
  `/etc/hosts` mappa già **tutti** i suoi hostname su quell'IP (confronto esatto via awk,
  niente regex).
- Il container gira come root; `/etc/hosts` viene modificato a runtime, quindi non va
  montato in sola lettura.
- `.dockerignore` esclude `.git`, `.github`, docs, `my-hosts*`, `Makefile`, `compose.yaml`,
  `CLAUDE.md`: l'unico file copiato nell'immagine è `entrypoint.sh`.

## Convenzioni

- README e codice in inglese; la CI pubblica a ogni push su `main`, quindi ogni commit su
  `main` produce una nuova `latest`.

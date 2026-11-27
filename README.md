# Debian Firefox VNC Container

A disposable, isolated Firefox you reach over VNC, built to **open suspicious links and attachments from phishing e-mails without putting your machine at risk**.

-   Firefox runs in a hardened container that cannot reach your computer, your LAN or your VPN: only the public Internet, through a filtering and logging proxy.
-   Downloaded files never touch your disk and can be **scanned with ClamAV and inspected** (real type, hashes, Office macros, PDF scripts, e-mail headers and links, archive content) in a second container with no network at all.
-   Everything (profile, cookies, history, downloads) lives in RAM and disappears when you stop it.

It also works as a plain throw-away browser for web testing or for internal sites that need custom DNS entries (see [Custom host entries](#custom-host-entries)).

```
you ──VNC 127.0.0.1:6000──▶ gateway ──▶ browser (Firefox)
browser ──http(s)──▶ gateway (squid proxy) ──▶ public Internet      ✗ host, LAN, VPN, Docker networks
browser ──downloads (RAM)──▶ analyzer (no network): ClamAV, oletools, exiftool, pdf/zip/e-mail parsers
```

## Requirements

-   Docker with the Compose plugin (`docker compose`), on an amd64 machine.
-   `make`.
-   A VNC client: [Remmina](https://remmina.org/) or [TigerVNC](https://tigervnc.org/) on Linux, Screen Sharing or [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) on macOS, RealVNC/[TightVNC](https://www.tightvnc.com/download.php) on Windows.

## Usage

Run `make` alone at any time: it prints this workflow and every available command.

### 1. Start the sandbox

```sh
make up
```

The first run builds the images (Firefox is always the latest release) and takes a few minutes.

### 2. Connect

```sh
make vnc
```

This opens Remmina (or `vncviewer`) on `localhost:6000`; with any other client connect to `localhost:6000`, no password. You get a minimal desktop with Firefox.

### 3. Open the suspicious link

Copy the link from the e-mail and paste it into Firefox (the clipboard is shared through VNC). **Never type real credentials.**

In another terminal you can watch where the page goes:

```sh
make proxy-logs   # every host contacted: redirect chains, where a fake login form sends data
```

### 4. Analyze attachments

Download the attachment in the sandboxed Firefox (from the webmail opened there, or from the link). To analyze the whole e-mail, use your webmail's "Download original" / "Download as .eml". Then, from your terminal:

```sh
make av-update                 # only the first time, then every now and then: ClamAV signatures
make files                     # list what has been downloaded
make scan                      # antivirus on every download (FILE=name for a single one)
make inspect FILE=invoice.pdf  # full report (without FILE: every download)
```

`make scan` ends with `Error 1` when something is detected: that is ClamAV's exit code, not a failure. If Firefox's Safe Browsing blocks a download, that is already a verdict. See [What `make inspect` shows](#what-make-inspect-shows).

### 5. Reset

```sh
make restart   # fresh session: new profile, downloads deleted
make down      # stop everything (downloads deleted too)
```

Do it after every analysis.

## Commands

The same list, grouped, is printed by `make help`.

| Start and connect | |
|---|---|
| `make up` | Start browser and gateway (builds if needed) |
| `make vnc` | Open the VNC client on `localhost:6000` |
| `make restart` | Recreate the containers: clean session, re-reads `my-hosts` |
| `make down` | Stop and remove the containers (profile and downloads are deleted) |
| `make hosts` | Create `my-hosts` for custom `/etc/hosts` entries (optional) |
| `make up-ghcr` | Like `up`, with the browser image published on GHCR instead of a local build |

| Analyze downloaded files | |
|---|---|
| `make av-update` | Download/update the ClamAV signatures |
| `make files` | List the files downloaded in Firefox |
| `make scan [FILE=name]` | ClamAV scan |
| `make inspect [FILE=name]` | Full static report |
| `make analyzer-shell` | Shell in the analyzer for manual work (files in `/downloads`, read-only) |

| Monitor and debug | |
|---|---|
| `make proxy-logs` | Follow outgoing traffic (every host the page contacts) |
| `make logs` | Follow browser and gateway logs |
| `make ps` | Container status |
| `make shell` / `make shell-root` | Shell in the browser container (unprivileged / root) |
| `make hosts-check` | Print `/etc/hosts` inside the browser |
| `make firefox-version` | Firefox version in the running container |

| Build and clean up | |
|---|---|
| `make build` / `make rebuild` | Build browser and gateway (with / without cache) |
| `make analyzer-build` | Build the analyzer (done automatically by the analysis commands) |
| `make clean` | Stop everything, remove local images and ClamAV signatures |

### Options

Pass variables on the command line, e.g. `make up VNC_PORT=6001`:

| Variable | Default | Meaning |
|---|---|---|
| `VNC_PORT` | `6000` | Host port for VNC |
| `VNC_BIND` | `127.0.0.1` | Host address for VNC. `0.0.0.0` exposes the passwordless VNC on your network: trusted networks only |
| `FILE` | (all) | File for `scan` / `inspect`, relative to the downloads folder |
| `HOSTS_FILE` | `my-hosts` | Custom hosts file |
| `FIREFOX_VERSION` | latest release | Pin a Firefox version, e.g. `make build FIREFOX_VERSION=126.0` |
| `MEM_LIMIT` / `CPUS` / `PIDS_LIMIT` | `4g` / `2` / `1024` | Browser resource limits |

### Custom host entries

To reach sites that need custom DNS (e.g. internal hosts), run `make hosts`, edit `my-hosts` (same format as `/etc/hosts`, `#` for comments) and `make restart`:

```
192.168.1.100 alfiosalanitri.local alfiosalanitri
10.0.0.5      internal-service.lan   # trailing comments are ignored too
```

IPs listed there are trusted: the proxy lets the browser reach them even if they are private. `my-hosts` is git-ignored. `make hosts-check` shows the resulting `/etc/hosts`.

## What `make inspect` shows

For each file: size, real type (by content, not extension), MD5/SHA256 with a VirusTotal link (hash lookup only, the file is never uploaded), ClamAV verdict (with alerts for macros and encrypted archives) and metadata (exiftool). Then, depending on the type:

| Type | What is shown |
|---|---|
| PDF | info, count of risky keywords (`/JavaScript`, `/OpenAction`, `/Launch`, `/EmbeddedFile`, ... also inside compressed streams), link targets, text preview |
| Office (doc/xls/ppt, OOXML, encrypted) | `oleid`, VBA macros decoded by `olevba`, DDE links, external relationships (remote templates), embedded objects |
| RTF | embedded OLE objects (`rtfobj`) |
| `.eml` / `.msg` | sender, Reply-To, Return-Path, SPF/DKIM/DMARC results, `Received` chain, MIME tree, links in the body **with their displayed text** (to spot a `paypal.com` text pointing elsewhere), attachments, which are then extracted in RAM and inspected in turn |
| Archives (zip, 7z, rar, iso, cab, ...) | content listing (never extracted; no password prompt) |
| HTML / SVG / JS / text | suspicious constructs (`<script>`, `eval`, `atob`, forms posting elsewhere, redirects, ...) and a preview |
| anything else | printable strings |

Files are only parsed by command-line tools, never executed or rendered, and all output is stripped of control characters, so a file name or content carrying terminal escape sequences cannot affect your terminal.

For manual digging, `make analyzer-shell` provides `olevba`, `oleid`, `rtfobj`, `msodde`, `oleobj`, `exiftool`, `pdfinfo`, `pdftotext`, `qpdf`, `7z`, `strings`, `xxd`, `file` and `clamscan`. There the output is not filtered: pipe it through `cat -v`.

## Security

### Browser container

-   **Unprivileged user**: the entrypoint uses root only to edit `/etc/hosts`, then drops to user `browser` (uid 1000). Xvfb, openbox, Firefox and x11vnc never run as root.
-   **No capabilities**: `cap_drop: ALL` (only `SETUID`/`SETGID` are kept for the privilege drop; the browser processes end up with an empty capability set) and `no-new-privileges`, so setuid binaries cannot regain privileges.
-   **Read-only filesystem**: the image cannot be modified. `/tmp`, `/home/browser` and the downloads folder are in-memory `tmpfs` mounted `noexec`: downloaded files cannot be executed and everything is discarded when the containers stop.
-   **Resource limits**: memory (`MEM_LIMIT`), CPU (`CPUS`) and process count (`PIDS_LIMIT`).
-   **Default seccomp profile** and Firefox's own seccomp sandbox are active; nothing from the host is mounted.

### Network isolation

-   The `browser` container is attached only to an `internal` Docker network: it has **no route** to the outside world and no DNS for external names.
-   Its only way out is the squid proxy in the `gateway` container, which **denies every private, loopback, link-local and CGNAT destination** (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, `127/8`, `169.254/16`, `fc00::/7`, …). The check is done on the resolved IP, so public hostnames pointing to private addresses (DNS rebinding) are blocked too.
-   WebRTC is disabled and the proxy setting is locked in Firefox; even if a page bypassed it, the internal network has no way out.
-   The gateway also relays the VNC port (Docker cannot publish ports of containers on internal networks) and runs as an unprivileged user with no capabilities and a read-only filesystem.

### Analyzer

-   Started on demand by the analysis commands; **no network at all** (`network_mode: none`), unprivileged user, no capabilities, read-only filesystem, `noexec` `/tmp`.
-   Sees the downloads **read-only**: even a file that exploits one of the parsers has nothing to reach and nothing to modify.
-   The ClamAV signatures are updated by a separate container (`make av-update`) that has Internet access but never sees the downloads. They are kept in the `clamav-db` volume (`make clean` removes it).

### Firefox policies

`firefox/policies.json` disables the password manager, autofill and form history (credentials typed by mistake are never stored), blocks extension installs, turns off telemetry, update checks, DNS-over-HTTPS and PDF scripting, and locks Safe Browsing (phishing/malware/downloads) on. Check them in Firefox at `about:policies`.

### Limitations

-   Containers share the host kernel: a Firefox exploit chained with a kernel exploit could still escape. For the strongest isolation run Docker inside a VM (or use a stronger runtime such as gVisor).
-   The visited sites see your public IP address. Use a VPN on the host if you do not want phishers to see it.
-   VNC is unencrypted and passwordless: keep it bound to `127.0.0.1`.
-   The plain `docker run` commands below do **not** have the network isolation, the analyzer or the other Compose protections. Use `make up` for untrusted links.

## Other ways to run it

### Published image

Each push to `main` publishes `ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest` (built with the latest Firefox release); `vX.Y.Z` git tags publish matching version tags. `make up-ghcr` uses it with the full isolated setup (the small gateway image is built locally).

### Plain Docker Compose

Compose cannot read a file into a variable, so pass the custom hosts yourself:

```sh
CUSTOM_HOSTS="$(cat my-hosts)" docker compose up -d --build
docker compose run --rm -T analyzer inspect     # analyzer commands: list, scan, inspect, update
```

### Plain `docker run` (no isolation, not for phishing)

```sh
docker build -t debian-browser-app .            # or --build-arg FIREFOX_VERSION=126.0
docker run -d --rm --name debian-browser --shm-size=2gb \
  -p 127.0.0.1:6000:5900 \
  -e CUSTOM_HOSTS="$(cat my-hosts)" \
  debian-browser-app                            # or ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest
```

`--shm-size=2gb` is required (with Docker's 64 MB default Firefox tabs crash). Stop it with `docker stop debian-browser`.

## Project structure

| Path | Content |
|---|---|
| `Makefile` | Everyday commands (`make help`) |
| `compose.yaml` | Services `browser`, `gateway`, `analyzer`, `av-update`; networks and volumes |
| `Dockerfile`, `entrypoint.sh` | Browser image: Debian `bookworm-slim`, Firefox, Xvfb, openbox, x11vnc |
| `firefox/policies.json` | Firefox enterprise policies |
| `gateway/` | Egress proxy (squid) + VNC relay (socat) |
| `analyzer/` | Offline analysis image and the `analyze` script behind `files`, `scan`, `inspect` |
| `my-hosts.example` | Template for `my-hosts` |
| `.github/workflows/docker-publish.yml` | Builds and publishes the browser image to GHCR |
| `CLAUDE.md` | Project context for AI coding assistants |

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

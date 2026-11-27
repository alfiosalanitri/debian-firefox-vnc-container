# Debian Firefox VNC Container

This project provides a simple Docker container running Debian with Firefox, accessible via VNC. It's designed to be lightweight and easily configurable, allowing you to dynamically add custom host entries at runtime without rebuilding the image.

This setup is ideal for **safely opening suspicious links (e.g. from phishing emails)** to inspect their content without putting your machine at risk, as well as for web testing and accessing internal websites that require specific DNS resolutions.

## Features

-   **Debian `bookworm-slim`**: A minimal and stable base image.
-   **Firefox**: The latest Firefox release is installed at build time (or a pinned version via the `FIREFOX_VERSION` build argument).
-   **VNC Access**: A built-in VNC server (`x11vnc`) provides remote GUI access.
-   **Passwordless**: VNC connection is passwordless for ease of use in trusted environments.
-   **Hardened sandbox**: unprivileged user, no Linux capabilities, read-only filesystem, ephemeral in-memory profile, resource limits (see [Security](#security)).
-   **Network isolation**: the browser can reach the public Internet only through a filtering proxy that blocks your host, LAN and VPNs; every contacted host is logged.
-   **Hardened Firefox**: enterprise policies disable password/form saving and extension installs, and lock Safe Browsing on.
-   **Dynamic Host Entries**: Easily modify the container's `/etc/hosts` file on startup.
-   **Docker Compose + Makefile**: One-command build, run and management.
-   **GitHub Package**: Automatically builds and publishes to the GitHub Container Registry via GitHub Actions.

## Prerequisites

-   **Docker**: You must have Docker installed and running on your system.
-   **VNC Client**: You will need a VNC client to connect to the container's desktop.
    -   **Windows**: [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/), [TightVNC](https://www.tightvnc.com/download.php)
    -   **macOS**: Use the built-in **Screen Sharing** app or [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/).
    -   **Linux**: [Remmina](https://remmina.org/), [TigerVNC](https://tigervnc.org/), etc.

## Project Structure

-   `.github/workflows/docker-publish.yml`: GitHub Actions workflow to publish the image.
-   `Dockerfile`: Defines the Docker image (linux/amd64).
-   `compose.yaml`: Docker Compose services (`browser` + `gateway`) and networks.
-   `gateway/`: egress proxy (squid) + VNC relay image used by Compose.
-   `firefox/policies.json`: Firefox enterprise policies baked into the image.
-   `Makefile`: Shortcuts for building, running and managing the container (`make help`).
-   `CLAUDE.md`: Project context for AI coding assistants.
-   `entrypoint.sh`: The main script that runs inside the container.
-   `my-hosts.example`: An example template for custom host entries.
-   `README.md`: This file.
-   `LICENSE`: The project's MIT License.
-   `.gitignore`: Specifies files for Git to ignore.
-   `.dockerignore`: Specifies files for Docker to ignore during build.

### .gitignore

It is highly recommended to add `my-hosts` to a `.gitignore` file to prevent your local host configurations from being committed to source control.

Create a `.gitignore` file with the following content:
```
# .gitignore
my-hosts
```

### .dockerignore

This file prevents certain files and directories from being sent to the Docker daemon during the build. This practice speeds up the `docker build` command, reduces the build context size, and avoids accidentally copying sensitive or unnecessary files into the image.

## Quick Start (Makefile + Docker Compose)

The easiest way to run the container locally:

```sh
make hosts   # create my-hosts from my-hosts.example, then edit it
make up      # build the image (latest Firefox) and start the container
```

Then connect your VNC client to `localhost:6000` (no password).

Other useful targets (run `make help` for the full list):

| Command | Description |
|---|---|
| `make up-ghcr` | Run the published GHCR browser image (the small gateway image is built locally) |
| `make logs` | Follow the logs of browser and gateway |
| `make proxy-logs` | Follow only the outgoing traffic (every host the page contacts) |
| `make shell` | Open a bash shell inside the container (unprivileged user; `make shell-root` for root) |
| `make hosts-check` | Print `/etc/hosts` inside the container |
| `make firefox-version` | Print the Firefox version inside the container |
| `make restart` | Recreate the container (re-reads `my-hosts`) |
| `make down` / `make clean` | Stop the container / also remove the local image |

Variables can be overridden on the command line, e.g.:

```sh
make up VNC_PORT=6001                 # different host port
make build FIREFOX_VERSION=126.0      # pin a specific Firefox release
make up VNC_BIND=0.0.0.0              # expose VNC on all interfaces (trusted networks only!)
```

> **Security note**: VNC is passwordless, so by default the port is bound to `127.0.0.1` only.

If you prefer plain Docker Compose, pass the hosts file yourself (Compose cannot read a file into a variable):

```sh
CUSTOM_HOSTS="$(cat my-hosts)" docker compose up -d --build
```

## Manual Setup (plain Docker)

Follow these steps to build and run the container with plain `docker` commands.

### 1. Prepare Custom Host Entries

First, copy the example hosts file to `my-hosts`. This new file will be used by the container at runtime.

```sh
cp my-hosts.example my-hosts
```

Next, edit the `my-hosts` file to add any custom IP address and hostname mappings you need.

**Example `my-hosts`:**
```
# This is a comment and will be ignored
192.168.1.100 alfiosalanitri.local alfiosalanitri
10.0.0.5      internal-service.lan   # trailing comments are ignored too
```

Entries already present in `/etc/hosts` (same IP and hostnames) are skipped, and lines without a hostname are reported as invalid.

### 2. Build the Docker Image

Open a terminal in the project directory and run the following command to build the image:

```sh
docker build -t debian-browser-app .
```

This installs the latest Firefox release. To pin a version, pass it as a build argument:

```sh
docker build --build-arg FIREFOX_VERSION=126.0 -t debian-browser-app .
```

### 3. Run the Container

Run the container with the following command. This command starts the container in the background, maps the VNC port, sets the shared memory size, and passes the contents of your `my-hosts` file.

```sh
docker run -d --rm \
  --name debian-browser \
  --shm-size="2gb" \
  -p "127.0.0.1:6000:5900" \
  -e CUSTOM_HOSTS="$(cat my-hosts)" \
  debian-browser-app
```
> **Note**: If you don't need any custom hosts, you can omit the `-e CUSTOM_HOSTS="..."` line.

### 4. Connect via VNC

1.  Once the container is running, open your VNC client.
2.  Connect to the address: `localhost:6000` (or `127.0.0.1:6000`).
3.  No password is required.
4.  You should now see a simple desktop with Firefox running.

## Using the Published GitHub Package

This repository automatically builds and publishes the container to the GitHub Container Registry (GHCR). You can run the container without building it locally.

Each push to `main` publishes a `latest` tag built with the latest Firefox release at that time; `vX.Y.Z` git tags publish matching version tags.

For instructions on logging in to `ghcr.io` and running the image, please see the **Packages** page of this repository. The general command is:

```sh
docker run -d --rm \
  --name debian-browser \
  -p "127.0.0.1:6000:5900" \
  --shm-size="2gb" \
  -e CUSTOM_HOSTS="$(cat my-hosts)" \
  ghcr.io/alfiosalanitri/debian-firefox-vnc-container:latest
```

## Managing the Container

-   **View logs:** See the output from the startup script and VNC server.
    ```sh
    docker logs debian-browser
    ```
-   **Stop the container:**
    ```sh
    docker stop debian-browser
    ```
    Since the container was started with the `--rm` flag, it will be automatically removed when you stop it.

## Security

This container is meant for opening untrusted links (e.g. from phishing emails). With `make up` / `docker compose` it runs with:

-   **Unprivileged user**: the entrypoint uses root only to edit `/etc/hosts`, then drops to user `browser` (uid 1000). Xvfb, openbox, Firefox and x11vnc never run as root.
-   **No capabilities**: `cap_drop: ALL` (only `SETUID`/`SETGID` are kept for the privilege drop; the browser processes end up with an empty capability set) and `no-new-privileges`, so setuid binaries cannot regain privileges.
-   **Read-only filesystem**: the image cannot be modified. `/tmp` and `/home/browser` are in-memory `tmpfs` mounted `noexec`: downloaded files cannot be executed and everything (profile, cookies, history, downloads) is discarded when the container stops.
-   **Resource limits**: memory (`MEM_LIMIT`, default 4g), CPU (`CPUS`, default 2) and process count (`PIDS_LIMIT`, default 1024).
-   **Default seccomp profile** and Firefox's own seccomp sandbox are active; nothing from the host is mounted.

### Network isolation

```
host ──VNC 127.0.0.1:6000──▶ gateway ──▶ browser:5900
browser ──http(s)──▶ gateway:3128 (squid) ──▶ public Internet
                               ✗ host, Docker networks, LAN, VPN (Tailscale), cloud metadata
```

-   The `browser` container is attached only to an `internal` Docker network: it has **no route** to the outside world and no DNS for external names.
-   Its only way out is the squid proxy in the `gateway` container, which **denies every private, loopback, link-local and CGNAT destination** (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, `127/8`, `169.254/16`, `fc00::/7`, …). The check is done on the resolved IP, so public hostnames pointing to private addresses (DNS rebinding) are blocked too.
-   IPs listed in `my-hosts` are considered trusted and stay reachable even if private.
-   WebRTC is disabled and the proxy setting is locked in Firefox; even if a page bypassed it, the internal network has no way out.
-   `make proxy-logs` shows every request (for HTTPS, the `host:port` of each `CONNECT`): useful to see redirect chains and where a phishing form sends data.
-   The gateway runs as an unprivileged user with no capabilities and a read-only filesystem.

### Firefox policies

`firefox/policies.json` disables the password manager, autofill and form history (credentials typed by mistake are never stored), blocks extension installs, turns off telemetry, update checks, DNS-over-HTTPS and PDF scripting, and locks Safe Browsing (phishing/malware/downloads) on. Check them in Firefox at `about:policies`.

### Recommended workflow for phishing links

1.  `make up`, connect with VNC, paste the link (the clipboard is shared through VNC).
2.  Inspect the page; watch `make proxy-logs` to see which hosts it contacts. **Never type real credentials.**
3.  `make restart` (or `make down`) after each analysis: profile, cookies, history and downloads live only in RAM and are discarded.

### Limitations

-   Containers share the host kernel: a Firefox exploit chained with a kernel exploit could still escape. For the strongest isolation run Docker inside a VM (or use a stronger runtime such as gVisor).
-   The visited sites see your public IP address (the proxy only hides that a proxy is used). Use a VPN on the host if you do not want phishers to see it.
-   VNC is unencrypted and passwordless: keep it bound to `127.0.0.1`.
-   The plain `docker run` commands above also drop to the unprivileged user and apply the Firefox policies, but **without network isolation** and the other Compose protections. Use `make up` / Docker Compose for untrusted links.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
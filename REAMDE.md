# Debian Firefox VNC Container

This project provides a simple Docker container running Debian with Firefox, accessible via VNC. It's designed to be lightweight and easily configurable, allowing you to dynamically add custom host entries at runtime without rebuilding the image.

This setup is ideal for web testing, sandboxed browsing, or accessing internal websites that require specific DNS resolutions.

## Features

-   **Debian `bookworm-slim`**: A minimal and stable base image.
-   **Firefox**: The latest version of Firefox is pre-installed.
-   **VNC Access**: A built-in VNC server (`x11vnc`) provides remote GUI access.
-   **Passwordless**: VNC connection is passwordless for ease of use in trusted environments.
-   **Dynamic Host Entries**: Easily modify the container's `/etc/hosts` file on startup.
-   **GitHub Package**: Automatically builds and publishes to the GitHub Container Registry via GitHub Actions.

## Prerequisites

-   **Docker**: You must have Docker installed and running on your system.
-   **VNC Client**: You will need a VNC client to connect to the container's desktop.
    -   **Windows**: [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/), [TightVNC](https://www.tightvnc.com/download.php)
    -   **macOS**: Use the built-in **Screen Sharing** app or [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/).
    -   **Linux**: [Remmina](https://remmina.org/), [TigerVNC](https://tigervnc.org/), etc.

## Project Structure

-   `.github/workflows/docker-publish.yml`: GitHub Actions workflow to publish the image.
-   `Dockerfile`: Defines the multi-platform Docker image.
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

## Quick Start

Follow these steps to build and run the container locally.

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
10.0.0.5      internal-service.lan
```

### 2. Build the Docker Image

Open a terminal in the project directory and run the following command to build the image:

```sh
docker build -t debian-browser-app .
```

### 3. Run the Container

Run the container with the following command. This command starts the container in the background, maps the VNC port, sets the shared memory size, and passes the contents of your `my-hosts` file.

```sh
docker run -d --rm \
  --name debian-browser \
  --shm-size="2gb" \
  -p "6000:5900" \
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

For instructions on logging in to `ghcr.io` and running the image, please see the **Packages** page of this repository. The general command is:

```sh
docker run -d --rm \
  --name debian-browser \
  -p "6000:5900" \
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

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
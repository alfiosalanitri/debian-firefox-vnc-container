FROM debian:bookworm-slim

ENV DISPLAY=:1

RUN apt-get update && apt-get install -y \
    openbox \
    curl \
    x11vnc \
    xvfb \
    xterm \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libasound2 \
    libxss1 \
    libnss3 \
    libx11-6 \
    fonts-dejavu \
    tar \
    bzip2 \
    xz-utils \
    vim \
    menu \
    libpci3 \
    libegl1 \
    && update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/xterm 100 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Firefox version to install: "latest" or an exact release (e.g. "161.0").
# CI and the Makefile resolve "latest" to the concrete version number, so that a
# new Firefox release invalidates the Docker layer cache.
ARG FIREFOX_VERSION=latest

# download.mozilla.org redirects to the right archive (.tar.xz for recent
# releases, .tar.bz2 for old ones); GNU tar detects the compression itself.
RUN curl -fL -o /tmp/firefox.tar \
        "https://download.mozilla.org/?product=firefox-${FIREFOX_VERSION}&os=linux64&lang=en-US" && \
    tar -xf /tmp/firefox.tar -C /opt/ && \
    ln -s /opt/firefox/firefox /usr/bin/firefox && \
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox 100 && \
    rm /tmp/firefox.tar && \
    firefox --version

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5900

ENTRYPOINT ["/entrypoint.sh"]
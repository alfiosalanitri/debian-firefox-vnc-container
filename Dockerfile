FROM debian:bookworm-slim

ENV DISPLAY=:1

RUN apt-get update && apt-get install -y \
    openbox \
    curl \
    x11vnc \
    xvfb \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libasound2 \
    libxss1 \
    libnss3 \
    libx11-6 \
    fonts-dejavu \
    tar \
    bzip2 \
    vim \
    menu \
    libpci3 \
    libegl1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -L -o /tmp/firefox.tar.bz2 "https://ftp.mozilla.org/pub/firefox/releases/126.0/linux-x86_64/en-US/firefox-126.0.tar.bz2" && \
    tar -xjf /tmp/firefox.tar.bz2 -C /opt/ && \
    ln -s /opt/firefox/firefox /usr/bin/firefox && \
    rm /tmp/firefox.tar.bz2

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5900

ENTRYPOINT ["/entrypoint.sh"]
# Offline analyzer for files downloaded in the sandboxed browser.
#
# Runs with NO network (network_mode: none), as an unprivileged user, on a
# read-only filesystem, and sees the browser downloads read-only. The same
# image, attached to the egress network, is used only to update the ClamAV
# signatures (freshclam), without access to the downloads.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    clamav \
    file \
    binutils \
    xxd \
    less \
    libimage-exiftool-perl \
    poppler-utils \
    qpdf \
    p7zip-full \
    unzip \
    libemail-outlook-message-perl \
    python3 \
    python3-venv \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# oletools (olevba, oleid, rtfobj, msodde, mraptor) is not packaged in bookworm
ARG OLETOOLS_VERSION=0.60.2
RUN python3 -m venv /opt/oletools && \
    /opt/oletools/bin/pip install --no-cache-dir "oletools==${OLETOOLS_VERSION}" && \
    ln -s /opt/oletools/bin/olevba /opt/oletools/bin/oleid /opt/oletools/bin/rtfobj \
          /opt/oletools/bin/msodde /opt/oletools/bin/mraptor /opt/oletools/bin/oleobj \
          /usr/local/bin/

# Same uid as the browser user, so the downloads (mode 0700) are readable
RUN useradd --uid 1000 --create-home --shell /bin/bash analyst && \
    install -d -o analyst -g analyst /var/lib/clamav /downloads

COPY freshclam.conf /etc/clamav/freshclam.conf
COPY analyze /usr/local/bin/analyze
COPY eml.py /usr/local/lib/analyzer/eml.py
RUN chmod 0755 /usr/local/bin/analyze && chmod 0644 /usr/local/lib/analyzer/eml.py

USER analyst
WORKDIR /downloads

ENTRYPOINT ["/usr/local/bin/analyze"]
CMD ["help"]

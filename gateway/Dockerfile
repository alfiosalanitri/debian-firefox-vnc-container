# Network gateway for the sandboxed browser.
#
# - squid: the browser's ONLY way out to the Internet. Blocks every private,
#   loopback and link-local destination (host, Docker networks, LAN, VPNs).
# - socat: relays the VNC port from the host to the browser container, which
#   sits on an internal network and therefore cannot publish ports itself.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    squid \
    socat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Runs entirely unprivileged (Debian's "proxy" user)
USER proxy

EXPOSE 3128 5900

ENTRYPOINT ["/entrypoint.sh"]

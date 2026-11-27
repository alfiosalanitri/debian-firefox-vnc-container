#!/bin/bash
set -euo pipefail

# Runs as the unprivileged "proxy" user: nothing here needs root.

HOSTS_FILE=/tmp/hosts
ACL_FILE=/tmp/squid-custom-hosts.conf

# Hosts file for squid = container's /etc/hosts + CUSTOM_HOSTS entries.
# The IPs of CUSTOM_HOSTS are also whitelisted (they may be private).
cp /etc/hosts "$HOSTS_FILE"
# Placeholder value so the ACL is always defined (255.255.255.255 is never routed)
echo "acl custom_hosts dst 255.255.255.255/32" > "$ACL_FILE"

if [ -n "${CUSTOM_HOSTS:-}" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        read -r -a fields <<< "$line" || true
        [ ${#fields[@]} -lt 2 ] && continue
        echo "${fields[*]}" >> "$HOSTS_FILE"
        echo "acl custom_hosts dst ${fields[0]}" >> "$ACL_FILE"
        echo "✅ Allowed custom host: ${fields[*]}"
    done <<< "$CUSTOM_HOSTS"
fi

# VNC relay: host -> gateway:5900 -> browser:5900 (resolved at each connection)
socat TCP-LISTEN:5900,fork,reuseaddr TCP:"${BROWSER_HOST:-browser}":5900 &

echo "🛡️  Egress proxy listening on :3128 (private destinations blocked)"
exec squid -N -f /etc/squid/squid.conf

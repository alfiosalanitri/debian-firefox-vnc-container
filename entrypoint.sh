#!/bin/bash

# Read custom host entries from the CUSTOM_HOSTS environment variable

# Returns 0 if /etc/hosts already maps every given hostname to the given IP.
# Exact field comparison (no regex), so dots in IPs/hostnames are literal.
hosts_entry_exists() {
    local ip="$1"
    shift
    awk -v ip="$ip" -v wanted="$*" '
        BEGIN { n = split(wanted, w, " ") }
        { sub(/#.*/, "") }
        $1 == ip { for (i = 2; i <= NF; i++) seen[$i] = 1 }
        END { for (j = 1; j <= n; j++) if (!(w[j] in seen)) exit 1 }
    ' /etc/hosts
}

if [ -n "$CUSTOM_HOSTS" ]; then
    echo "Processing custom host entries..."
    while IFS= read -r line || [ -n "$line" ]; do
        # Drop comments (whole-line or trailing) and split on any whitespace
        line="${line%%#*}"
        read -r -a fields <<< "$line"

        # Skip empty lines
        [ ${#fields[@]} -eq 0 ] && continue

        if [ ${#fields[@]} -lt 2 ]; then
            echo "❌ Invalid entry (missing hostname): ${fields[*]}"
            continue
        fi

        entry="${fields[*]}"
        if hosts_entry_exists "${fields[@]}"; then
            echo "⚠️  Already present: $entry"
        else
            echo "$entry" >> /etc/hosts
            echo "✅ Added: $entry"
        fi
    done <<< "$CUSTOM_HOSTS"
else
    echo "ℹ️  No CUSTOM_HOSTS environment variable found. Skipping."
fi

echo "--- /etc/hosts content ---"
cat /etc/hosts
echo "--------------------------"


# Start the virtual framebuffer on display :1
Xvfb :1 -screen 0 1440x900x16 &
xvfb_pid=$!

# Wait until Xvfb has created its socket (up to 10 seconds)
for _ in $(seq 1 50); do
    [ -S /tmp/.X11-unix/X1 ] && break
    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
        echo "❌ Xvfb exited unexpectedly" >&2
        exit 1
    fi
    sleep 0.2
done
if [ ! -S /tmp/.X11-unix/X1 ]; then
    echo "❌ Xvfb did not start within 10 seconds" >&2
    exit 1
fi

# Start the window manager
openbox &

# Start Firefox
firefox --no-sandbox &

# Start the VNC server and make it the main process
# The 'exec' command replaces the current shell process with x11vnc,
# ensuring the container stays running as long as the VNC server is up.
echo "🚀 Starting VNC server on port 5900"
exec x11vnc -display :1 -nopw -forever -shared -rfbport 5900

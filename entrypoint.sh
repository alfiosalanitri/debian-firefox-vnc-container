#!/bin/bash

# Read custom host entries from the CUSTOM_HOSTS environment variable

if [ -n "$CUSTOM_HOSTS" ]; then
    echo "Processing custom host entries..."
    # Use a "here string" to read from the variable line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Clean up leading/trailing spaces and multiple spaces
        trimmed="$(echo "$line" | tr -s '[:space:]' ' ' | sed 's/^ *//')"
        
        # Skip empty lines or comments
        [ -z "$trimmed" ] && continue
        [[ "$trimmed" == \#* ]] && continue

        # Extract IP and hosts
        ip=$(echo "$trimmed" | cut -d' ' -f1)
        hosts=$(echo "$trimmed" | cut -d' ' -f2-)

        # Check if the line already effectively exists
        if ! grep -qE "^\s*$ip\s+.*\b$hosts\b" /etc/hosts; then
            echo "$trimmed" >> /etc/hosts
            echo "✅ Added: $trimmed"
        else
            echo "⚠️  Already present: $trimmed"
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
sleep 2 # Give Xvfb time to start

# Start the window manager
openbox &

# Start Firefox
firefox --no-sandbox &

# Start the VNC server and make it the main process
# The 'exec' command replaces the current shell process with x11vnc,
# ensuring the container stays running as long as the VNC server is up.
echo "🚀 Starting VNC server on port 5900"
exec x11vnc -display :1 -nopw -forever -shared -rfbport 5900
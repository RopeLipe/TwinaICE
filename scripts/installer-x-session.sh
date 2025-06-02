#!/bin/bash
#
# TwinaOS Installer X Session Startup Script
# This script ensures proper X session initialization for the installer
#

# Wait for X to be ready
export DISPLAY=:0
export HOME=/home/installer

# Log startup
echo "Starting TwinaOS installer X session..." > /tmp/installer-x.log

# Wait for network to be ready
for i in {1..30}; do
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Network is ready" >> /tmp/installer-x.log
        break
    fi
    echo "Waiting for network... ($i/30)" >> /tmp/installer-x.log
    sleep 1
done

# Start window manager
openbox &
OPENBOX_PID=$!

# Wait for openbox to start
sleep 2

# Check if installer service is running
for i in {1..10}; do
    if curl -s http://localhost:5000 >/dev/null 2>&1; then
        echo "Installer service is ready" >> /tmp/installer-x.log
        break
    fi
    echo "Waiting for installer service... ($i/10)" >> /tmp/installer-x.log
    sleep 1
done

# Start browser in kiosk mode
chromium \
    --kiosk \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu-sandbox \
    --disable-software-rasterizer \
    --disable-dev-tools \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-infobars \
    --disable-suggestions-service \
    --disable-save-password-bubble \
    --disable-session-crashed-bubble \
    --incognito \
    http://localhost:5000 &

# Keep the session running
wait $OPENBOX_PID
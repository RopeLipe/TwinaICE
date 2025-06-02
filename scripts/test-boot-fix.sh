#!/bin/bash
#
# Test script to verify boot fixes
#

echo "TwinaOS Boot Fix Test Script"
echo "============================"
echo
echo "This script will help verify the boot fixes are working correctly."
echo

# Check if running as installer user
if [[ "$USER" == "installer" ]]; then
    echo "✓ Running as installer user"
else
    echo "✗ Not running as installer user (current: $USER)"
fi

# Check if X is running
if [[ -n "$DISPLAY" ]]; then
    echo "✓ X display is set: $DISPLAY"
else
    echo "✗ X display is not set"
fi

# Check if openbox is running
if pgrep -x openbox >/dev/null; then
    echo "✓ Openbox is running"
else
    echo "✗ Openbox is not running"
fi

# Check if installer service is running
if systemctl is-active --quiet installer.service; then
    echo "✓ Installer service is active"
else
    echo "✗ Installer service is not active"
    echo "  Status: $(systemctl is-active installer.service)"
fi

# Check if web server is accessible
if curl -s http://localhost:5000 >/dev/null 2>&1; then
    echo "✓ Web installer is accessible at http://localhost:5000"
else
    echo "✗ Web installer is not accessible"
fi

# Check if chromium is running
if pgrep -x chromium >/dev/null; then
    echo "✓ Chromium browser is running"
else
    echo "✗ Chromium browser is not running"
fi

echo
echo "Boot configuration files:"
echo "------------------------"

# Check for bootloader configs
for config in /isolinux/isolinux.cfg /syslinux/syslinux.cfg /boot/grub/grub.cfg; do
    if [[ -f "$config" ]]; then
        echo "Found: $config"
        grep -E "(timeout|prompt|default)" "$config" 2>/dev/null | head -5
        echo
    fi
done

echo
echo "Troubleshooting tips:"
echo "--------------------"
echo "1. If X is not running, try: startx"
echo "2. If installer service fails, check: journalctl -u installer.service"
echo "3. If browser doesn't start, try manually: chromium --kiosk http://localhost:5000"
echo "4. Check logs in: /tmp/installer-x.log"
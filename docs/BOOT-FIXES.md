# TwinaOS Boot Fixes Documentation

## Overview

This document describes the fixes implemented to address two main issues:
1. Making the bootloader silent and auto-boot immediately
2. Ensuring Openbox/Desktop environment launches properly after auto-login

## Issue 1: Silent Bootloader

### Problem
The bootloader menu was visible to users, requiring manual selection or waiting for timeout.

### Solution
Added a binary hook (`0005-configure-bootloader.hook.binary`) that:
- Sets bootloader timeout to 0 (immediate boot)
- Disables prompt mode
- Removes menu UI elements
- Sets default boot label to 'live'

The hook handles multiple bootloader types:
- isolinux
- syslinux  
- GRUB (if present)

### Implementation
```bash
# In config/hooks/live/0005-configure-bootloader.hook.binary
sed -i 's/timeout .*/timeout 0/' binary/isolinux/isolinux.cfg
sed -i 's/prompt .*/prompt 0/' binary/isolinux/isolinux.cfg
sed -i '/^ui /d' binary/isolinux/isolinux.cfg
sed -i '/^menu /d' binary/isolinux/isolinux.cfg
```

## Issue 2: Openbox Not Launching

### Problem
After auto-login, the installer user was logged in but X server and Openbox were not starting.

### Root Cause
- No automatic X server startup after console login
- Missing xinit package
- Incorrect service dependencies

### Solution
Implemented a multi-step approach:

1. **Auto-login Configuration**
   - Getty service override for automatic login of 'installer' user

2. **Automatic X Server Start**
   - Added `.bash_profile` that checks if on tty1 and starts X
   - Ensures X only starts once and on the correct terminal

3. **X Session Configuration**
   - `.xinitrc` starts openbox-session and chromium in kiosk mode
   - Proper timing with sleep to ensure services are ready

4. **Package Dependencies**
   - Added xinit package
   - Added xserver-xorg-video-all and xserver-xorg-input-all for hardware compatibility

### Implementation Details

#### Auto-start X on login (.bash_profile):
```bash
if [[ -z "$DISPLAY" ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
```

#### X session startup (.xinitrc):
```bash
#!/bin/bash
openbox-session &
sleep 2
chromium --kiosk --no-sandbox --disable-dev-shm-usage http://localhost:5000 &
wait
```

## Boot Flow

1. **BIOS/UEFI** → Bootloader (silent, 0 timeout)
2. **Kernel Boot** → Plymouth splash (quiet mode)
3. **Systemd Init** → Multi-user target
4. **Getty Auto-login** → Installer user logged in
5. **Bash Profile** → Detects tty1, starts X
6. **X Session** → Openbox starts
7. **Openbox Autostart** → Chromium launches in kiosk mode
8. **Web Installer** → Ready for user interaction

## Testing

To verify the fixes are working:

1. Build the ISO with updated scripts
2. Boot in a VM or physical hardware
3. Observe:
   - No bootloader menu visible
   - Automatic progression to Plymouth splash
   - Auto-login occurs
   - X server starts automatically
   - Chromium opens in fullscreen with installer

## Troubleshooting

If issues persist:

1. **Bootloader still visible**:
   - Check if binary hook is executing
   - Verify bootloader type matches hook logic
   - Check build logs for hook execution

2. **X server not starting**:
   - Switch to tty2 (Ctrl+Alt+F2) and login
   - Check if xinit is installed: `which startx`
   - Try manual start: `startx`
   - Check logs: `journalctl -b`

3. **Openbox not starting**:
   - Check ~/.xsession-errors
   - Verify openbox is installed
   - Try running manually: `DISPLAY=:0 openbox`

4. **Chromium not launching**:
   - Check if installer service is running: `systemctl status installer`
   - Verify port 5000 is accessible: `curl http://localhost:5000`
   - Check Openbox autostart: `~/.config/openbox/autostart`

## Configuration Files Modified

- `/etc/systemd/system/getty@tty1.service.d/override.conf` - Auto-login
- `/home/installer/.bash_profile` - Auto-start X
- `/home/installer/.xinitrc` - X session configuration
- `/home/installer/.config/openbox/autostart` - Openbox startup apps
- `binary/isolinux/isolinux.cfg` - Bootloader configuration (via hook)
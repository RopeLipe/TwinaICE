# TwinaOS Build Instructions

## Overview

This document provides comprehensive instructions for building and testing the TwinaOS Live Installer ISO.

## Prerequisites

### Host System Requirements
- Windows 10/11 host machine
- VirtualBox, VMware, or Hyper-V
- 8GB+ RAM (4GB for VM)
- 50GB+ free disk space

### Debian VM Requirements
- Debian 12 (Bookworm) or newer
- Minimum 4GB RAM allocated
- 20GB+ disk space
- Internet connection
- sudo privileges

## Step 1: VM Setup

### Install Debian 12 in VM

1. **Download Debian 12 ISO**:
   ```
   https://www.debian.org/distrib/
   ```

2. **Create VM with these specs**:
   - RAM: 4GB minimum (6GB+ recommended)
   - Disk: 30GB minimum
   - CPU: 2+ cores
   - Network: NAT or Bridged

3. **Install Debian**:
   - Choose "Standard system utilities" + "SSH server"
   - Create user account with sudo privileges
   - Complete basic installation

### VM Network Configuration

Configure port forwarding for testing:
- Host port 8080 → Guest port 5000 (Flask installer)
- Host port 2222 → Guest port 22 (SSH access)

## Step 2: Development Environment

### Login to Debian VM

```bash
# SSH from Windows host (if port forwarding configured)
ssh -p 2222 username@localhost

# Or use VM console directly
```

### Clone TwinaOS Repository

```bash
# Clone the project
git clone <repository-url> twinaos
cd twinaos

# Make scripts executable
chmod +x scripts/*.sh
```

### Setup Build Environment

```bash
# Run the setup script
./scripts/setup-dev-env.sh

# This will install:
# - Live-build tools
# - Python dependencies
# - QEMU for testing
# - Required packages
```

## Step 3: Build Process

### Quick Build (Recommended)

```bash
# Build everything in one command
./scripts/build-iso.sh

# This process takes 20-60 minutes depending on:
# - Internet speed (downloading packages)
# - VM performance
# - Debian mirror speed
```

### Manual Build Steps

If you prefer step-by-step control:

```bash
# 1. Setup build environment
./scripts/setup-build-env.sh

# 2. Configure live-build
cd build
lb config --distribution bookworm --architecture amd64

# 3. Customize configuration
# Edit config/ directories as needed

# 4. Build the ISO
sudo lb build

# 5. Find the generated ISO
ls -la *.iso
```

### Build Output

Successful build produces:
```
build/live-image-amd64.hybrid.iso
```

This file is renamed to:
```
twinaos-installer-YYYYMMDD.iso
```

## Step 4: Testing

### Test in QEMU (VM)

```bash
# Quick test
./scripts/test-qemu.sh twinaos-installer.iso

# Test in UEFI mode
./scripts/test-qemu.sh --uefi

# Test with VNC (headless)
./scripts/test-qemu.sh --vnc
```

### Test in VirtualBox (Windows Host)

1. **Create new VM**:
   - Type: Linux
   - Version: Debian (64-bit)
   - RAM: 2GB minimum
   - No hard disk needed for live testing

2. **Boot from ISO**:
   - Settings → Storage → Add optical drive
   - Select the generated ISO file
   - Boot order: Optical drive first

3. **Test installation**:
   - Add a virtual hard disk for installation testing
   - Size: 20GB minimum

### Access Web Installer

Once the ISO boots:

1. **Wait for Plymouth splash screen**
2. **Auto-login occurs**
3. **Flask installer starts automatically**
4. **Access via**:
   - Direct VM: http://localhost:5000
   - Port forwarded: http://localhost:8080

## Step 5: Customization

### Modify Installer UI

```bash
# Edit web interface
nano installer/templates/index.html
nano installer/static/css/installer.css
nano installer/static/js/installer.js

# Rebuild ISO to test changes
./scripts/build-iso.sh
```

### Change Package List

```bash
# Edit build script packages
nano scripts/build-iso.sh

# Or edit configuration
nano config/twinaos.yaml
```

### Customize Plymouth Theme

```bash
# Edit splash screen
nano splash/twinaos.plymouth

# Add custom images to splash/
```

## Step 6: Debugging

### Enable Debug Mode

During boot or in installer:
- Press `Ctrl+Alt+D` to enable debug mode
- Access terminal and logs
- View installation progress

### Check Logs

```bash
# In live system
tail -f /tmp/twinaos-install.log

# System logs
journalctl -f

# Flask application logs
systemctl status installer.service
```

### Manual Testing

```bash
# Access shell during installation
sudo systemctl stop installer.service

# Run installer manually
cd /opt/twinaos
python3 app.py --debug

# Or test components individually
bash lib/install_functions.sh
```

## Troubleshooting

### Build Failures

1. **Network issues**:
   ```bash
   # Test connectivity
   ping debian.org
   
   # Try different mirror
   nano config/auto/config
   ```

2. **Permission errors**:
   ```bash
   # Fix permissions
   sudo chown -R $USER:$USER build/
   ```

3. **Space issues**:
   ```bash
   # Check disk space
   df -h
   
   # Clean old builds
   sudo rm -rf build/
   ```

### Boot Issues

1. **ISO won't boot**:
   - Verify VM settings (enable virtualization)
   - Check ISO integrity
   - Try different VM software

2. **Plymouth not showing**:
   - Check VM graphics acceleration
   - Verify theme installation

3. **Installer not starting**:
   - Check systemd service status
   - Verify Python dependencies
   - Check network configuration

### Installation Issues

1. **Network detection**:
   - Ensure VM has network access
   - Check NetworkManager service
   - Verify WiFi drivers (for real hardware)

2. **Disk partitioning**:
   - Ensure target disk is unmounted
   - Check disk permissions
   - Verify UEFI/BIOS detection

## Production Deployment

### Hardware Testing

1. **Create bootable USB**:
   ```bash
   # From Windows host
   # Use Rufus, Etcher, or dd
   ```

2. **Test on target hardware**:
   - Boot from USB
   - Test touch interface
   - Verify WiFi connectivity
   - Complete installation

### Distribution

1. **Generate checksums**:
   ```bash
   sha256sum twinaos-installer.iso > twinaos-installer.iso.sha256
   ```

2. **Create release package**:
   ```bash
   # Include documentation and checksums
   tar -czf twinaos-installer-v1.0.tar.gz \
       twinaos-installer.iso \
       twinaos-installer.iso.sha256 \
       README.md \
       INSTALL.md
   ```

## Performance Optimization

### Build Speed

1. **Use local mirror**:
   ```bash
   # Edit config for faster downloads
   nano config/auto/config
   ```

2. **Parallel builds**:
   ```bash
   # Use multiple CPU cores
   export MAKEFLAGS="-j$(nproc)"
   ```

3. **Cache packages**:
   ```bash
   # Preserve package cache between builds
   mkdir -p cache/packages
   ```

### Runtime Performance

1. **Optimize Python**:
   ```bash
   # Use production WSGI server
   pip3 install gunicorn
   ```

2. **Reduce services**:
   ```bash
   # Disable unnecessary services
   systemctl disable unnecessary.service
   ```

## Security Considerations

### Live System Security

- Default passwords are for development only
- Disable SSH in production builds
- Review installed packages regularly
- Update base system frequently

### Installation Security

- Verify user input validation
- Secure disk operations
- Protect against injection attacks
- Implement proper error handling

## Support and Contributions

### Getting Help

1. Check troubleshooting section
2. Review logs and debug output
3. Test on different hardware/VMs
4. Submit issues with full details

### Contributing

1. Fork the repository
2. Create feature branches
3. Test thoroughly
4. Submit pull requests
5. Document changes

## License

This project is licensed under GPLv3. See LICENSE file for details.

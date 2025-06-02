# TwinaOS - Custom Debian Live Installer ISO

A tablet-focused operating system installer built on Debian with a modern web-based GUI installer.

## Features

- **Web-based Installer**: Modern HTML5/CSS3 GUI using Flask
- **Touch-friendly Interface**: Large buttons, swipe gestures, responsive design
- **Silent Boot**: Plymouth splash screen with quiet kernel messages
- **Auto-boot**: No timeout, direct boot into installer
- **Complete Installation Workflow**: Language, keyboard, timezone, WiFi, partitioning, user setup
- **Real-time Progress**: Live installation progress with status updates
- **Debug Mode**: Accessible via Ctrl+Alt+D hotkey

## Development Environment

### Prerequisites

- Windows host machine
- Debian VM for ISO building
- VirtualBox or VMware for testing
- Minimum 4GB RAM for VM
- 20GB+ free disk space

### VM Setup

1. **Install Debian 12 (Bookworm) in VM**:
   ```bash
   # Minimal installation with build tools
   sudo apt update
   sudo apt install -y build-essential git wget curl
   sudo apt install -y live-build squashfs-tools xorriso isolinux
   sudo apt install -y python3 python3-pip python3-venv
   ```

2. **Clone and setup project**:
   ```bash
   git clone <repository-url> twinaos
   cd twinaos
   chmod +x scripts/*.sh
   ```

## Build Instructions

### Quick Build
```bash
./scripts/build-iso.sh
```

### Manual Build Process

1. **Prepare build environment**:
   ```bash
   ./scripts/setup-build-env.sh
   ```

2. **Create live system**:
   ```bash
   ./scripts/create-live-system.sh
   ```

3. **Build installer components**:
   ```bash
   ./scripts/build-installer.sh
   ```

4. **Generate ISO**:
   ```bash
   ./scripts/generate-iso.sh
   ```

### Testing

1. **Test in QEMU**:
   ```bash
   ./scripts/test-iso.sh twinaos-installer.iso
   ```

2. **Test in VirtualBox**:
   - Create new VM with 2GB+ RAM
   - Boot from generated ISO
   - Test installation process

## Project Structure

```
twinaos/
├── build/                  # Build artifacts
├── config/                 # Live-build configuration
├── installer/              # Web installer application
│   ├── app.py             # Flask application
│   ├── static/            # CSS, JS, images
│   ├── templates/         # HTML templates
│   └── lib/               # Installation libraries
├── scripts/               # Build and utility scripts
├── splash/                # Plymouth theme
├── systemd/               # Service files
└── docs/                  # Documentation
```

## Usage

1. Boot the ISO on target device
2. Wait for splash screen and auto-boot
3. Web installer launches automatically
4. Follow on-screen installation wizard
5. Reboot into installed system

## Debug Mode

Press `Ctrl+Alt+D` during boot or in installer to access:
- Terminal access
- Installation logs
- System diagnostics
- Manual partitioning tools

## Customization

- Modify `config/auto/config` for live-build settings
- Edit `installer/templates/` for UI customization
- Update `splash/` for custom boot animation
- Adjust `systemd/installer.service` for startup behavior

## License

GPLv3 - See LICENSE file for details

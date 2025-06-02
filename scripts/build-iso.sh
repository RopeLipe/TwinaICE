#!/bin/bash
#
# TwinaOS ISO Builder
# Builds a custom Debian Live Installer ISO for tablet devices
#

set -e

# Configuration
WORK_DIR="$(pwd)/build"
ISO_NAME="twinaos-installer"
DEBIAN_VERSION="bookworm"
ARCH="amd64"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should NOT be run as root. Use sudo only when prompted."
    fi
}

# Check dependencies
check_dependencies() {
    log "Checking build dependencies..."
    
    local deps=("live-build" "squashfs-tools" "xorriso" "isolinux" "python3" "python3-pip")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep "; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}. Please install with: sudo apt install ${missing[*]}"
    fi
    
    success "All dependencies satisfied"
}

# Clean previous builds
clean_build() {
    log "Cleaning previous build artifacts..."
    if [[ -d "$WORK_DIR" ]]; then
        sudo rm -rf "$WORK_DIR"
    fi
    mkdir -p "$WORK_DIR"
    success "Build directory cleaned"
}

# Setup live-build configuration
setup_live_config() {
    log "Setting up live-build configuration..."
    
    cd "$WORK_DIR"
    
    # Initialize live-build
    lb config \
        --distribution "$DEBIAN_VERSION" \
        --architecture "$ARCH" \
        --archive-areas "main contrib non-free-firmware" \
        --binary-images iso-hybrid \
        --bootappend-live "boot=live components quiet splash" \
        --bootloaders syslinux \
        --debian-installer false \
        --iso-application "Twina Ice" \
        --iso-publisher "Tectonic Software" \
        --iso-volume "Twina-$(date +%Y%m%d)" \
        --memtest none \
        --win32-loader false
    
    success "Live-build configuration created"
}

# Copy installer files
copy_installer() {
    log "Copying installer files..."
    
    # Create necessary directories
    mkdir -p "$WORK_DIR/config/includes.chroot/opt/twinaos"
    mkdir -p "$WORK_DIR/config/includes.chroot/etc/systemd/system"
    mkdir -p "$WORK_DIR/config/includes.chroot/usr/share/plymouth/themes/twinaos"
    
    # Copy installer application
    cp -r ../installer/* "$WORK_DIR/config/includes.chroot/opt/twinaos/"
    
    # Copy systemd service
    cp ../systemd/installer.service "$WORK_DIR/config/includes.chroot/etc/systemd/system/"
    
    # Copy Plymouth theme
    cp -r ../splash/* "$WORK_DIR/config/includes.chroot/usr/share/plymouth/themes/twinaos/"
    
    success "Installer files copied"
}

# Create package lists
create_package_lists() {
    log "Creating package lists..."
    
    mkdir -p "$WORK_DIR/config/package-lists"
    
    # Base packages
    cat > "$WORK_DIR/config/package-lists/base.list.chroot" << 'EOF'
# Base system
live-boot
live-config
live-config-systemd

# Network and WiFi
network-manager
wpasupplicant
wireless-tools
firmware-iwlwifi
firmware-realtek
firmware-atheros

# Python and web server
python3
python3-pip
python3-venv
python3-flask
python3-requests
python3-psutil

# Installation tools
debootstrap
gdisk
parted
e2fsprogs
dosfstools
grub-pc-bin
grub-efi-amd64-bin

# Graphics and boot
plymouth
plymouth-themes
xserver-xorg-core
chromium
openbox

# Utilities
curl
wget
rsync
sudo
systemd
EOF

    success "Package lists created"
}

# Create hooks
create_hooks() {
    log "Creating live-build hooks..."
    
    mkdir -p "$WORK_DIR/config/hooks/live"
    
    # Hook to setup installer service
    cat > "$WORK_DIR/config/hooks/live/0010-setup-installer.hook.chroot" << 'EOF'
#!/bin/bash

# Enable installer service
systemctl enable installer.service

# Install Python dependencies
pip3 install flask flask-socketio psutil

# Setup Plymouth theme
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/twinaos/twinaos.plymouth 100
update-alternatives --set default.plymouth /usr/share/plymouth/themes/twinaos/twinaos.plymouth

# Configure Plymouth
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub

# Create installer user
useradd -m -s /bin/bash -G sudo installer
echo "installer:installer" | chpasswd

# Auto-login for installer user
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOFINNER'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin installer --noclear %I $TERM
EOFINNER

# Setup auto-start for installer
mkdir -p /home/installer/.config/openbox
cat > /home/installer/.config/openbox/autostart << 'EOFINNER'
# Start installer web browser
sleep 5
chromium --kiosk --no-sandbox --disable-dev-shm-usage http://localhost:5000 &
EOFINNER

chown -R installer:installer /home/installer/.config
EOF

    chmod +x "$WORK_DIR/config/hooks/live/0010-setup-installer.hook.chroot"
    
    success "Hooks created"
}

# Build the live system
build_live() {
    log "Building live system (this may take a while)..."
    
    cd "$WORK_DIR"
    sudo lb build
    
    success "Live system built successfully"
}

# Copy ISO to output
copy_iso() {
    log "Copying ISO to output..."
    
    if [[ -f "$WORK_DIR/live-image-${ARCH}.hybrid.iso" ]]; then
        cp "$WORK_DIR/live-image-${ARCH}.hybrid.iso" "../${ISO_NAME}-$(date +%Y%m%d).iso"
        success "ISO created: ${ISO_NAME}-$(date +%Y%m%d).iso"
    else
        error "ISO file not found after build"
    fi
}

# Main build process
main() {
    log "Starting TwinaOS ISO build process..."
    
    check_root
    check_dependencies
    clean_build
    setup_live_config
    copy_installer
    create_package_lists
    create_hooks
    build_live
    copy_iso
    
    success "TwinaOS ISO build completed successfully!"
    log "ISO file: ${ISO_NAME}-$(date +%Y%m%d).iso"
    log "You can now test the ISO in a virtual machine"
}

# Run main function
main "$@"

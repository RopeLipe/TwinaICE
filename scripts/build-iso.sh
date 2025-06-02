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
        --archive-areas "main contrib non-free non-free-firmware" \
        --binary-images iso-hybrid \
        --bootappend-live "boot=live components quiet splash noautologin" \
        --bootloaders syslinux \
        --debian-installer none \
        --iso-application "TwinaOS Installer" \
        --iso-publisher "TwinaOS Project" \
        --iso-volume "TwinaOS-$(date +%Y%m%d)" \
        --memtest none \
        --win32-loader false
    
    success "Live-build configuration created"
}

# Copy installer files
copy_installer() {
    log "Copying installer files..."
    
    # Create necessary directories
    mkdir -p "config/includes.chroot/opt/twinaos"
    mkdir -p "config/includes.chroot/etc/systemd/system"
    mkdir -p "config/includes.chroot/usr/share/plymouth/themes/twinaos"
    mkdir -p "config/includes.chroot/usr/local/bin"
    
    # Copy installer application
    cp -r ../installer/* "config/includes.chroot/opt/twinaos/"
    
    # Copy systemd service
    cp ../systemd/installer.service "config/includes.chroot/etc/systemd/system/"
    
    # Copy Plymouth theme
    cp -r ../splash/* "config/includes.chroot/usr/share/plymouth/themes/twinaos/"
    
    # Copy X session script if it exists
    if [[ -f ../scripts/installer-x-session.sh ]]; then
        cp ../scripts/installer-x-session.sh "config/includes.chroot/usr/local/bin/"
        chmod +x "config/includes.chroot/usr/local/bin/installer-x-session.sh"
    fi
    
    success "Installer files copied"
}

# Create package lists
create_package_lists() {
    log "Creating package lists..."
    
    mkdir -p "config/package-lists"
    
    # Base packages
    cat > "config/package-lists/base.list.chroot" << 'EOF'
# Base system
live-boot
live-config
live-config-systemd

# Network and WiFi
network-manager
wpasupplicant
wireless-tools

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
xserver-xorg-video-all
xserver-xorg-input-all
xinit
openbox
chromium

# Utilities
curl
wget
rsync
sudo
systemd
EOF

    # Create firmware package list (separate to handle non-free)
    cat > "config/package-lists/firmware.list.chroot" << 'EOF'
# Hardware firmware (requires non-free repositories)
firmware-linux-free
firmware-misc-nonfree
firmware-realtek
firmware-iwlwifi
firmware-atheros
intel-microcode
amd64-microcode
EOF

    success "Package lists created"
}

# Create hooks
create_hooks() {
    log "Creating live-build hooks..."
    
    mkdir -p "config/hooks/live"
    
    # Hook to configure bootloader for silent boot
    cat > "config/hooks/live/0005-configure-bootloader.hook.binary" << 'EOF'
#!/bin/bash

# Configure isolinux/syslinux for silent auto-boot
if [ -d binary/isolinux ]; then
    # Set timeout to 0 for immediate boot
    sed -i 's/timeout .*/timeout 0/' binary/isolinux/isolinux.cfg || true
    sed -i 's/prompt .*/prompt 0/' binary/isolinux/isolinux.cfg || true
    
    # Remove menu display
    sed -i '/^ui /d' binary/isolinux/isolinux.cfg || true
    sed -i '/^menu /d' binary/isolinux/isolinux.cfg || true
    
    # Set default label
    sed -i 's/^default .*/default live/' binary/isolinux/isolinux.cfg || true
fi

# Configure syslinux for silent auto-boot
if [ -d binary/syslinux ]; then
    sed -i 's/timeout .*/timeout 0/' binary/syslinux/syslinux.cfg || true
    sed -i 's/prompt .*/prompt 0/' binary/syslinux/syslinux.cfg || true
    sed -i '/^ui /d' binary/syslinux/syslinux.cfg || true
    sed -i '/^menu /d' binary/syslinux/syslinux.cfg || true
    sed -i 's/^default .*/default live/' binary/syslinux/syslinux.cfg || true
fi

# Configure GRUB for silent auto-boot (if using GRUB)
if [ -d binary/boot/grub ]; then
    cat > binary/boot/grub/grub.cfg << 'GRUBEOF'
set default=0
set timeout=0
menuentry "TwinaOS Installer" {
    linux /live/vmlinuz boot=live components quiet splash
    initrd /live/initrd.img
}
GRUBEOF
fi
EOF

    chmod +x "config/hooks/live/0005-configure-bootloader.hook.binary"

    # Hook to setup installer service
    cat > "config/hooks/live/0010-setup-installer.hook.chroot" << 'EOF'
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

# Create bash profile to auto-start X
cat > /home/installer/.bash_profile << 'EOFINNER'
# Auto-start X if on tty1 and X not running
if [[ -z "$DISPLAY" ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOFINNER

# Setup auto-start for installer with proper X session
mkdir -p /home/installer
cat > /home/installer/.xinitrc << 'EOFINNER'
#!/bin/bash
# Start the installer X session

# Set up environment
export DISPLAY=:0
export HOME=/home/installer

# Start window manager
openbox-session &

# Wait for openbox to be ready
sleep 2

# Start the installer browser
chromium --kiosk --no-sandbox --disable-dev-shm-usage --disable-gpu-sandbox http://localhost:5000 &

# Keep X running
wait
EOFINNER

chmod +x /home/installer/.xinitrc

# Setup Openbox autostart
mkdir -p /home/installer/.config/openbox
cat > /home/installer/.config/openbox/autostart << 'EOFINNER'
# Start installer web browser after X is ready
(sleep 3 && chromium --kiosk --no-sandbox --disable-dev-shm-usage http://localhost:5000) &
EOFINNER

# Set proper permissions
chown -R installer:installer /home/installer
chmod 755 /home/installer
chmod 644 /home/installer/.bash_profile
EOF

    chmod +x "config/hooks/live/0010-setup-installer.hook.chroot"
    
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

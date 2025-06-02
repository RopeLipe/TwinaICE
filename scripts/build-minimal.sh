#!/bin/bash
#
# TwinaOS ISO Builder - Minimal Version
# Builds a custom Debian Live Installer ISO without firmware packages
#

set -e

# Configuration
WORK_DIR="$(pwd)/build"
ISO_NAME="twinaos-installer-minimal"
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

# Setup live-build configuration (minimal)
setup_live_config() {
    log "Setting up minimal live-build configuration..."
    
    cd "$WORK_DIR"
    
    # Initialize live-build with main repository only
    lb config \
        --distribution "$DEBIAN_VERSION" \
        --architecture "$ARCH" \
        --archive-areas "main" \
        --binary-images iso-hybrid \
        --bootappend-live "boot=live components quiet splash" \
        --bootloaders syslinux \
        --debian-installer none \
        --iso-application "TwinaOS Installer (Minimal)" \
        --iso-publisher "TwinaOS Project" \
        --iso-volume "TwinaOS-Minimal-$(date +%Y%m%d)" \
        --memtest none \
        --win32-loader false
    
    success "Minimal live-build configuration created"
}

# Copy installer files
copy_installer() {
    log "Copying installer files..."
    
    # Create necessary directories
    mkdir -p "config/includes.chroot/opt/twinaos"
    mkdir -p "config/includes.chroot/etc/systemd/system"
    mkdir -p "config/includes.chroot/usr/share/plymouth/themes/twinaos"
    
    # Copy installer application
    cp -r ../installer/* "config/includes.chroot/opt/twinaos/"
    
    # Copy systemd service
    cp ../systemd/installer.service "config/includes.chroot/etc/systemd/system/"
    
    # Copy Plymouth theme
    cp -r ../splash/* "config/includes.chroot/usr/share/plymouth/themes/twinaos/"
    
    success "Installer files copied"
}

# Create minimal package lists
create_package_lists() {
    log "Creating minimal package lists..."
    
    mkdir -p "config/package-lists"
    
    # Minimal packages only
    cat > "config/package-lists/base.list.chroot" << 'EOF'
# Base system
live-boot
live-config
live-config-systemd

# Network (basic)
network-manager
wpasupplicant

# Python and web server
python3
python3-pip
python3-venv

# Installation tools (essential)
debootstrap
gdisk
parted
e2fsprogs
dosfstools

# Graphics and boot
plymouth
xserver-xorg-core
openbox

# Utilities
curl
wget
sudo
systemd
EOF

    success "Minimal package lists created"
}

# Create simplified hooks
create_hooks() {
    log "Creating simplified hooks..."
    
    mkdir -p "config/hooks/live"
    
    # Bootloader configuration hook
    cat > "config/hooks/live/0005-configure-bootloader.hook.binary" << 'EOF'
#!/bin/bash

# Configure isolinux/syslinux for silent auto-boot
if [ -d binary/isolinux ]; then
    sed -i 's/timeout .*/timeout 0/' binary/isolinux/isolinux.cfg || true
    sed -i 's/prompt .*/prompt 0/' binary/isolinux/isolinux.cfg || true
    sed -i '/^ui /d' binary/isolinux/isolinux.cfg || true
    sed -i '/^menu /d' binary/isolinux/isolinux.cfg || true
    sed -i 's/^default .*/default live/' binary/isolinux/isolinux.cfg || true
fi

if [ -d binary/syslinux ]; then
    sed -i 's/timeout .*/timeout 0/' binary/syslinux/syslinux.cfg || true
    sed -i 's/prompt .*/prompt 0/' binary/syslinux/syslinux.cfg || true
    sed -i '/^ui /d' binary/syslinux/syslinux.cfg || true
    sed -i '/^menu /d' binary/syslinux/syslinux.cfg || true
    sed -i 's/^default .*/default live/' binary/syslinux/syslinux.cfg || true
fi
EOF

    chmod +x "config/hooks/live/0005-configure-bootloader.hook.binary"

    # Simple installer setup hook
    cat > "config/hooks/live/9999-installer-setup.hook.chroot" << 'EOF'
#!/bin/bash

# Install Python packages
pip3 install flask flask-socketio psutil requests

# Create installer user
useradd -m -s /bin/bash -G sudo,netdev installer
echo 'installer:installer' | chpasswd

# Enable auto-login
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOL'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin installer --noclear %I $TERM
EOL

# Setup X initialization
cat > /home/installer/.xinitrc << 'EOL'
#!/bin/bash
exec openbox-session
EOL
chmod +x /home/installer/.xinitrc

# Setup Openbox autostart
mkdir -p /home/installer/.config/openbox
cat > /home/installer/.config/openbox/autostart << 'EOL'
# Wait for network and start browser
(sleep 3 && chromium --kiosk --no-sandbox --disable-dev-shm-usage http://localhost:5000) &
EOL

# Create GUI startup service
cat > /etc/systemd/system/installer-gui.service << 'EOL'
[Unit]
Description=Start X11 for installer
After=multi-user.target

[Service]
Type=simple
User=installer
PAMName=login
TTYPath=/dev/tty1
Environment="HOME=/home/installer"
ExecStart=/usr/bin/startx
Restart=on-failure

[Install]
WantedBy=graphical.target
EOL

# Enable services
systemctl enable installer.service
systemctl enable installer-gui.service

# Set ownership
chown -R installer:installer /home/installer

# Setup Plymouth theme
plymouth-set-default-theme twinaos
update-initramfs -u
EOF

    chmod +x "config/hooks/live/9999-installer-setup.hook.chroot"
    
    success "Simplified hooks created"
}

# Build the ISO
build_iso() {
    log "Building minimal ISO image..."
    
    # Set environment variables for live-build
    export LB_DISTRIBUTION="$DEBIAN_VERSION"
    export LB_ARCHITECTURE="$ARCH"
    
    # Build with verbose output
    sudo lb build 2>&1 | tee build.log
    
    if [[ -f "live-image-$ARCH.hybrid.iso" ]]; then
        # Rename the ISO
        local iso_filename="${ISO_NAME}-$(date +%Y%m%d).iso"
        mv "live-image-$ARCH.hybrid.iso" "../$iso_filename"
        success "ISO built successfully: $iso_filename"
        
        # Generate checksums
        cd ..
        sha256sum "$iso_filename" > "$iso_filename.sha256"
        log "SHA256: $(cat "$iso_filename.sha256")"
        
        # Show file info
        log "ISO size: $(du -h "$iso_filename" | cut -f1)"
        
    else
        error "ISO build failed. Check build.log for details."
    fi
}

# Main build function
main() {
    log "Starting TwinaOS minimal ISO build..."
    
    check_root
    check_dependencies
    clean_build
    setup_live_config
    copy_installer
    create_package_lists
    create_hooks
    build_iso
    
    success "Build completed successfully!"
    echo
    log "Next steps:"
    echo "1. Test the ISO: ./scripts/test-qemu.sh $ISO_NAME-$(date +%Y%m%d).iso"
    echo "2. If successful, try the full build with firmware"
    echo "3. Boot on real hardware to test"
}

# Script help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "TwinaOS Minimal ISO Builder"
    echo
    echo "This script builds a minimal version of TwinaOS without firmware packages"
    echo "to avoid repository issues. Use this if the main build fails."
    echo
    echo "Usage: $0"
    echo
    echo "The minimal build includes:"
    echo "- Basic Debian live system"
    echo "- TwinaOS installer"
    echo "- Essential drivers only"
    echo "- No proprietary firmware"
    echo
    echo "After successful minimal build, you can try the full version."
    echo
    exit 0
fi

# Run main function
main "$@"

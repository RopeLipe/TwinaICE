#!/bin/bash
#
# Setup Build Environment for TwinaOS
# Installs required dependencies and configures the build system
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if running on Debian/Ubuntu
check_os() {
    if ! command -v apt &> /dev/null; then
        error "This script requires a Debian-based system (Debian/Ubuntu)"
    fi
    
    log "Detected Debian-based system"
}

# Update package repository
update_packages() {
    log "Updating package repository..."
    sudo apt update
    success "Package repository updated"
}

# Install build dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    local packages=(
        # Live-build tools
        "live-build"
        "debootstrap"
        "squashfs-tools"
        "xorriso"
        "isolinux"
        "syslinux-utils"
        
        # Development tools
        "build-essential"
        "git"
        "wget"
        "curl"
        "rsync"
        
        # Python and web development
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        
        # Additional tools
        "qemu-system-x86"
        "qemu-utils"
        "parted"
        "gdisk"
        "dosfstools"
        "e2fsprogs"
    )
    
    for package in "${packages[@]}"; do
        log "Installing $package..."
        sudo apt install -y "$package"
    done
    
    success "All dependencies installed"
}

# Install Python packages
install_python_deps() {
    log "Installing Python dependencies..."
    
    pip3 install --user flask flask-socketio psutil requests
    
    success "Python dependencies installed"
}

# Setup live-build configuration directory
setup_live_build() {
    log "Setting up live-build environment..."
    
    # Create live-build cache directory
    sudo mkdir -p /var/cache/live-build
    sudo chown -R $(whoami):$(whoami) /var/cache/live-build
    
    success "Live-build environment configured"
}

# Configure system for building
configure_system() {
    log "Configuring system for ISO building..."
    
    # Add user to required groups
    sudo usermod -a -G kvm,libvirt $(whoami) 2>/dev/null || true
    
    # Configure sudoers for live-build
    echo "$(whoami) ALL=(ALL) NOPASSWD: /usr/sbin/lb, /bin/mount, /bin/umount, /usr/bin/chroot" | sudo tee /etc/sudoers.d/twinaos-build
    
    success "System configured for building"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    local tools=("lb" "debootstrap" "mksquashfs" "xorriso" "python3")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing tools: ${missing[*]}"
    fi
    
    success "All tools verified successfully"
}

# Create workspace
create_workspace() {
    log "Creating workspace directories..."
    
    mkdir -p build
    mkdir -p iso-output
    mkdir -p logs
    
    success "Workspace created"
}

# Main setup function
main() {
    log "Setting up TwinaOS build environment..."
    
    check_os
    update_packages
    install_dependencies
    install_python_deps
    setup_live_build
    configure_system
    verify_installation
    create_workspace
    
    success "Build environment setup completed!"
    echo
    log "You can now run: ./scripts/build-iso.sh"
    warn "You may need to log out and back in for group changes to take effect"
}

# Run main function
main "$@"

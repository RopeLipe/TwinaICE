#!/bin/bash
#
# TwinaOS Development Environment Setup
# Prepares a Debian system for building TwinaOS Live ISO
#

set -e

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

# Check if running on Debian
check_debian() {
    if ! grep -q "Debian" /etc/os-release; then
        error "This script must be run on a Debian system"
    fi
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    if [[ "$version" -lt "11" ]]; then
        warn "Debian 11+ recommended for best compatibility"
    fi
    
    success "Running on Debian $version"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    success "System updated"
}

# Install build dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    local packages=(
        # Live-build and ISO creation
        "live-build"
        "squashfs-tools" 
        "xorriso"
        "isolinux"
        "syslinux-utils"
        
        # Development tools
        "build-essential"
        "git"
        "wget"
        "curl"
        "jq"
        
        # Python development
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        
        # System tools
        "debootstrap"
        "parted"
        "gdisk"
        "dosfstools"
        "e2fsprogs"
        
        # Network tools
        "network-manager"
        "wpasupplicant"
        
        # Testing tools
        "qemu-system-x86"
        "qemu-utils"
        
        # Additional utilities
        "plymouth"
        "plymouth-themes"
    )
    
    sudo apt install -y "${packages[@]}"
    success "Dependencies installed"
}

# Install Python packages
install_python_packages() {
    log "Installing Python packages..."
    
    pip3 install --user --upgrade \
        flask \
        flask-socketio \
        psutil \
        requests \
        pyyaml
    
    success "Python packages installed"
}

# Setup user permissions
setup_permissions() {
    log "Setting up user permissions..."
    
    # Add user to necessary groups
    sudo usermod -a -G sudo,disk,netdev "$USER"
    
    # Create necessary directories
    mkdir -p ~/twinaos-build
    
    success "Permissions configured"
}

# Download and setup additional tools
setup_tools() {
    log "Setting up additional tools..."
    
    # Download latest live-build if needed
    local lb_version=$(lb --version 2>/dev/null | head -1 | awk '{print $2}' || echo "0")
    log "Live-build version: $lb_version"
    
    success "Additional tools configured"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."
    
    local tools=("lb" "mksquashfs" "xorriso" "python3" "qemu-system-x86_64")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing tools: ${missing[*]}"
    fi
    
    success "All tools verified"
}

# Create sample configuration
create_sample_config() {
    log "Creating sample configuration..."
    
    cat > ~/twinaos-build/config.yaml << 'EOF'
# TwinaOS Build Configuration
project:
  name: "TwinaOS"
  version: "1.0.0"
  description: "Tablet-focused Debian-based OS"

build:
  debian_version: "bookworm"
  architecture: "amd64"
  iso_name: "twinaos-installer"
  
installer:
  default_language: "en_US"
  default_timezone: "UTC"
  enable_debug: true
  
features:
  plymouth_theme: true
  auto_login: true
  network_manager: true
  
packages:
  extra:
    - "firefox-esr"
    - "libreoffice"
    - "gimp"
    - "vlc"
EOF
    
    success "Sample configuration created in ~/twinaos-build/config.yaml"
}

# Main execution
main() {
    log "Starting TwinaOS development environment setup..."
    
    check_debian
    update_system
    install_dependencies
    install_python_packages
    setup_permissions
    setup_tools
    verify_installation
    create_sample_config
    
    success "Development environment setup complete!"
    echo
    log "Next steps:"
    echo "1. Clone the TwinaOS repository"
    echo "2. Run ./scripts/build-iso.sh to build the ISO"
    echo "3. Test with ./scripts/test-iso.sh"
    echo
    warn "You may need to log out and back in for group changes to take effect"
}

# Script help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "TwinaOS Development Environment Setup"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "This script prepares a Debian system for TwinaOS development by:"
    echo "- Installing required packages and dependencies"
    echo "- Setting up user permissions and groups"
    echo "- Installing Python packages for the installer"
    echo "- Creating sample configurations"
    echo
    echo "Requirements:"
    echo "- Debian 11+ (Bullseye or newer)"
    echo "- sudo access"
    echo "- Internet connection"
    echo
    exit 0
fi

# Run main function
main "$@"

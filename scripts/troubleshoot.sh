#!/bin/bash
#
# TwinaOS Build Troubleshooter
# Diagnoses and fixes common build issues
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check Debian version and repositories
check_debian_repos() {
    log "Checking Debian version and repositories..."
    
    local version=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log "Debian version: $version"
    
    if [[ "$version" != "12" ]]; then
        warn "Not running Debian 12. Some packages may not be available."
    fi
    
    log "Checking repository configuration..."
    cat /etc/apt/sources.list
    
    if grep -q "non-free" /etc/apt/sources.list; then
        success "Non-free repositories are enabled"
    else
        warn "Non-free repositories not found in sources.list"
        log "To enable non-free repositories, run:"
        echo "sudo sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list"
    fi
}

# Test package availability
test_packages() {
    log "Testing package availability..."
    
    local packages=(
        "live-boot"
        "live-config" 
        "network-manager"
        "python3-flask"
        "debootstrap"
        "plymouth"
        "firmware-linux-free"
        "firmware-misc-nonfree"
        "firmware-iwlwifi"
        "firmware-realtek"
    )
    
    local available=()
    local missing=()
    
    # Update package list
    log "Updating package list..."
    sudo apt update >/dev/null 2>&1
    
    for package in "${packages[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            available+=("$package")
        else
            missing+=("$package")
        fi
    done
    
    log "Available packages (${#available[@]}):"
    printf '  %s\n' "${available[@]}"
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages (${#missing[@]}):"
        printf '  %s\n' "${missing[@]}"
    else
        success "All packages are available"
    fi
}

# Fix repository configuration
fix_repositories() {
    log "Fixing repository configuration..."
    
    # Backup current sources.list
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    
    # Create new sources.list with all components
    cat << 'EOF' | sudo tee /etc/apt/sources.list > /dev/null
# Debian 12 (Bookworm) repositories
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
    
    success "Repository configuration updated"
    
    # Update package list
    log "Updating package list..."
    sudo apt update
    
    success "Package list updated"
}

# Test live-build functionality
test_live_build() {
    log "Testing live-build functionality..."
    
    local test_dir="/tmp/lb-test"
    
    # Clean up any previous test
    sudo rm -rf "$test_dir"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Initialize a minimal live-build configuration
    log "Creating test live-build configuration..."
    lb config \
        --distribution bookworm \
        --architecture amd64 \
        --archive-areas "main" \
        --binary-images iso-hybrid \
        --debian-installer none >/dev/null 2>&1
    
    if [[ -d "config" ]]; then
        success "Live-build configuration test passed"
    else
        error "Live-build configuration test failed"
        return 1
    fi
    
    # Test package list creation
    mkdir -p config/package-lists
    echo "live-boot" > config/package-lists/test.list.chroot
    
    # Clean up
    cd - >/dev/null
    sudo rm -rf "$test_dir"
    
    success "Live-build functionality test completed"
}

# Check build dependencies
check_dependencies() {
    log "Checking build dependencies..."
    
    local deps=(
        "live-build"
        "squashfs-tools"
        "xorriso"
        "isolinux"
        "python3"
        "python3-pip"
        "debootstrap"
    )
    
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep "; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing[*]}"
        log "To install missing dependencies:"
        echo "sudo apt install ${missing[*]}"
        return 1
    else
        success "All dependencies are installed"
    fi
}

# Clean build environment
clean_environment() {
    log "Cleaning build environment..."
    
    local build_dir="$(pwd)/build"
    
    if [[ -d "$build_dir" ]]; then
        sudo rm -rf "$build_dir"
        log "Removed old build directory"
    fi
    
    # Clean apt cache
    sudo apt clean
    log "Cleaned apt cache"
    
    success "Build environment cleaned"
}

# Show system information
show_system_info() {
    log "System Information:"
    echo "  OS: $(lsb_release -d | cut -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Memory: $(free -h | awk '/^Mem:/{print $2}')"
    echo "  Disk space: $(df -h . | awk 'NR==2{print $4}')"
    echo "  Python: $(python3 --version)"
    echo "  Live-build: $(lb --version | head -1 || echo "Not installed")"
}

# Generate build recommendations
generate_recommendations() {
    log "Build Recommendations:"
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    local memory=$(free -m | awk '/^Mem:/{print $2}')
    
    if [[ "$version" != "12" ]]; then
        warn "Upgrade to Debian 12 for best compatibility"
    fi
    
    if [[ $memory -lt 4096 ]]; then
        warn "At least 4GB RAM recommended for building"
    fi
    
    if ! grep -q "non-free" /etc/apt/sources.list; then
        warn "Enable non-free repositories for hardware support"
    fi
    
    log "Recommended build sequence:"
    echo "1. ./scripts/troubleshoot.sh --fix-repos"
    echo "2. ./scripts/setup-dev-env.sh"
    echo "3. ./scripts/build-minimal.sh (test build)"
    echo "4. ./scripts/build-iso.sh (full build)"
}

# Main menu
show_menu() {
    echo "TwinaOS Build Troubleshooter"
    echo
    echo "1. Check system information"
    echo "2. Check repositories"
    echo "3. Test package availability"
    echo "4. Check dependencies"
    echo "5. Test live-build"
    echo "6. Fix repositories"
    echo "7. Clean environment"
    echo "8. Show recommendations"
    echo "9. Run all checks"
    echo "0. Exit"
    echo
    read -p "Select option [0-9]: " choice
    
    case $choice in
        1) show_system_info ;;
        2) check_debian_repos ;;
        3) test_packages ;;
        4) check_dependencies ;;
        5) test_live_build ;;
        6) fix_repositories ;;
        7) clean_environment ;;
        8) generate_recommendations ;;
        9) run_all_checks ;;
        0) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

# Run all checks
run_all_checks() {
    log "Running comprehensive troubleshooting..."
    echo
    
    show_system_info
    echo
    check_debian_repos
    echo
    check_dependencies
    echo
    test_packages
    echo
    test_live_build
    echo
    generate_recommendations
}

# Command line options
case "${1:-}" in
    --fix-repos)
        fix_repositories
        ;;
    --clean)
        clean_environment
        ;;
    --check-all)
        run_all_checks
        ;;
    --help|-h)
        echo "TwinaOS Build Troubleshooter"
        echo
        echo "Usage: $0 [OPTION]"
        echo
        echo "Options:"
        echo "  --fix-repos    Fix repository configuration"
        echo "  --clean        Clean build environment"
        echo "  --check-all    Run all diagnostic checks"
        echo "  --help         Show this help"
        echo
        echo "Interactive mode: $0 (no options)"
        ;;
    "")
        # Interactive mode
        while true; do
            show_menu
            echo
        done
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

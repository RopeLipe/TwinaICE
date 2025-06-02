#!/bin/bash
#
# TwinaOS Quick Test Script
# Tests the generated ISO in QEMU with proper configuration
#

set -e

# Configuration
ISO_FILE="${1:-twinaos-installer.iso}"
VM_NAME="TwinaOS-Test"
VM_MEMORY="2048"
VM_DISK_SIZE="20G"
VM_DISK="twinaos-test.qcow2"

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
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if ISO exists
check_iso() {
    if [[ ! -f "$ISO_FILE" ]]; then
        error "ISO file not found: $ISO_FILE"
    fi
    
    log "Found ISO file: $ISO_FILE ($(du -h "$ISO_FILE" | cut -f1))"
}

# Check QEMU installation
check_qemu() {
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        error "QEMU not found. Install with: sudo apt install qemu-system-x86"
    fi
    
    log "QEMU found: $(qemu-system-x86_64 --version | head -1)"
}

# Create test disk
create_test_disk() {
    if [[ ! -f "$VM_DISK" ]]; then
        log "Creating test disk: $VM_DISK ($VM_DISK_SIZE)"
        qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
        success "Test disk created"
    else
        log "Using existing test disk: $VM_DISK"
    fi
}

# Test in BIOS mode
test_bios() {
    log "Testing in BIOS mode..."
    
    qemu-system-x86_64 \
        -name "$VM_NAME-BIOS" \
        -m "$VM_MEMORY" \
        -smp 2 \
        -cdrom "$ISO_FILE" \
        -hda "$VM_DISK" \
        -boot order=dc \
        -vga virtio \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::8080-:5000 \
        -display gtk,show-cursor=on \
        -monitor stdio \
        "$@"
}

# Test in UEFI mode
test_uefi() {
    log "Testing in UEFI mode..."
    
    # Check for OVMF firmware
    local ovmf_path=""
    local possible_paths=(
        "/usr/share/ovmf/OVMF.fd"
        "/usr/share/qemu/OVMF.fd"
        "/usr/share/edk2-ovmf/OVMF.fd"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            ovmf_path="$path"
            break
        fi
    done
    
    if [[ -z "$ovmf_path" ]]; then
        warn "OVMF firmware not found. Install with: sudo apt install ovmf"
        warn "Falling back to BIOS mode"
        test_bios "$@"
        return
    fi
    
    log "Using OVMF firmware: $ovmf_path"
    
    qemu-system-x86_64 \
        -name "$VM_NAME-UEFI" \
        -m "$VM_MEMORY" \
        -smp 2 \
        -bios "$ovmf_path" \
        -cdrom "$ISO_FILE" \
        -hda "$VM_DISK" \
        -boot order=dc \
        -vga virtio \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::8080-:5000 \
        -display gtk,show-cursor=on \
        -monitor stdio \
        "$@"
}

# Test network connectivity
test_network() {
    log "Testing network connectivity (port forwarding 5000 -> 8080)..."
    log "Once the installer starts, you can access it at: http://localhost:8080"
}

# Cleanup function
cleanup() {
    log "Cleaning up test environment..."
    # Kill any remaining QEMU processes
    pkill -f "$VM_NAME" 2>/dev/null || true
}

# Help function
show_help() {
    echo "TwinaOS ISO Test Script"
    echo
    echo "Usage: $0 [ISO_FILE] [OPTIONS]"
    echo
    echo "Options:"
    echo "  --bios        Test in BIOS mode only"
    echo "  --uefi        Test in UEFI mode only"
    echo "  --vnc         Use VNC display instead of GTK"
    echo "  --memory MB   Set VM memory (default: $VM_MEMORY)"
    echo "  --help        Show this help"
    echo
    echo "Examples:"
    echo "  $0                           # Test default ISO in BIOS mode"
    echo "  $0 my-iso.iso --uefi         # Test specific ISO in UEFI mode"
    echo "  $0 --vnc --memory 4096       # Test with VNC and 4GB RAM"
    echo
    echo "Network:"
    echo "  The installer web interface will be accessible at http://localhost:8080"
    echo "  SSH access (if enabled): ssh -p 2222 installer@localhost"
    echo
}

# Parse arguments
MODE="bios"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --bios)
            MODE="bios"
            shift
            ;;
        --uefi)
            MODE="uefi"
            shift
            ;;
        --vnc)
            EXTRA_ARGS+=("-display" "vnc=:1")
            log "VNC display enabled. Connect to localhost:5901"
            shift
            ;;
        --memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            EXTRA_ARGS+=("$1")
            shift
            ;;
        *)
            if [[ -z "$ISO_FILE" ]]; then
                ISO_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Main execution
main() {
    log "Starting TwinaOS ISO test..."
    
    check_iso
    check_qemu
    create_test_disk
    test_network
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    case "$MODE" in
        "bios")
            test_bios "${EXTRA_ARGS[@]}"
            ;;
        "uefi")
            test_uefi "${EXTRA_ARGS[@]}"
            ;;
        *)
            error "Unknown mode: $MODE"
            ;;
    esac
}

# Run main function
main "$@"

#!/bin/bash
#
# Test TwinaOS ISO in QEMU
# Launches the ISO in a virtual machine for testing
#

set -e

# Configuration
QEMU_MEMORY="2048"
QEMU_DISK_SIZE="20G"
QEMU_DISPLAY="gtk"

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

# Check if ISO file exists
check_iso() {
    local iso_file="$1"
    
    if [[ -z "$iso_file" ]]; then
        error "Usage: $0 <iso-file>"
    fi
    
    if [[ ! -f "$iso_file" ]]; then
        error "ISO file not found: $iso_file"
    fi
    
    log "Found ISO file: $iso_file"
}

# Check QEMU installation
check_qemu() {
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        error "QEMU not found. Install with: sudo apt install qemu-system-x86"
    fi
    
    log "QEMU found"
}

# Create test disk image
create_test_disk() {
    local disk_file="test-disk.qcow2"
    
    if [[ ! -f "$disk_file" ]]; then
        log "Creating test disk image..."
        qemu-img create -f qcow2 "$disk_file" "$QEMU_DISK_SIZE"
        success "Test disk created: $disk_file"
    else
        log "Using existing test disk: $disk_file"
    fi
}

# Launch QEMU
launch_qemu() {
    local iso_file="$1"
    local disk_file="test-disk.qcow2"
    
    log "Launching QEMU with TwinaOS ISO..."
    log "Memory: ${QEMU_MEMORY}MB"
    log "Disk: $disk_file"
    log "Display: $QEMU_DISPLAY"
    
    # QEMU command with optimal settings for testing
    qemu-system-x86_64 \
        -machine type=pc,accel=kvm \
        -cpu host \
        -m "$QEMU_MEMORY" \
        -smp cores=2,threads=1,sockets=1 \
        -cdrom "$iso_file" \
        -drive file="$disk_file",format=qcow2,if=virtio \
        -netdev user,id=net0 \
        -device virtio-net,netdev=net0 \
        -display "$QEMU_DISPLAY" \
        -vga virtio \
        -soundhw hda \
        -usb \
        -device usb-tablet \
        -boot order=dc \
        -enable-kvm \
        "$@"
}

# Main function
main() {
    local iso_file="$1"
    
    log "Starting TwinaOS ISO test..."
    
    check_iso "$iso_file"
    check_qemu
    create_test_disk
    launch_qemu "$iso_file"
    
    success "QEMU session ended"
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <iso-file> [additional-qemu-options]"
    echo
    echo "Examples:"
    echo "  $0 twinaos-installer-20250601.iso"
    echo "  $0 twinaos-installer.iso -vnc :1"
    echo "  $0 twinaos-installer.iso -nographic"
    exit 1
fi

# Run main function
main "$@"

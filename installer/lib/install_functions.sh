#!/bin/bash
#
# Advanced installation library for TwinaOS
# Contains functions for disk partitioning, system installation, and configuration
#

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a /tmp/twinaos-install.log
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a /tmp/twinaos-install.log >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a /tmp/twinaos-install.log
}

# System detection functions
detect_system_type() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

detect_cpu_architecture() {
    uname -m
}

get_total_memory() {
    free -m | awk '/^Mem:/{print $2}'
}

# Disk management functions
list_block_devices() {
    lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT | jq -r '.blockdevices[] | select(.type=="disk") | {name: .name, size: .size, path: ("/dev/" + .name)}'
}

wipe_disk() {
    local disk="$1"
    
    log_info "Wiping disk $disk"
    
    # Unmount any mounted partitions
    for partition in $(lsblk -ln -o NAME "$disk" | tail -n +2); do
        umount "/dev/$partition" 2>/dev/null || true
    done
    
    # Clear partition table and filesystem signatures
    wipefs -a "$disk"
    dd if=/dev/zero of="$disk" bs=512 count=1024
    
    log_success "Disk $disk wiped successfully"
}

create_uefi_partitions() {
    local disk="$1"
    
    log_info "Creating UEFI partition scheme on $disk"
    
    # Create GPT partition table
    parted -s "$disk" mklabel gpt
    
    # Create EFI System Partition (512MB)
    parted -s "$disk" mkpart primary fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    
    # Create root partition (remaining space)
    parted -s "$disk" mkpart primary ext4 513MiB 100%
    
    log_success "UEFI partitions created"
}

create_bios_partitions() {
    local disk="$1"
    
    log_info "Creating BIOS partition scheme on $disk"
    
    # Create MBR partition table
    parted -s "$disk" mklabel msdos
    
    # Create root partition (full disk)
    parted -s "$disk" mkpart primary ext4 1MiB 100%
    parted -s "$disk" set 1 boot on
    
    log_success "BIOS partitions created"
}

format_partitions() {
    local disk="$1"
    local system_type="$2"
    
    log_info "Formatting partitions on $disk"
    
    if [[ "$system_type" == "uefi" ]]; then
        # Format EFI partition
        mkfs.fat -F32 "${disk}1"
        log_success "EFI partition formatted"
        
        # Format root partition
        mkfs.ext4 -F "${disk}2"
        log_success "Root partition formatted"
    else
        # Format root partition
        mkfs.ext4 -F "${disk}1"
        log_success "Root partition formatted"
    fi
}

# Mount functions
mount_target_system() {
    local disk="$1"
    local system_type="$2"
    local target_dir="/mnt/target"
    
    log_info "Mounting target system"
    
    # Create mount point
    mkdir -p "$target_dir"
    
    if [[ "$system_type" == "uefi" ]]; then
        # Mount root partition
        mount "${disk}2" "$target_dir"
        
        # Create and mount EFI partition
        mkdir -p "$target_dir/boot/efi"
        mount "${disk}1" "$target_dir/boot/efi"
    else
        # Mount root partition
        mount "${disk}1" "$target_dir"
    fi
    
    log_success "Target system mounted at $target_dir"
}

unmount_target_system() {
    local target_dir="/mnt/target"
    
    log_info "Unmounting target system"
    
    # Unmount in reverse order
    umount "$target_dir/boot/efi" 2>/dev/null || true
    umount "$target_dir/proc" 2>/dev/null || true
    umount "$target_dir/sys" 2>/dev/null || true
    umount "$target_dir/dev/pts" 2>/dev/null || true
    umount "$target_dir/dev" 2>/dev/null || true
    umount "$target_dir" 2>/dev/null || true
    
    log_success "Target system unmounted"
}

# Base system installation
install_base_system() {
    local target_dir="/mnt/target"
    local suite="bookworm"
    local mirror="http://deb.debian.org/debian"
    
    log_info "Installing base system with debootstrap"
    
    # Install minimal base system
    debootstrap --arch=amd64 --include=systemd,grub-pc-bin,grub-efi-amd64-bin,linux-image-amd64,firmware-linux "$suite" "$target_dir" "$mirror"
    
    log_success "Base system installed"
}

# Chroot preparation
prepare_chroot() {
    local target_dir="/mnt/target"
    
    log_info "Preparing chroot environment"
    
    # Mount proc, sys, dev
    mount --bind /proc "$target_dir/proc"
    mount --bind /sys "$target_dir/sys"
    mount --bind /dev "$target_dir/dev"
    mount --bind /dev/pts "$target_dir/dev/pts"
    
    # Copy resolv.conf for network access
    cp /etc/resolv.conf "$target_dir/etc/resolv.conf"
    
    log_success "Chroot environment prepared"
}

# System configuration
configure_fstab() {
    local disk="$1"
    local system_type="$2"
    local target_dir="/mnt/target"
    
    log_info "Configuring /etc/fstab"
    
    cat > "$target_dir/etc/fstab" << EOF
# TwinaOS fstab
# <file system> <mount point> <type> <options> <dump> <pass>
EOF
    
    if [[ "$system_type" == "uefi" ]]; then
        echo "${disk}2 / ext4 defaults 0 1" >> "$target_dir/etc/fstab"
        echo "${disk}1 /boot/efi vfat defaults 0 2" >> "$target_dir/etc/fstab"
    else
        echo "${disk}1 / ext4 defaults 0 1" >> "$target_dir/etc/fstab"
    fi
    
    log_success "fstab configured"
}

configure_hostname() {
    local hostname="$1"
    local target_dir="/mnt/target"
    
    log_info "Setting hostname to $hostname"
    
    echo "$hostname" > "$target_dir/etc/hostname"
    
    cat > "$target_dir/etc/hosts" << EOF
127.0.0.1	localhost
127.0.1.1	$hostname

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    
    log_success "Hostname configured"
}

configure_locale() {
    local locale="$1"
    local target_dir="/mnt/target"
    
    log_info "Configuring locale: $locale"
    
    # Generate locale
    echo "$locale UTF-8" > "$target_dir/etc/locale.gen"
    chroot "$target_dir" locale-gen
    
    # Set default locale
    echo "LANG=$locale" > "$target_dir/etc/locale.conf"
    
    log_success "Locale configured"
}

configure_timezone() {
    local timezone="$1"
    local target_dir="/mnt/target"
    
    log_info "Setting timezone to $timezone"
    
    chroot "$target_dir" ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    chroot "$target_dir" dpkg-reconfigure -f noninteractive tzdata
    
    log_success "Timezone configured"
}

# User management
create_user_account() {
    local username="$1"
    local password="$2"
    local fullname="$3"
    local target_dir="/mnt/target"
    
    log_info "Creating user account: $username"
    
    # Create user
    chroot "$target_dir" useradd -m -s /bin/bash -c "$fullname" "$username"
    
    # Set password
    echo "$username:$password" | chroot "$target_dir" chpasswd
    
    # Add to sudo group
    chroot "$target_dir" usermod -aG sudo "$username"
    
    log_success "User account created: $username"
}

# Bootloader installation
install_grub_uefi() {
    local disk="$1"
    local target_dir="/mnt/target"
    
    log_info "Installing GRUB for UEFI"
    
    # Install GRUB packages
    chroot "$target_dir" apt update
    chroot "$target_dir" apt install -y grub-efi-amd64 efibootmgr
    
    # Install GRUB to EFI
    chroot "$target_dir" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=TwinaOS
    
    # Generate GRUB configuration
    chroot "$target_dir" update-grub
    
    log_success "GRUB installed for UEFI"
}

install_grub_bios() {
    local disk="$1"
    local target_dir="/mnt/target"
    
    log_info "Installing GRUB for BIOS"
    
    # Install GRUB packages
    chroot "$target_dir" apt update
    chroot "$target_dir" apt install -y grub-pc
    
    # Install GRUB to disk
    chroot "$target_dir" grub-install "$disk"
    
    # Generate GRUB configuration
    chroot "$target_dir" update-grub
    
    log_success "GRUB installed for BIOS"
}

# Network configuration
configure_network() {
    local target_dir="/mnt/target"
    
    log_info "Configuring network with NetworkManager"
    
    # Install NetworkManager
    chroot "$target_dir" apt update
    chroot "$target_dir" apt install -y network-manager wpasupplicant
    
    # Enable NetworkManager
    chroot "$target_dir" systemctl enable NetworkManager
    
    log_success "Network configured"
}

# Package installation
install_essential_packages() {
    local target_dir="/mnt/target"
    
    log_info "Installing essential packages"
    
    local packages=(
        "sudo"
        "openssh-server"
        "curl"
        "wget"
        "git"
        "vim"
        "htop"
        "firefox-esr"
        "libreoffice"
        "file-roller"
        "gnome-terminal"
        "nautilus"
        "network-manager-gnome"
    )
    
    chroot "$target_dir" apt update
    chroot "$target_dir" apt install -y "${packages[@]}"
    
    log_success "Essential packages installed"
}

# Desktop environment
install_desktop_environment() {
    local target_dir="/mnt/target"
    
    log_info "Installing desktop environment"
    
    # Install minimal GNOME
    chroot "$target_dir" apt install -y gnome-core gdm3
    
    # Enable GDM
    chroot "$target_dir" systemctl enable gdm3
    
    log_success "Desktop environment installed"
}

# Cleanup
cleanup_installation() {
    local target_dir="/mnt/target"
    
    log_info "Cleaning up installation"
    
    # Remove package cache
    chroot "$target_dir" apt clean
    chroot "$target_dir" apt autoremove -y
    
    # Remove resolv.conf copy
    rm -f "$target_dir/etc/resolv.conf"
    
    # Clear logs
    find "$target_dir/var/log" -type f -exec truncate -s 0 {} \;
    
    log_success "Installation cleanup completed"
}

# Main installation function
perform_full_installation() {
    local disk="$1"
    local hostname="$2"
    local username="$3"
    local password="$4"
    local fullname="$5"
    local locale="${6:-en_US.UTF-8}"
    local timezone="${7:-UTC}"
    
    local system_type
    system_type=$(detect_system_type)
    
    log_info "Starting full installation on $disk"
    log_info "System type: $system_type"
    
    # Disk preparation
    wipe_disk "$disk"
    
    if [[ "$system_type" == "uefi" ]]; then
        create_uefi_partitions "$disk"
    else
        create_bios_partitions "$disk"
    fi
    
    format_partitions "$disk" "$system_type"
    mount_target_system "$disk" "$system_type"
    
    # System installation
    install_base_system
    prepare_chroot
    
    # Configuration
    configure_fstab "$disk" "$system_type"
    configure_hostname "$hostname"
    configure_locale "$locale"
    configure_timezone "$timezone"
    
    # User setup
    create_user_account "$username" "$password" "$fullname"
    
    # Software installation
    configure_network
    install_essential_packages
    install_desktop_environment
    
    # Bootloader
    if [[ "$system_type" == "uefi" ]]; then
        install_grub_uefi "$disk"
    else
        install_grub_bios "$disk"
    fi
    
    # Cleanup
    cleanup_installation
    unmount_target_system
    
    log_success "Full installation completed successfully"
}

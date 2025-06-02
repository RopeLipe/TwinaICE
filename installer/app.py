#!/usr/bin/env python3
"""
TwinaOS Web Installer
A Flask-based web installer for TwinaOS tablet operating system
"""

import os
import sys
import subprocess
import threading
import time
import json
import psutil
from flask import Flask, render_template, request, jsonify, session
from flask_socketio import SocketIO, emit
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.secret_key = 'twinaos-installer-secret-key'
socketio = SocketIO(app, cors_allowed_origins="*")

# Global installation state
installation_state = {
    'step': 'welcome',
    'progress': 0,
    'status': 'ready',
    'error': None,
    'config': {}
}

class InstallationManager:
    def __init__(self):
        self.config = {}
        self.log_file = '/tmp/twinaos-install.log'
        
    def run_command(self, command, shell=True):
        """Run a command and return the result"""
        try:
            result = subprocess.run(
                command,
                shell=shell,
                capture_output=True,
                text=True,
                timeout=300
            )
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Command timed out"
        except Exception as e:
            return False, "", str(e)
    
    def get_disks(self):
        """Get available disks for installation"""
        try:
            success, output, error = self.run_command("lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT")
            if success:
                data = json.loads(output)
                disks = []
                for device in data.get('blockdevices', []):
                    if device.get('type') == 'disk':
                        disks.append({
                            'name': device['name'],
                            'size': device['size'],
                            'path': f"/dev/{device['name']}"
                        })
                return disks
            return []
        except Exception as e:
            logger.error(f"Error getting disks: {e}")
            return []
    
    def get_wifi_networks(self):
        """Get available WiFi networks"""
        try:
            success, output, error = self.run_command("nmcli -t -f SSID,SIGNAL,SECURITY dev wifi")
            if success:
                networks = []
                for line in output.strip().split('\n'):
                    if line:
                        parts = line.split(':')
                        if len(parts) >= 3:
                            networks.append({
                                'ssid': parts[0],
                                'signal': parts[1],
                                'security': parts[2]
                            })
                return networks
            return []
        except Exception as e:
            logger.error(f"Error getting WiFi networks: {e}")
            return []
    
    def connect_wifi(self, ssid, password=None):
        """Connect to WiFi network"""
        try:
            if password:
                cmd = f"nmcli dev wifi connect '{ssid}' password '{password}'"
            else:
                cmd = f"nmcli dev wifi connect '{ssid}'"
            
            success, output, error = self.run_command(cmd)
            return success, output if success else error
        except Exception as e:
            return False, str(e)
    
    def partition_disk(self, disk_path, mode='auto'):
        """Partition the selected disk"""
        try:
            # Clear existing partitions
            self.run_command(f"wipefs -a {disk_path}")
            
            if mode == 'auto':
                # Create GPT partition table
                self.run_command(f"parted -s {disk_path} mklabel gpt")
                
                # Create EFI system partition (512MB)
                self.run_command(f"parted -s {disk_path} mkpart primary fat32 1MiB 513MiB")
                self.run_command(f"parted -s {disk_path} set 1 esp on")
                
                # Create root partition (remaining space)
                self.run_command(f"parted -s {disk_path} mkpart primary ext4 513MiB 100%")
                
                # Format partitions
                self.run_command(f"mkfs.fat -F32 {disk_path}1")
                self.run_command(f"mkfs.ext4 -F {disk_path}2")
                
                return True, "Disk partitioned successfully"
            else:
                return False, "Manual partitioning not implemented"
                
        except Exception as e:
            return False, str(e)
    
    def install_system(self, target_disk):
        """Install the base system"""
        try:
            # Mount target partitions
            os.makedirs('/mnt/target', exist_ok=True)
            self.run_command(f"mount {target_disk}2 /mnt/target")
            
            os.makedirs('/mnt/target/boot/efi', exist_ok=True)
            self.run_command(f"mount {target_disk}1 /mnt/target/boot/efi")
            
            # Install base system with debootstrap
            self.run_command("debootstrap --arch=amd64 bookworm /mnt/target http://deb.debian.org/debian")
            
            # Configure fstab
            with open('/mnt/target/etc/fstab', 'w') as f:
                f.write(f"{target_disk}2 / ext4 defaults 0 1\n")
                f.write(f"{target_disk}1 /boot/efi vfat defaults 0 2\n")
            
            # Install GRUB
            self.run_command("mount --bind /dev /mnt/target/dev")
            self.run_command("mount --bind /proc /mnt/target/proc")
            self.run_command("mount --bind /sys /mnt/target/sys")
            
            # Install GRUB in chroot
            chroot_cmd = """
            apt update
            apt install -y grub-efi-amd64 linux-image-amd64
            grub-install --target=x86_64-efi --efi-directory=/boot/efi
            update-grub
            """
            
            with open('/mnt/target/install_grub.sh', 'w') as f:
                f.write(chroot_cmd)
            
            self.run_command("chmod +x /mnt/target/install_grub.sh")
            self.run_command("chroot /mnt/target /install_grub.sh")
            
            return True, "System installed successfully"
            
        except Exception as e:
            return False, str(e)
    
    def create_user(self, username, password, fullname=""):
        """Create user account"""
        try:
            # Create user in chroot
            user_cmd = f"""
            useradd -m -s /bin/bash -c "{fullname}" {username}
            echo "{username}:{password}" | chpasswd
            usermod -aG sudo {username}
            """
            
            with open('/mnt/target/create_user.sh', 'w') as f:
                f.write(user_cmd)
            
            self.run_command("chmod +x /mnt/target/create_user.sh")
            self.run_command("chroot /mnt/target /create_user.sh")
            
            return True, "User created successfully"
            
        except Exception as e:
            return False, str(e)
    
    def finalize_installation(self):
        """Finalize the installation"""
        try:
            # Set hostname
            hostname = self.config.get('hostname', 'twinaos')
            with open('/mnt/target/etc/hostname', 'w') as f:
                f.write(hostname)
            
            # Configure timezone
            timezone = self.config.get('timezone', 'UTC')
            self.run_command(f"chroot /mnt/target ln -sf /usr/share/zoneinfo/{timezone} /etc/localtime")
            
            # Configure locale
            locale = self.config.get('locale', 'en_US.UTF-8')
            with open('/mnt/target/etc/locale.gen', 'w') as f:
                f.write(f"{locale} UTF-8\n")
            
            self.run_command("chroot /mnt/target locale-gen")
            
            # Unmount
            self.run_command("umount /mnt/target/boot/efi")
            self.run_command("umount /mnt/target/dev")
            self.run_command("umount /mnt/target/proc")
            self.run_command("umount /mnt/target/sys")
            self.run_command("umount /mnt/target")
            
            return True, "Installation finalized"
            
        except Exception as e:
            return False, str(e)

installer = InstallationManager()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/step/<step>')
def get_step(step):
    """Get step data"""
    data = {'step': step}
    
    if step == 'disk':
        data['disks'] = installer.get_disks()
    elif step == 'network':
        data['networks'] = installer.get_wifi_networks()
    
    return jsonify(data)

@app.route('/api/config', methods=['POST'])
def save_config():
    """Save configuration step"""
    config = request.get_json()
    installer.config.update(config)
    installation_state['config'].update(config)
    return jsonify({'success': True})

@app.route('/api/wifi/connect', methods=['POST'])
def connect_wifi():
    """Connect to WiFi"""
    data = request.get_json()
    ssid = data.get('ssid')
    password = data.get('password')
    
    success, message = installer.connect_wifi(ssid, password)
    return jsonify({'success': success, 'message': message})

@app.route('/api/install/start', methods=['POST'])
def start_installation():
    """Start the installation process"""
    def install_worker():
        global installation_state
        
        try:
            installation_state['status'] = 'installing'
            installation_state['progress'] = 0
            
            # Step 1: Partition disk
            socketio.emit('install_progress', {
                'progress': 10,
                'message': 'Partitioning disk...'
            })
            
            disk = installer.config.get('disk')
            success, message = installer.partition_disk(disk)
            if not success:
                raise Exception(f"Partitioning failed: {message}")
            
            # Step 2: Install base system
            socketio.emit('install_progress', {
                'progress': 30,
                'message': 'Installing base system...'
            })
            
            success, message = installer.install_system(disk)
            if not success:
                raise Exception(f"System installation failed: {message}")
            
            # Step 3: Create user
            socketio.emit('install_progress', {
                'progress': 70,
                'message': 'Creating user account...'
            })
            
            username = installer.config.get('username')
            password = installer.config.get('password')
            fullname = installer.config.get('fullname', '')
            
            success, message = installer.create_user(username, password, fullname)
            if not success:
                raise Exception(f"User creation failed: {message}")
            
            # Step 4: Finalize
            socketio.emit('install_progress', {
                'progress': 90,
                'message': 'Finalizing installation...'
            })
            
            success, message = installer.finalize_installation()
            if not success:
                raise Exception(f"Finalization failed: {message}")
            
            # Complete
            installation_state['status'] = 'completed'
            installation_state['progress'] = 100
            socketio.emit('install_progress', {
                'progress': 100,
                'message': 'Installation completed successfully!'
            })
            
        except Exception as e:
            installation_state['status'] = 'error'
            installation_state['error'] = str(e)
            socketio.emit('install_error', {'error': str(e)})
    
    # Start installation in background thread
    thread = threading.Thread(target=install_worker)
    thread.daemon = True
    thread.start()
    
    return jsonify({'success': True, 'message': 'Installation started'})

@app.route('/api/reboot', methods=['POST'])
def reboot_system():
    """Reboot the system"""
    def delayed_reboot():
        time.sleep(3)
        subprocess.run(['reboot'], check=False)
    
    thread = threading.Thread(target=delayed_reboot)
    thread.daemon = True
    thread.start()
    
    return jsonify({'success': True, 'message': 'Rebooting...'})

@socketio.on('connect')
def handle_connect():
    emit('status', installation_state)

if __name__ == '__main__':
    # Run the Flask app
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)

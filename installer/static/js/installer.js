// TwinaOS Installer JavaScript

class TwinaOSInstaller {
    constructor() {
        this.currentStep = 0;
        this.steps = [
            'welcome', 'language', 'keyboard', 'timezone', 
            'network', 'disk', 'user', 'summary', 'progress', 'complete'
        ];
        this.config = {};
        this.socket = null;
        this.debugMode = false;
        
        this.init();
    }
    
    init() {
        this.initializeElements();
        this.setupEventListeners();
        this.initializeSocket();
        this.loadData();
        this.startTimeClock();
        this.checkDebugHotkey();
    }
    
    initializeElements() {
        this.stepElements = this.steps.map(step => document.getElementById(`step-${step}`));
        this.currentStepElement = document.getElementById('current-step');
        this.stepCounterElement = document.getElementById('step-counter');
        this.navBackButton = document.getElementById('nav-back');
        this.navNextButton = document.getElementById('nav-next');
        this.loadingOverlay = document.getElementById('loading-overlay');
    }
    
    setupEventListeners() {
        // Navigation
        this.navBackButton.addEventListener('click', () => this.previousStep());
        this.navNextButton.addEventListener('click', () => this.nextStep());
        
        // Language selection
        document.querySelectorAll('.language-item').forEach(item => {
            item.addEventListener('click', () => this.selectLanguage(item));
        });
        
        // Keyboard selection
        this.setupKeyboardSelection();
        
        // Timezone selection
        this.setupTimezoneSelection();
        
        // Network tabs
        document.querySelectorAll('.tab-button').forEach(button => {
            button.addEventListener('click', () => this.switchNetworkTab(button));
        });
        
        // WiFi refresh
        document.getElementById('wifi-refresh').addEventListener('click', () => this.refreshWiFiNetworks());
        
        // Disk selection
        this.setupDiskSelection();
        
        // User form
        this.setupUserForm();
        
        // Installation
        document.getElementById('reboot-now').addEventListener('click', () => this.rebootSystem());
        document.getElementById('reboot-later').addEventListener('click', () => this.closeInstaller());
        
        // Progress details
        document.getElementById('show-details').addEventListener('click', () => this.toggleInstallationDetails());
    }
    
    initializeSocket() {
        this.socket = io();
        
        this.socket.on('install_progress', (data) => {
            this.updateInstallationProgress(data);
        });
        
        this.socket.on('install_error', (data) => {
            this.showInstallationError(data.error);
        });
        
        this.socket.on('status', (data) => {
            console.log('Installer status:', data);
        });
    }
    
    async loadData() {
        // Load keyboard layouts
        this.populateKeyboardLayouts();
        
        // Load timezones
        this.populateTimezones();
        
        // Load initial data for current step
        await this.loadStepData();
    }
    
    async loadStepData() {
        const currentStepName = this.steps[this.currentStep];
        
        try {
            const response = await fetch(`/api/step/${currentStepName}`);
            const data = await response.json();
            
            if (currentStepName === 'disk') {
                this.populateDisks(data.disks || []);
            } else if (currentStepName === 'network') {
                this.populateWiFiNetworks(data.networks || []);
            }
        } catch (error) {
            console.error('Error loading step data:', error);
        }
    }
    
    // Step Navigation
    showStep(stepIndex) {
        // Hide all steps
        this.stepElements.forEach(element => {
            if (element) element.classList.remove('active');
        });
        
        // Show current step
        if (this.stepElements[stepIndex]) {
            this.stepElements[stepIndex].classList.add('active');
        }
        
        // Update step indicator
        this.currentStepElement.textContent = this.steps[stepIndex].charAt(0).toUpperCase() + 
                                              this.steps[stepIndex].slice(1);
        this.stepCounterElement.textContent = `${stepIndex + 1} / ${this.steps.length}`;
        
        // Update navigation buttons
        this.navBackButton.disabled = stepIndex === 0;
        
        if (stepIndex === this.steps.length - 1) {
            this.navNextButton.style.display = 'none';
        } else {
            this.navNextButton.style.display = 'flex';
            this.navNextButton.textContent = stepIndex === this.steps.length - 2 ? 'Install' : 'Next';
        }
        
        // Load step-specific data
        this.loadStepData();
    }
    
    async nextStep() {
        if (!this.validateCurrentStep()) {
            return;
        }
        
        await this.saveCurrentStepData();
        
        if (this.currentStep < this.steps.length - 1) {
            // Special handling for installation step
            if (this.currentStep === this.steps.indexOf('summary')) {
                this.startInstallation();
            }
            
            this.currentStep++;
            this.showStep(this.currentStep);
        }
    }
    
    previousStep() {
        if (this.currentStep > 0) {
            this.currentStep--;
            this.showStep(this.currentStep);
        }
    }
    
    validateCurrentStep() {
        const stepName = this.steps[this.currentStep];
        
        switch (stepName) {
            case 'language':
                return document.querySelector('.language-item.selected') !== null;
            case 'keyboard':
                return document.querySelector('.keyboard-item.selected') !== null;
            case 'timezone':
                return document.querySelector('.timezone-item.selected') !== null;
            case 'disk':
                return document.querySelector('.disk-item.selected') !== null;
            case 'user':
                return this.validateUserForm();
            default:
                return true;
        }
    }
    
    async saveCurrentStepData() {
        const stepName = this.steps[this.currentStep];
        const data = {};
        
        switch (stepName) {
            case 'language':
                const selectedLang = document.querySelector('.language-item.selected');
                if (selectedLang) {
                    data.language = selectedLang.dataset.lang;
                    data.languageName = selectedLang.dataset.name;
                }
                break;
                
            case 'keyboard':
                const selectedKeyboard = document.querySelector('.keyboard-item.selected');
                if (selectedKeyboard) {
                    data.keyboard = selectedKeyboard.dataset.layout;
                    data.keyboardName = selectedKeyboard.textContent.trim();
                }
                break;
                
            case 'timezone':
                const selectedTimezone = document.querySelector('.timezone-item.selected');
                if (selectedTimezone) {
                    data.timezone = selectedTimezone.dataset.timezone;
                }
                break;
                
            case 'disk':
                const selectedDisk = document.querySelector('.disk-item.selected');
                if (selectedDisk) {
                    data.disk = selectedDisk.dataset.path;
                    data.diskName = selectedDisk.querySelector('.disk-details h4').textContent;
                }
                
                const partitionMode = document.querySelector('input[name="partition-mode"]:checked');
                if (partitionMode) {
                    data.partitionMode = partitionMode.value;
                }
                break;
                
            case 'user':
                data.fullname = document.getElementById('full-name').value;
                data.username = document.getElementById('username').value;
                data.password = document.getElementById('password').value;
                data.hostname = document.getElementById('hostname').value;
                break;
        }
        
        if (Object.keys(data).length > 0) {
            this.config = { ...this.config, ...data };
            
            try {
                await fetch('/api/config', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });
            } catch (error) {
                console.error('Error saving config:', error);
            }
        }
        
        this.updateSummary();
    }
    
    // Language Selection
    selectLanguage(item) {
        document.querySelectorAll('.language-item').forEach(el => el.classList.remove('selected'));
        item.classList.add('selected');
    }
    
    // Keyboard Layout
    setupKeyboardSelection() {
        const searchInput = document.getElementById('keyboard-search');
        searchInput.addEventListener('input', () => this.filterKeyboardLayouts());
        
        // Test input
        document.getElementById('keyboard-test-input').addEventListener('keyup', (e) => {
            // Could implement keyboard layout testing here
        });
    }
    
    populateKeyboardLayouts() {
        const layouts = [
            { code: 'us', name: 'US - English (US)' },
            { code: 'gb', name: 'GB - English (UK)' },
            { code: 'de', name: 'DE - German' },
            { code: 'fr', name: 'FR - French' },
            { code: 'es', name: 'ES - Spanish' },
            { code: 'it', name: 'IT - Italian' },
            { code: 'pt', name: 'PT - Portuguese' },
            { code: 'ru', name: 'RU - Russian' },
            { code: 'jp', name: 'JP - Japanese' },
            { code: 'kr', name: 'KR - Korean' }
        ];
        
        const container = document.getElementById('keyboard-list');
        container.innerHTML = layouts.map(layout => `
            <div class="keyboard-item" data-layout="${layout.code}" onclick="selectKeyboard(this)">
                <strong>${layout.code.toUpperCase()}</strong>
                <div>${layout.name}</div>
            </div>
        `).join('');
    }
    
    filterKeyboardLayouts() {
        const search = document.getElementById('keyboard-search').value.toLowerCase();
        const items = document.querySelectorAll('.keyboard-item');
        
        items.forEach(item => {
            const text = item.textContent.toLowerCase();
            item.style.display = text.includes(search) ? 'block' : 'none';
        });
    }
    
    // Timezone
    setupTimezoneSelection() {
        const searchInput = document.getElementById('timezone-search');
        searchInput.addEventListener('input', () => this.filterTimezones());
    }
    
    populateTimezones() {
        const timezones = [
            'UTC',
            'America/New_York',
            'America/Chicago', 
            'America/Denver',
            'America/Los_Angeles',
            'Europe/London',
            'Europe/Paris',
            'Europe/Berlin',
            'Europe/Rome',
            'Europe/Madrid',
            'Asia/Tokyo',
            'Asia/Seoul',
            'Asia/Shanghai',
            'Asia/Kolkata',
            'Australia/Sydney'
        ];
        
        const container = document.getElementById('timezone-list');
        container.innerHTML = timezones.map(tz => `
            <div class="timezone-item" data-timezone="${tz}" onclick="selectTimezone(this)">
                ${tz.replace('_', ' ')}
            </div>
        `).join('');
    }
    
    filterTimezones() {
        const search = document.getElementById('timezone-search').value.toLowerCase();
        const items = document.querySelectorAll('.timezone-item');
        
        items.forEach(item => {
            const text = item.textContent.toLowerCase();
            item.style.display = text.includes(search) ? 'block' : 'none';
        });
    }
    
    startTimeClock() {
        const updateTime = () => {
            const now = new Date();
            const timeString = now.toLocaleTimeString([], { 
                hour: '2-digit', 
                minute: '2-digit',
                second: '2-digit'
            });
            
            const timeElement = document.getElementById('current-time-display');
            if (timeElement) {
                timeElement.textContent = timeString;
            }
        };
        
        updateTime();
        setInterval(updateTime, 1000);
    }
    
    // Network
    switchNetworkTab(button) {
        document.querySelectorAll('.tab-button').forEach(btn => btn.classList.remove('active'));
        document.querySelectorAll('.network-tab').forEach(tab => tab.classList.remove('active'));
        
        button.classList.add('active');
        document.getElementById(`${button.dataset.tab}-tab`).classList.add('active');
    }
    
    async refreshWiFiNetworks() {
        this.showLoading();
        
        try {
            const response = await fetch('/api/step/network');
            const data = await response.json();
            this.populateWiFiNetworks(data.networks || []);
        } catch (error) {
            console.error('Error refreshing WiFi networks:', error);
        } finally {
            this.hideLoading();
        }
    }
    
    populateWiFiNetworks(networks) {
        const container = document.getElementById('wifi-networks');
        
        if (networks.length === 0) {
            container.innerHTML = `
                <div class="wifi-network">
                    <div class="wifi-info">
                        <i class="fas fa-wifi wifi-icon"></i>
                        <div class="wifi-details">
                            <h4>No networks found</h4>
                            <p>Make sure WiFi is enabled and try refreshing</p>
                        </div>
                    </div>
                </div>
            `;
            return;
        }
        
        container.innerHTML = networks.map(network => `
            <div class="wifi-network" onclick="connectToWiFi('${network.ssid}', '${network.security}')">
                <div class="wifi-info">
                    <i class="fas fa-wifi wifi-icon"></i>
                    <div class="wifi-details">
                        <h4>${network.ssid}</h4>
                        <p>${network.security || 'Open'}</p>
                    </div>
                </div>
                <div class="signal-strength">
                    <i class="fas fa-signal"></i>
                    <span>${network.signal}%</span>
                </div>
            </div>
        `).join('');
    }
    
    // Disk Selection
    setupDiskSelection() {
        // Disk selection is handled by onclick in HTML
    }
    
    populateDisks(disks) {
        const container = document.getElementById('disk-list');
        
        if (disks.length === 0) {
            container.innerHTML = `
                <div class="disk-item">
                    <i class="fas fa-exclamation-triangle disk-icon"></i>
                    <div class="disk-details">
                        <h4>No disks found</h4>
                        <p>No suitable installation targets were detected</p>
                    </div>
                </div>
            `;
            return;
        }
        
        container.innerHTML = disks.map(disk => `
            <div class="disk-item" data-path="${disk.path}" onclick="selectDisk(this)">
                <i class="fas fa-hdd disk-icon"></i>
                <div class="disk-details">
                    <h4>${disk.name}</h4>
                    <p>Size: ${disk.size} • Path: ${disk.path}</p>
                </div>
            </div>
        `).join('');
    }
    
    // User Form
    setupUserForm() {
        const usernameInput = document.getElementById('username');
        const passwordInput = document.getElementById('password');
        const passwordConfirmInput = document.getElementById('password-confirm');
        
        usernameInput.addEventListener('input', () => this.validateUsername());
        passwordInput.addEventListener('input', () => this.validatePassword());
        passwordConfirmInput.addEventListener('input', () => this.validatePasswordConfirm());
        
        // Auto-generate username from full name
        document.getElementById('full-name').addEventListener('input', (e) => {
            if (!usernameInput.value) {
                const fullName = e.target.value.toLowerCase().replace(/[^a-z ]/g, '');
                const username = fullName.split(' ')[0];
                usernameInput.value = username;
                this.validateUsername();
            }
        });
    }
    
    validateUsername() {
        const input = document.getElementById('username');
        const value = input.value;
        const isValid = /^[a-z][a-z0-9]*$/.test(value) && value.length >= 3;
        
        input.style.borderColor = isValid ? 'var(--success-color)' : 'var(--error-color)';
        return isValid;
    }
    
    validatePassword() {
        const password = document.getElementById('password').value;
        const strengthFill = document.getElementById('strength-fill');
        const strengthText = document.getElementById('strength-text');
        
        let strength = 0;
        let strengthLabel = 'Weak';
        
        if (password.length >= 8) strength += 25;
        if (/[a-z]/.test(password)) strength += 25;
        if (/[A-Z]/.test(password)) strength += 25; 
        if (/[0-9]/.test(password)) strength += 25;
        if (/[^A-Za-z0-9]/.test(password)) strength += 25;
        
        if (strength >= 100) strengthLabel = 'Very Strong';
        else if (strength >= 75) strengthLabel = 'Strong';
        else if (strength >= 50) strengthLabel = 'Good';
        else if (strength >= 25) strengthLabel = 'Fair';
        
        strengthFill.style.width = `${Math.min(strength, 100)}%`;
        strengthFill.className = `strength-fill ${strengthLabel.toLowerCase().replace(' ', '')}`;
        strengthText.textContent = password ? `Password strength: ${strengthLabel}` : 'Enter a password';
        
        this.validatePasswordConfirm();
        
        return strength >= 50;
    }
    
    validatePasswordConfirm() {
        const password = document.getElementById('password').value;
        const confirm = document.getElementById('password-confirm').value;
        const confirmInput = document.getElementById('password-confirm');
        
        if (!confirm) {
            confirmInput.style.borderColor = '';
            return false;
        }
        
        const isValid = password === confirm;
        confirmInput.style.borderColor = isValid ? 'var(--success-color)' : 'var(--error-color)';
        return isValid;
    }
    
    validateUserForm() {
        const fullName = document.getElementById('full-name').value.trim();
        const username = document.getElementById('username').value.trim();
        const password = document.getElementById('password').value;
        const hostname = document.getElementById('hostname').value.trim();
        
        return fullName && 
               this.validateUsername() && 
               this.validatePassword() && 
               this.validatePasswordConfirm() && 
               hostname;
    }
    
    // Summary
    updateSummary() {
        // Update summary with current configuration
        const summaryElements = {
            'summary-language': this.config.languageName || 'English',
            'summary-keyboard': this.config.keyboardName || 'US',
            'summary-timezone': this.config.timezone || 'UTC',
            'summary-network': 'WiFi configured', // TODO: Update based on actual network state
            'summary-disk': this.config.diskName || 'None selected',
            'summary-partitioning': this.config.partitionMode || 'Automatic',
            'summary-fullname': this.config.fullname || '-',
            'summary-username': this.config.username || '-',
            'summary-hostname': this.config.hostname || 'twinaos'
        };
        
        Object.entries(summaryElements).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = value;
        });
    }
    
    // Installation
    async startInstallation() {
        this.currentStep = this.steps.indexOf('progress');
        this.showStep(this.currentStep);
        
        try {
            const response = await fetch('/api/install/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(this.config)
            });
            
            if (!response.ok) {
                throw new Error('Failed to start installation');
            }
        } catch (error) {
            this.showInstallationError(error.message);
        }
    }
    
    updateInstallationProgress(data) {
        const { progress, message } = data;
        
        // Update progress bar
        document.getElementById('progress-fill').style.width = `${progress}%`;
        document.getElementById('progress-percentage').textContent = `${progress}%`;
        document.getElementById('progress-message').textContent = message;
        
        // Update progress ring
        const circle = document.querySelector('.progress-ring-circle');
        const radius = circle.r.baseVal.value;
        const circumference = radius * 2 * Math.PI;
        const offset = circumference - (progress / 100) * circumference;
        
        circle.style.strokeDasharray = `${circumference} ${circumference}`;
        circle.style.strokeDashoffset = offset;
        
        // Update installation steps
        this.updateInstallationSteps(progress);
        
        if (progress >= 100) {
            setTimeout(() => {
                this.currentStep = this.steps.indexOf('complete');
                this.showStep(this.currentStep);
            }, 2000);
        }
    }
    
    updateInstallationSteps(progress) {
        const steps = [
            { id: 'step-partition', threshold: 10 },
            { id: 'step-system', threshold: 30 },
            { id: 'step-user-create', threshold: 70 },
            { id: 'step-finalize', threshold: 90 }
        ];
        
        steps.forEach(step => {
            const element = document.getElementById(step.id);
            if (progress >= step.threshold) {
                element.classList.add('completed');
                element.classList.remove('active');
                element.querySelector('i').className = 'fas fa-check-circle';
            } else if (progress >= step.threshold - 20) {
                element.classList.add('active');
                element.querySelector('i').className = 'fas fa-circle-notch fa-spin';
            }
        });
    }
    
    showInstallationError(error) {
        alert(`Installation Error: ${error}`);
        // Could implement better error handling here
    }
    
    toggleInstallationDetails() {
        const log = document.getElementById('install-log');
        const button = document.getElementById('show-details');
        
        log.classList.toggle('show');
        button.innerHTML = log.classList.contains('show') ? 
            '<i class="fas fa-chevron-up"></i> Hide Details' :
            '<i class="fas fa-chevron-down"></i> Show Details';
    }
    
    // System Actions
    async rebootSystem() {
        try {
            await fetch('/api/reboot', { method: 'POST' });
        } catch (error) {
            console.error('Error rebooting:', error);
        }
    }
    
    closeInstaller() {
        // Could implement graceful shutdown
        window.close();
    }
    
    // Utility Functions
    showLoading() {
        this.loadingOverlay.classList.add('show');
    }
    
    hideLoading() {
        this.loadingOverlay.classList.remove('show');
    }
    
    // Debug Mode
    checkDebugHotkey() {
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.altKey && e.key === 'd') {
                e.preventDefault();
                this.toggleDebug();
            }
        });
    }
    
    toggleDebug() {
        this.debugMode = !this.debugMode;
        const panel = document.getElementById('debug-panel');
        panel.classList.toggle('show');
        
        if (this.debugMode) {
            this.updateDebugInfo();
        }
    }
    
    updateDebugInfo() {
        // Update debug panel with system information
        document.getElementById('debug-system').innerHTML = `
            <pre>Current Step: ${this.steps[this.currentStep]}
Config: ${JSON.stringify(this.config, null, 2)}</pre>
        `;
    }
}

// Global functions for onclick handlers
function selectKeyboard(element) {
    document.querySelectorAll('.keyboard-item').forEach(el => el.classList.remove('selected'));
    element.classList.add('selected');
}

function selectTimezone(element) {
    document.querySelectorAll('.timezone-item').forEach(el => el.classList.remove('selected'));
    element.classList.add('selected');
    
    document.getElementById('selected-timezone').textContent = element.dataset.timezone;
}

function selectDisk(element) {
    document.querySelectorAll('.disk-item').forEach(el => el.classList.remove('selected'));
    element.classList.add('selected');
}

function connectToWiFi(ssid, security) {
    if (security && security !== 'Open') {
        showWiFiModal(ssid);
    } else {
        // Connect to open network
        installer.connectToOpenWiFi(ssid);
    }
}

function showWiFiModal(ssid) {
    document.getElementById('wifi-modal-ssid').textContent = ssid;
    document.getElementById('wifi-modal').classList.add('show');
}

function closeWifiModal() {
    document.getElementById('wifi-modal').classList.remove('show');
    document.getElementById('wifi-password').value = '';
}

async function connectWifi() {
    const ssid = document.getElementById('wifi-modal-ssid').textContent;
    const password = document.getElementById('wifi-password').value;
    
    try {
        const response = await fetch('/api/wifi/connect', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ssid, password })
        });
        
        const result = await response.json();
        
        if (result.success) {
            closeWifiModal();
            // Update network status
        } else {
            alert(`Connection failed: ${result.message}`);
        }
    } catch (error) {
        alert(`Connection error: ${error.message}`);
    }
}

function togglePassword(inputId) {
    const input = document.getElementById(inputId);
    const button = input.nextElementSibling;
    const icon = button.querySelector('i');
    
    if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'fas fa-eye-slash';
    } else {
        input.type = 'password';
        icon.className = 'fas fa-eye';
    }
}

function openTerminal() {
    // Could implement terminal access for debug mode
    alert('Terminal access would open here in debug mode');
}

function toggleDebug() {
    installer.toggleDebug();
}

// Initialize installer when page loads
let installer;
document.addEventListener('DOMContentLoaded', () => {
    installer = new TwinaOSInstaller();
});

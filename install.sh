#!/bin/bash

# Cloud-Init VM Setup Installer
# This script installs dependencies and sets up the cloud-init VM environment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        log_info "Please run as a regular user with sudo privileges"
        exit 1
    fi
}

# Check if user has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges"
        log_info "Please make sure you can run sudo commands"
        exit 1
    fi
}

# Check system requirements
check_system() {
    log_info "Checking system requirements..."
    
    # Check Linux distribution
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine Linux distribution"
        exit 1
    fi
    
    source /etc/os-release
    log_info "Detected system: $PRETTY_NAME"
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        log_warning "This script is designed for x86_64 architecture. Current: $ARCH"
    fi
    
    # Check virtualization support
    if ! grep -E '(vmx|svm)' /proc/cpuinfo > /dev/null; then
        log_warning "Hardware virtualization support not detected"
        log_warning "VMs may not perform optimally"
    fi
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update package list
    sudo apt-get update -y
    
    # Install required packages
    local packages=(
        "qemu-kvm"
        "qemu-utils" 
        "libvirt-daemon-system"
        "libvirt-clients"
        "bridge-utils"
        "virt-manager"
        "virtinst"
        "genisoimage"
        "wget"
        "curl"
        "make"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            sudo apt-get install -y "$package"
        else
            log_success "$package is already installed"
        fi
    done
}

# Setup libvirt
setup_libvirt() {
    log_info "Setting up libvirt..."
    
    # Add user to libvirt group
    sudo usermod -a -G libvirt "$USER"
    
    # Start and enable libvirt service
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    # Check if default network exists
    if ! sudo virsh net-list --all | grep -q "default"; then
        log_info "Creating default libvirt network..."
        
        # Create default network XML configuration
        cat > /tmp/default-network.xml << EOF
<network>
  <name>default</name>
  <uuid>9a05da11-e96b-47f3-8253-a3a482e445f5</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:0a:cd:21'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
        
        if sudo virsh net-define /tmp/default-network.xml; then
            log_success "Default network created successfully"
        else
            log_warning "Failed to create default network, but continuing..."
        fi
        rm -f /tmp/default-network.xml
    fi
    
    # Start default network
    if ! sudo virsh net-list | grep -q "default.*active"; then
        log_info "Starting default libvirt network..."
        if sudo virsh net-start default; then
            sudo virsh net-autostart default
            log_success "Default network started and enabled"
        else
            log_warning "Failed to start default network"
            log_warning "You may need to configure networking manually"
        fi
    fi
    
    log_success "Libvirt setup complete"
}

# Validate configuration files
validate_config() {
    log_info "Validating configuration files..."
    
    local required_files=("user-data" "meta-data")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            log_error "Required file missing: $file"
            exit 1
        else
            log_success "Found: $file"
        fi
    done
    
    # Check if SSH key is set in user-data
    if grep -q "ssh-rsa" "$SCRIPT_DIR/user-data" || grep -q "ssh-ed25519" "$SCRIPT_DIR/user-data"; then
        log_success "SSH key found in user-data"
    else
        log_warning "No SSH key found in user-data"
        log_warning "You may want to add your SSH public key for access"
    fi
    
    # Check if init.yaml exists and validate it
    if [[ -f "$SCRIPT_DIR/init.yaml" ]]; then
        log_success "Found: init.yaml (extended configuration)"
        
        # Check for SSH key in init.yaml as well
        if grep -q "ssh-authorized-keys" "$SCRIPT_DIR/init.yaml"; then
            log_success "SSH keys configured in init.yaml"
        fi
    fi
}

# Check required tools
check_tools() {
    log_info "Checking required tools..."
    
    local tools=("qemu-img" "virt-install" "genisoimage" "virsh" "wget")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            log_success "$tool is available"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please run the installer again to install dependencies"
        exit 1
    fi
}

# Setup SSH key helper
setup_ssh_key() {
    log_info "SSH Key Setup Helper"
    
    if [[ ! -f ~/.ssh/id_rsa.pub ]] && [[ ! -f ~/.ssh/id_ed25519.pub ]]; then
        log_warning "No SSH public key found"
        read -p "Would you like to generate an SSH key pair? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f ~/.ssh/id_ed25519
            log_success "SSH key pair generated"
        fi
    fi
    
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
        local pubkey=$(cat ~/.ssh/id_ed25519.pub)
        log_info "Your SSH public key:"
        echo "$pubkey"
        
        read -p "Would you like to add this key to user-data automatically? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup original file
            cp "$SCRIPT_DIR/user-data" "$SCRIPT_DIR/user-data.backup"
            
            # Replace placeholder or add key
            if grep -q "ssh-rsa" "$SCRIPT_DIR/user-data"; then
                sed -i "s|ssh-rsa.*|$pubkey|" "$SCRIPT_DIR/user-data"
            else
                sed -i "/ssh_authorized_keys:/a\      - $pubkey" "$SCRIPT_DIR/user-data"
            fi
            log_success "SSH key added to user-data"
        fi
    fi
}

# Main installation function
main() {
    log_info "Cloud-Init VM Setup Installer"
    log_info "=============================="
    
    check_root
    check_sudo
    check_system
    
    read -p "Do you want to install system dependencies? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_dependencies
        setup_libvirt
        
        log_warning "You need to log out and log back in for group membership to take effect"
        log_info "Or you can run: newgrp libvirt"
    fi
    
    check_tools
    validate_config
    
    read -p "Do you want to setup SSH keys? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_ssh_key
    fi
    
    log_success "Installation complete!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review and customize user-data and meta-data files"
    log_info "2. Run 'make download' to get the Ubuntu cloud image"
    log_info "3. Run 'make vm_image' to create the VM disk"
    log_info "4. Run 'make iso' to create the cloud-init ISO"
    log_info "5. Run 'make create_vm' to create and start the VM"
    log_info ""
    log_info "Use 'make clean' to remove the VM when done"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Cloud-Init VM Setup Installer"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --check        Only check system requirements"
        echo "  --deps         Only install dependencies"
        echo ""
        echo "This script will:"
        echo "  - Install required virtualization packages"
        echo "  - Setup libvirt and KVM"
        echo "  - Validate cloud-init configuration"
        echo "  - Help setup SSH keys"
        exit 0
        ;;
    --check)
        check_system
        check_tools
        validate_config
        exit 0
        ;;
    --deps)
        check_root
        check_sudo
        install_dependencies
        setup_libvirt
        exit 0
        ;;
    *)
        main
        ;;
esac
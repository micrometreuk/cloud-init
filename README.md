# Cloud-Init VM Setup

This project provides an automated way to create and configure virtual machines using cloud-init on Ubuntu. It sets up VMs with predefined configurations including users, SSH keys, Docker, Kubernetes (microk8s), and other development tools.

## Quick Start

1. **Install dependencies and setup environment:**
   ```bash
   ./install.sh
   ```

2. **Create and start a VM:**
   ```bash
   make create_vm
   ```

3. **Check VM status:**
   ```bash
   make status
   ```

## Installation

### Automatic Installation (Recommended)

Run the installer script which will handle all dependencies:

```bash
./install.sh
```

The installer will:
- Check system requirements
- Install virtualization packages (QEMU, libvirt, virt-install)
- Setup libvirt and KVM
- Configure user permissions
- Validate cloud-init configuration files
- Help setup SSH keys

### Manual Installation

If you prefer to install dependencies manually:

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm qemu-utils libvirt-daemon-system \
    libvirt-clients bridge-utils virt-manager virt-install \
    genisoimage wget curl make

# Add user to libvirt group
sudo usermod -a -G libvirt $USER

# Start libvirt service
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# You may need to log out and back in for group membership to take effect
```

## Configuration Files

### user-data
Basic cloud-init configuration with user setup and SSH keys. This is used for simple VM setups.

### init.yaml
Extended cloud-init configuration that includes:
- User management with sudo privileges
- Docker installation and setup
- Kubernetes (microk8s) installation
- Various development tools
- Container deployments

### meta-data
VM metadata including instance ID and hostname.

### network-config
Network configuration for static IP setup (optional).

## Usage

### Available Make Targets

- `make help` - Show available commands
- `make install` - Run the installer script
- `make check` - Check system requirements only
- `make download` - Download Ubuntu 20.04 cloud image
- `make vm_image` - Create VM disk image
- `make iso` - Create cloud-init ISO with configuration
- `make create_vm` - Create and start the VM
- `make status` - Show VM status
- `make clean` - Stop and remove VM
- `make clean_all` - Clean everything including downloaded images

### Step-by-Step VM Creation

1. **Run the installer (first time only):**
   ```bash
   ./install.sh
   ```

2. **Customize configuration files:**
   - Edit `user-data` or `init.yaml` to add your SSH public key
   - Modify `meta-data` to change hostname/instance ID
   - Adjust `network-config` if you need static networking

3. **Create the VM:**
   ```bash
   make create_vm
   ```

4. **Connect to the VM:**
   - Via SSH: `ssh ubuntu@<vm-ip>` (IP shown in VM creation output)
   - Via console: `virsh console hal9000`
   - Via VNC: Connect to the host on VNC port (usually 5900)

### SSH Key Setup

The installer can help you set up SSH keys:

1. It will check for existing SSH keys
2. Offer to generate new ones if none exist
3. Automatically add them to your cloud-init configuration

Alternatively, add your SSH public key manually to `user-data`:

```yaml
#cloud-config
users:
  - name: ubuntu
    ssh_authorized_keys:
      - ssh-rsa YOUR_PUBLIC_KEY_HERE user@hostname
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    groups: sudo
    shell: /bin/bash
```

## VM Configurations

### Basic Configuration (user-data)
- Creates `ubuntu` user with sudo privileges
- Configures SSH key authentication
- Basic system setup

### Extended Configuration (init.yaml)
- Creates `manage` user with comprehensive development environment
- Installs Docker and Docker Compose
- Installs Kubernetes (microk8s)
- Installs kubectl with completion
- Deploys sample containers
- Installs development tools (git, vim, curl, etc.)

## Troubleshooting

### Common Issues

1. **Permission denied errors:**
   ```bash
   # Make sure you're in the libvirt group
   sudo usermod -a -G libvirt $USER
   newgrp libvirt  # or log out and back in
   ```

2. **VM won't start:**
   ```bash
   # Check system requirements
   ./install.sh --check
   
   # Verify virtualization is enabled
   grep -E '(vmx|svm)' /proc/cpuinfo
   ```

3. **Network issues:**
   ```bash
   # Check default libvirt network
   sudo virsh net-list
   sudo virsh net-start default
   ```

4. **Can't connect via SSH:**
   - Verify your SSH public key is in the configuration
   - Check VM IP: `virsh domifaddr hal9000`
   - Wait for cloud-init to complete (may take a few minutes)

### Checking VM Status

```bash
# List all VMs
virsh list --all

# Get VM IP address
virsh domifaddr hal9000

# View VM console
virsh console hal9000

# Check cloud-init logs (inside VM)
sudo cloud-init status
sudo journalctl -u cloud-init
```

## System Requirements

- **OS:** Ubuntu 18.04+ (or compatible Debian-based distribution)
- **Architecture:** x86_64
- **RAM:** At least 4GB (2GB for the VM + host overhead)
- **Storage:** At least 10GB free space
- **CPU:** Hardware virtualization support (Intel VT-x or AMD-V)
- **Network:** Internet connection for downloading images and packages

## Security Notes

- The default configurations include sudo without password for convenience
- SSH key authentication is strongly recommended over password authentication
- The extended configuration installs various services that may expose ports
- Review and customize configurations for production use

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is provided as-is for educational and development purposes.

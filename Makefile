.PHONY: help install check download disk_image vm_image iso create_vm create_vm_local status clean clean_all

# Default target
help:
	@echo "Cloud-Init VM Setup"
	@echo "=================="
	@echo ""
	@echo "Available targets:"
	@echo "  install       - Run the installer script"
	@echo "  check         - Check system requirements only"
	@echo "  download      - Download Ubuntu cloud image"
	@echo "  disk_image    - Convert cloud image to raw format"
	@echo "  vm_image      - Create VM disk image"
	@echo "  iso           - Create cloud-init ISO"
	@echo "  create_vm     - Create VM (copies files to /var/lib/libvirt/images)"
	@echo "  create_vm_local - Create VM using local files (requires permissions)"
	@echo "  status        - Show VM status"
	@echo "  clean         - Stop and remove VM"
	@echo "  clean_all     - Clean everything including images"
	@echo "  fix_permissions - Fix home directory permissions for libvirt"
	@echo ""

install:
	@./install.sh

check:
	@./install.sh --check

download:
	@if [ ! -f focal-server-cloudimg-amd64.img ]; then \
		echo "Downloading Ubuntu 20.04 cloud image..."; \
		wget http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img; \
	else \
		echo "Ubuntu cloud image already exists"; \
	fi

disk_image: download
	@if [ ! -f focal-server-cloudimg-amd64.raw ]; then \
		echo "Converting cloud image to raw format..."; \
		qemu-img convert -f qcow2 -O raw focal-server-cloudimg-amd64.img focal-server-cloudimg-amd64.raw; \
	else \
		echo "Raw disk image already exists"; \
	fi

vm_image: download
	@if [ ! -f hal9000.img ]; then \
		echo "Creating VM disk image..."; \
		qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 -F qcow2 hal9000.img 10G; \
	else \
		echo "VM disk image already exists"; \
	fi

iso:
	@echo "Creating cloud-init ISO..."
	genisoimage -output cidata.iso -V cidata -r -J user-data meta-data

create_vm: vm_image iso
	@if virsh list --all | grep -q "hal9000"; then \
		echo "VM 'hal9000' already exists. Use 'make clean' first."; \
		exit 1; \
	fi
	@echo "Setting up files for libvirt..."
	@# Ensure libvirt images directory exists
	@if [ ! -d "/var/lib/libvirt/images" ]; then \
		sudo mkdir -p /var/lib/libvirt/images; \
	fi
	@# Copy base image first
	@if [ ! -f "/var/lib/libvirt/images/focal-server-cloudimg-amd64.img" ]; then \
		echo "Copying base Ubuntu image..."; \
		sudo cp focal-server-cloudimg-amd64.img /var/lib/libvirt/images/; \
		sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/images/focal-server-cloudimg-amd64.img; \
	fi
	@# Create VM image in libvirt directory
	@echo "Creating VM disk in libvirt storage..."
	@sudo qemu-img create -b /var/lib/libvirt/images/focal-server-cloudimg-amd64.img \
		-f qcow2 -F qcow2 /var/lib/libvirt/images/hal9000.img 10G
	@sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/images/hal9000.img
	@# Copy cloud-init ISO
	@sudo cp cidata.iso /var/lib/libvirt/images/cidata.iso
	@sudo chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/images/cidata.iso
	@echo "Creating VM..."
	virt-install --name=hal9000 --ram=2048 --vcpus=1 --import \
		--disk path=/var/lib/libvirt/images/hal9000.img,format=qcow2 \
		--disk path=/var/lib/libvirt/images/cidata.iso,device=cdrom \
		--os-variant=ubuntu20.04 \
		--network bridge=virbr0,model=virtio \
		--graphics vnc,listen=0.0.0.0 \
		--noautoconsole
	@echo "VM created successfully!"
	@echo "You can connect via VNC or wait for SSH to be available"

status:
	@echo "VM Status:"
	@virsh list --all | grep hal9000 || echo "VM 'hal9000' not found"
	@echo ""
	@echo "Network Status:"
	@virsh net-list || true

clean:
	@echo "Cleaning up VM..."
	@if virsh list | grep -q "hal9000.*running"; then \
		echo "Shutting down VM..."; \
		virsh shutdown hal9000; \
		sleep 5; \
	fi
	@if virsh list --all | grep -q "hal9000"; then \
		echo "Removing VM definition..."; \
		virsh undefine hal9000 --remove-all-storage; \
	fi
	@if [ -f cidata.iso ]; then \
		echo "Removing local cloud-init ISO..."; \
		rm -f cidata.iso; \
	fi
	@if [ -f "/var/lib/libvirt/images/hal9000.img" ]; then \
		echo "Removing VM disk from libvirt storage..."; \
		sudo rm -f /var/lib/libvirt/images/hal9000.img; \
	fi
	@if [ -f "/var/lib/libvirt/images/cidata.iso" ]; then \
		echo "Removing cloud-init ISO from libvirt storage..."; \
		sudo rm -f /var/lib/libvirt/images/cidata.iso; \
	fi
	@echo "Cleanup complete!"

clean_all: clean
	@echo "Removing all generated files..."
	@rm -f focal-server-cloudimg-amd64.img
	@rm -f focal-server-cloudimg-amd64.raw
	@rm -f hal9000.img
	@if [ -f "/var/lib/libvirt/images/focal-server-cloudimg-amd64.img" ]; then \
		echo "Removing base image from libvirt storage..."; \
		sudo rm -f /var/lib/libvirt/images/focal-server-cloudimg-amd64.img; \
	fi
	@echo "All files cleaned!"

clean_all: clean
	@echo "Removing all generated files..."
	@rm -f focal-server-cloudimg-amd64.img
	@rm -f focal-server-cloudimg-amd64.raw
	@rm -f hal9000.img
	@echo "All files cleaned!"

# Alternative VM creation using local files (requires permissions)
create_vm_local: vm_image iso
	@if virsh list --all | grep -q "hal9000"; then \
		echo "VM 'hal9000' already exists. Use 'make clean' first."; \
		exit 1; \
	fi
	@echo "Creating VM using local files..."
	@echo "Note: This requires proper permissions. Use 'make fix_permissions' if needed."
	virt-install --name=hal9000 --ram=2048 --vcpus=1 --import \
		--disk path=$(PWD)/hal9000.img,format=qcow2 \
		--disk path=$(PWD)/cidata.iso,device=cdrom \
		--os-variant=ubuntu20.04 \
		--network bridge=virbr0,model=virtio \
		--graphics vnc,listen=0.0.0.0 \
		--noautoconsole
	@echo "VM created successfully!"

# Fix home directory permissions for libvirt access
fix_permissions:
	@echo "Fixing permissions for libvirt access..."
	@echo "This will give libvirt-qemu user access to your home directory"
	@sudo chmod 755 /home/$(USER)
	@sudo setfacl -m u:libvirt-qemu:x /home/$(USER)
	@sudo chmod 644 hal9000.img cidata.iso
	@echo "Permissions fixed!"
	@echo "You can now use 'make create_vm_local'"

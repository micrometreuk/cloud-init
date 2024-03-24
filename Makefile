.PHONY: run
download:
	wget http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img
disk_image:
	qemu-img convert -f qcow2 -O raw focal-server-cloudimg-amd64.img focal-server-cloudimg-amd64.raw
vm_image:
	qemu-img create -b focal-server-cloudimg-amd64.img -f qcow2 -F qcow2 hal9000.img 10G
iso:
	genisoimage -output cidata.iso -V cidata -r -J user-data meta-data
create_vm:
	 virt-install --name=hal9000 --ram=2048 --vcpus=1 --import --disk path=hal9000.img,format=qcow2 --disk path=cidata.iso,device=cdrom --os-variant=ubuntu20.04 --network bridge=virbr0,model=virtio --graphics vnc,listen=0.0.0.0 --noautoconsole
clean:
	virsh shutdown hal9000
	virsh undefine hal9000

#!/bin/bash

# For detailed comments and notes, visit https://wiki.test.redhat.com/Kernel/Filesystem/windows-demo

# Include function
. ./function


# =======================================================================
# Common Parameters, both KVM and windows use them
# =======================================================================
VM_MAC=$(gen_virt_mac)
VM_EXT_MAC=$(gen_virt_mac 01)
ANS_FILE_DIR="$(pwd)/answerfiles"
DEFAULT_IF=$(ip -4 route get 1 | head -n 1 | awk '{print $5}')

# =======================================================================
# Parameter Processing
# =======================================================================
ARGS=`getopt -o bhi:n:p:t: \
	--long bridge \
	--long help \
	--long vm-name: \
	--long image: \
	--long script-path: \
	--long ans-file-media-type: \
	--long admin-password: \
	--long product-key: \
	--long domain: \
	--long ad-forest-level: \
	--long ad-domain-level: \
	--long ram: \
	--long cpus: \
	--long disk-size: \
	--long os-variant: \
	--long timeout: \
	-n "$0" -- "$@"`
eval set -- "$ARGS"
while true; do
	case "$1" in
	-b|--bridge) BRIDGE=`setup_bridge`; shift 1;; 
	-h|--help) Usage; exit 1;; 
	-i|--image) WIN_ISO="$2"; shift 2;;
	-n|--vm-name) VM_NAME="$2"; shift 2;;
	-p|--script-path) EXTRA_SCRIPT="$2"; add_extra_script;shift 2;;
	-t|--ans-file-media-type) ANSF_MEDIA_TYPE="$2"; shift 2;;
	--admin-password) ADMINPASSWORD="$2"; shift 2;;
	--product-key) PRODUCT_KEY="$2"; shift 2;;
	--domain) DOMAIN="$2"; shift 2;;
	--ad-forest-level) AD_FOREST_LEVEL="$2"; shift 2;;
	--ad-domain-level) AD_DOMAIN_LEVEL="$2"; shift 2;;
	--ram) VM_RAM="$2"; shift 2;;
	--cpus) VM_CPUS="$2"; shift 2;;
	--disk-size) VM_DISKSIZE="$2"; shift 2;;
	--os-variant) VM_OS_VARIANT="$2"; shift 2;;
	--timeout) VM_TIMEOUT="$2";shift 2;;
	--) shift; break;;
	*) Usage; exit 1;; 
	esac
done

# =======================================================================
# Windows Preparation
# =======================================================================

# Setup windows
ADMINNAME=${ADMINNAME:-Administrator}
DNS_IF_MAC=$VM_EXT_MAC
MAC_DISABLE=$VM_MAC

# Setup Active Directory
FQDN=${FQDN:-$VM_NAME.$DOMAIN}
NETBIOS_NAME=`echo $DOMAIN | sed -e 's/\.//g' | tr '[a-z]' '[A-Z]'`

# =======================================================================
# KVM Preparation
# =======================================================================

# Enable libvirtd remote access
sed -i -e "/#libvirtd_args/s/^#//" /etc/sysconfig/libvirtd
sed -i -e "/#listen_tls/s/^#//" /etc/libvirt/libvirtd.conf
systemctl restart libvirtd.service
systemctl restart virtlogd.service

# Parameters
VM_IMG_DIR=/var/lib/libvirt/images
ANSF_CDROM=${ANSF_CDROM:-$VM_IMG_DIR/$VM_NAME-ansf-cdrom.iso}
ANSF_FLOPPY=${ANSF_FLOPPY:-$VM_IMG_DIR/$VM_NAME-ansf-floppy.vfd}
WIN_VM_DISKFILE=${WIN_VM_DISKFILE:-$VM_IMG_DIR/$VM_NAME.qcow2}
VM_NETWORK_NAME=default
VM_IP=$(gen_ip)
VM_EXT_IP=
VIRTHOST=$(hostname -f)
VM_WAIT_FILE="\\\\installcomplete"
SERIAL_PATH=/tmp/serial-`date +'%Y%m%d%H%M%S'`.$$
VM_NETWORK_INTERNAL="--network network=$VM_NETWORK_NAME,model=rtl8139,mac=$VM_MAC"
VM_NETWORK_EXTRA="--network type=direct,source=$DEFAULT_IF,source_mode=vepa,mac=$VM_EXT_MAC"
VM_NETWORK=${BRIDGE:-"$VM_NETWORK_INTERNAL $VM_NETWORK_EXTRA"}

# Update KVM network configuration
if [ -z "$BRIDGE" ]; then
	virsh net-update $VM_NETWORK_NAME delete ip-dhcp-host "<host ip='"$VM_IP"' />" --live --config
	virsh net-update $VM_NETWORK_NAME add ip-dhcp-host "<host mac='"$VM_MAC"' name='"$VM_NAME"' ip='"$VM_IP"' />" --live --config
fi

# =======================================================================
# Setup
# =======================================================================

# Generate answerfiles cdrom/floppy
make_ansf

# Place libguestfs temporary files in properly labeled dir
TMPDIR="/tmp/libguestfs"
export TMPDIR
mkdir $TMPDIR
chcon -t svirt_tmp_t $TMPDIR

# Execute virt-install command with the parameters given

case "$ANSF_MEDIA_TYPE" in
	"floppy") ANSF_MEDIA_PATH=$ANSF_FLOPPY;;
	"cdrom") ANSF_MEDIA_PATH=$ANSF_CDROM;;
esac
virt-install --connect=qemu:///system --hvm \
		--clock offset=utc \
		--accelerate --name "$VM_NAME" --ram=$VM_RAM --vcpu=$VM_CPUS --cpu host,-invtsc \
		--disk path=$WIN_ISO,device=cdrom \
		--vnc --os-variant ${VM_OS_VARIANT} \
		--serial file,path=$SERIAL_PATH --serial pty \
		--disk path=$WIN_VM_DISKFILE,bus=ide,size=$VM_DISKSIZE,format=qcow2,cache=none \
		--disk path=$ANSF_MEDIA_PATH,device=$ANSF_MEDIA_TYPE \
		$VM_NETWORK \
		|| { echo error $? from virt-install ; exit 1 ; }

# To check whether the installation is done
wait_for_completion

# =======================================================================
# Post Setup
# =======================================================================

# Fetch the external ip address from windows
# for machine from outside to reach it
VM_EXT_IP=`get_external_ip`

# When installation is done, test AD connection and get AD CA cert
get_cert

# Also save other variables into a log file
save_ad_env

# Eject CDs
eject_cds

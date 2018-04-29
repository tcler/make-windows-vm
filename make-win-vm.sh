#!/bin/bash

# Include function
. ./function
PROG=${0##*/}

# ==============================================================================
# Parameter Processing
# ==============================================================================
Usage() {
cat <<EOF
Usage: $PEOG [OPTION]...

  -h, --help    #Display this help.

  --image </path/to/image>
		#*Specify the path to windows image.
  --product-key #Prodcut key for windows activation.
  --hostname <hostname>
		#hostname of windows
  --domain <domain>
		#*Specify windows domain name.
  -u <user>     #Specify user for install and config, default: Administrator
  -p <password> #*Specify user's password for windows.

  --ad-forest-level
		#Specify active directory forest level.
  --ad-domain-level
		#Specify active directory domain level.

  --vm-name <VM_NAME>
		#*Specify the vm guest's name.
  --ram         #VM's ram size
  --cpus        #Numbers of cpu cores for VM.
  --disk-size   #VM disk size, in .qcow2 format.
  --os-variant  #*Specify os variant in for VM.
  -t --ans-file-media-type <cdrom|floppy>
		#Specify the answerfiles media type loaded to KVM.
  -b, --bridge  #Use traditional bridge interface br0. Not recommended.
  --timeout     #Set waiting timeout for installation.
EOF
}

ARGS=$(getopt -o hu:p:t:b \
	--long help \
	--long image: \
	--long product-key: \
	--long hostname: \
	--long domain: \
	--long ad-forest-level: \
	--long ad-domain-level: \
	--long vm-name: \
	--long ram: \
	--long cpus: \
	--long disk-size: \
	--long os-variant: \
	--long ans-file-media-type: \
	--long bridge \
	--long timeout: \
	-n "$PROG" -- "$@")
eval set -- "$ARGS"
while true; do
	case "$1" in
	-h|--help) Usage; exit 1;; 
	--image) WIN_ISO="$2"; shift 2;;
	--product-key) PRODUCT_KEY="$2"; shift 2;;
	--hostname) PRODUCT_KEY="$2"; shift 2;;
	--domain) DOMAIN="$2"; shift 2;;
	-u) ADMINNAME="$2"; shift 2;;
	-p) ADMINPASSWORD="$2"; shift 2;;
	--ad-forest-level) AD_FOREST_LEVEL="$2"; shift 2;;
	--ad-domain-level) AD_DOMAIN_LEVEL="$2"; shift 2;;
	--vm-name) VM_NAME="$2"; shift 2;;
	--ram) VM_RAM="$2"; shift 2;;
	--cpus) VM_CPUS="$2"; shift 2;;
	--disk-size) VM_DISKSIZE="$2"; shift 2;;
	--os-variant) VM_OS_VARIANT="$2"; shift 2;;
	-t|--ans-file-media-type) ANSF_MEDIA_TYPE="$2"; shift 2;;
	-b|--bridge) brgmode=yes; shift 1;; 
	--timeout) VM_TIMEOUT="$2";shift 2;;
	--) shift; break;;
	*) Usage; exit 1;; 
	esac
done

[[ -z "$WIN_ISO" || -z "$PRODUCT_KEY" || -z "$ADMINPASSWORD" || 
   -z "$VM_NAME" || -z "$VM_OS_VARIANT" ]] && {
	Usage
	exit 1
}

# =======================================================================
# Global variable
# =======================================================================
IPCONFIG_LOG=ipconfig.log
INSTALL_COMPLETE=installcomplete

# =======================================================================
# Windows Preparation
# =======================================================================
GUEST_HOSTNAME=${GUEST_HOSTNAME:-$VM_NAME}
DOMAIN=${DOMAIN:-mytest.com}
ADMINNAME=${ADMINNAME:-Administrator}
ADMINPASSWORD=${ADMINPASSWORD:-password}
VM_MAC=$(gen_virt_mac)
VM_EXT_MAC=$(gen_virt_mac 01)
DNS_IF_MAC=$VM_EXT_MAC
MAC_DISABLE=$VM_MAC

# Setup Active Directory
FQDN=${FQDN:-$GUEST_HOSTNAME.$DOMAIN}
NETBIOS_NAME=$(echo ${DOMAIN//./} | tr '[a-z]' '[A-Z]')

# =======================================================================
# KVM Preparation
# =======================================================================
# Enable libvirtd remote access
sed -i -e "/#libvirtd_args/s/^#//" /etc/sysconfig/libvirtd
sed -i -e "/#listen_tls/s/^#//" /etc/libvirt/libvirtd.conf
systemctl restart libvirtd.service
systemctl restart virtlogd.service

# ====================================================================
# Setup_bridge
# ====================================================================
DEFAULT_IF=$(ip -4 route get 1 | head -n 1 | awk '{print $5}')
[[ "$brgmode" = yes ]] && {
	echo "{INFO} bridge mode setup ..."
	if [ $DEFAULT_IF != "br0" ]; then
		network_path="/etc/sysconfig/network-scripts"
		echo -e "TYPE=Bridge\nBOOTPROTO=dhcp\nDEVICE=br0\nONBOOT=yes" \
			> $network_path/ifcfg-br0
		grep br0 $network_path/ifcfg-$DEFAULT_IF
		if [ $? -ne 0 ]; then
			echo "BRIDGE=br0" >> $network_path/ifcfg-$DEFAULT_IF
		fi
		systemctl restart network > /dev/null 2>&1
	fi
	VM_NET_OPT_BRIDGE="--network bridge=br0,model=rtl8139,mac=$VM_EXT_MAC"
}

# Parameters
VM_IMG_DIR=/var/lib/libvirt/images
ANSF_CDROM=${ANSF_CDROM:-$VM_IMG_DIR/$VM_NAME-ansf-cdrom.iso}
ANSF_FLOPPY=${ANSF_FLOPPY:-$VM_IMG_DIR/$VM_NAME-ansf-floppy.vfd}
VM_IMAGE=${VM_IMAGE:-$VM_IMG_DIR/$VM_NAME.qcow2}
VM_NETWORK_NAME=default
VM_IP=$(gen_ip)
VM_NET_OPT_INTERNAL="--network network=$VM_NETWORK_NAME,model=rtl8139,mac=$VM_MAC"
VM_NET_OPT_EXTRA="--network type=direct,source=$DEFAULT_IF,source_mode=vepa,mac=$VM_EXT_MAC"
VM_NET_OPT=${VM_NET_OPT_BRIDGE:-"$VM_NET_OPT_INTERNAL $VM_NET_OPT_EXTRA"}
SERIAL_PATH=/tmp/serial-$(date +%Y%m%d%H%M%S).$$
VIRTHOST=$(hostname -f)

# Update KVM network configuration
if [ -z "$VM_NET_OPT_BRIDGE" ]; then
	echo "{INFO} virsh net-update ..."
	virsh net-update $VM_NETWORK_NAME delete ip-dhcp-host "<host ip='"$VM_IP"' />" --live --config
	virsh net-update $VM_NETWORK_NAME add ip-dhcp-host "<host mac='"$VM_MAC"' name='"$VM_NAME"' ip='"$VM_IP"' />" --live --config
fi

# ====================================================================
# Generate cdrom/floppy of answerfiles
# ====================================================================
process_ansf() {
	local destdir=$1; shift
	for f; do fname=${f##*/}; cp ${f} $destdir/${fname%.in}; done

	sed -i -e "s/@ADMINPASSWORD@/$ADMINPASSWORD/g" \
		-e "s/@ADMINNAME@/$ADMINNAME/g" \
		-e "s/@AD_DOMAIN@/$DOMAIN/g" \
		-e "s/@NETBIOS_NAME@/$NETBIOS_NAME/g" \
		-e "s/@VM_NAME@/$VM_NAME/g" \
		-e "s/@FQDN@/$FQDN/g" \
		-e "s/@PRODUCT_KEY@/$PRODUCT_KEY/g" \
		-e "s/@ANSF_DRIVE_LETTER@/$ANSF_DRIVE_LETTER/g" \
		-e "s/@INSTALL_COMPLETE@/$INSTALL_COMPLETE/g" \
		-e "s/@AD_FOREST_LEVEL@/$AD_FOREST_LEVEL/g" \
		-e "s/@AD_DOMAIN_LEVEL@/$AD_DOMAIN_LEVEL/g" \
		-e "s/@MAC_DISABLE@/$MAC_DISABLE/g" \
		-e "s/@DNS_IF_MAC@/$DNS_IF_MAC/g" \
		-e "s/@VIRTHOST@/$VIRTHOST/g" \
		-e "s/@IPCONFIG_LOG@/$IPCONFIG_LOG/g" \
		$destdir/*
	unix2dos $destdir/*
}

echo "{INFO} make answer file media ..."
rm -f $ANSF_FLOPPY $ANSF_CDROM  #remove old/exist media file
media_mp=$(mktemp -d)
case "$ANSF_MEDIA_TYPE" in
"floppy")
	ANSF_MEDIA_PATH=$ANSF_FLOPPY
	ANSF_DRIVE_LETTER="A:"
	mkfs.vfat -C $ANSF_FLOPPY 1440 || { echo error $? from mkfs.vfat -C $ANSF_FLOPPY 1440; exit 1; }
	mount -o loop -t vfat $ANSF_FLOPPY $media_mp
	process_ansf $media_mp "$@"
	umount $media_mp
	;;
"cdrom")
	ANSF_MEDIA_PATH=$ANSF_CDROM
	ANSF_DRIVE_LETTER="E:"
	process_ansf $media_mp "$@"
	genisoimage -iso-level 4 -J -l -R -o $ANSF_CDROM $media_mp
	;;
esac
rm -rf $media_mp

# Place libguestfs temporary files in properly labeled dir
TMPDIR="/tmp/libguestfs"
export TMPDIR
mkdir -p $TMPDIR
chcon -t svirt_tmp_t $TMPDIR

# Execute virt-install command with the parameters given
echo "{INFO} virt-install ..."
rm -f $VM_IMAGE
virt-install --connect=qemu:///system --hvm --clock offset=utc \
	--accelerate --cpu host,-invtsc \
	--name "$VM_NAME" --ram=${VM_RAM:-2048} --vcpu=${VM_CPUS:-2} \
	--os-variant ${VM_OS_VARIANT} \
	--disk path=$WIN_ISO,device=cdrom \
	--disk path=$VM_IMAGE,bus=ide,size=$VM_DISKSIZE,format=qcow2,cache=none \
	--disk path=$ANSF_MEDIA_PATH,device=$ANSF_MEDIA_TYPE \
	--serial file,path=$SERIAL_PATH --serial pty \
	$VM_NET_OPT \
	--vnc --vnclisten 0.0.0.0 --vncport 7788 || { echo error $? from virt-install ; exit 1 ; }

# To check whether the installation is done
echo "{INFO} waiting install done ..."
success=no
t=${VM_TIMEOUT:-60}
while ((t-- > 0)) ; do
	virt-cat -d $VM_NAME "/$INSTALL_COMPLETE" > /dev/null 2>&1 && {
		success=yes; break;
	}
	sleep 1m
done
[[ $success != yes ]] && {
	echo "{WARN} Install timeout($VM_TIMEOUT)"
}

# =======================================================================
# Post Setup
# =======================================================================
# When installation is done, test AD connection and get AD CA cert
echo "{INFO} get cert test ..."
get_cert

# Eject CDs
echo "{INFO} eject media ..."
eject_cds $VM_NAME  $WIN_ISO $ANSF_MEDIA_PATH

# Save relative variables info a log file
VM_EXT_IP=$(virt-cat -d $VM_NAME /$IPCONFIG_LOG |
	grep IPv4.Address | grep -v 192.168.122 |
	egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
VM_INFO_FILE=/tmp/$VM_NAME.info
cat <<- EOF | tee $VM_INFO_FILE
	VM_NAME=$VM_NAME
	VM_IP=$VM_IP
	VM_EXT_IP=$VM_EXT_IP
	ADMINNAME=$ADMINNAME
	ADMINPASSWORD=$ADMINPASSWORD
	DOMAIN=$DOMAIN
	FQDN=$FQDN
	NETBIOS_NAME=$NETBIOS_NAME
EOF

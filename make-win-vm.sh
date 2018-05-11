#!/bin/bash

LANG=C
PROG=${0##*/}

is_bridge() {
	local ifname=$1
	[[ -z "$ifname" || -n "$(brctl show $ifname 2>&1 >/dev/null)" ]] && return 1
	return 0
}

get_default_if() {
	local dev=$1
	local iface=

	iface=$(ip route get 1 | awk '/^[0-9]/{print $5}')
	if [[ -n "$dev" ]] && is_bridge $iface; then
		brctl show $iface | awk 'NR==2 {print $4}'
		return 0
	fi
	echo $iface
}

create_bridge() {
	local brname=${1:-br0}
	local net_script_path=/etc/sysconfig/network-scripts

	if is_bridge $brname; then
		local dev=$(get_default_if dev)
		echo "[${FUNCNAME[0]}] bridge $brname exist"
		grep -q "^ *BRIDGE=$brname" $net_script_path/ifcfg-$dev || {
			echo "[${FUNCNAME[0]}] br addif($brname $dev) and restart network service ..."
			echo "BRIDGE=$brname" >>$net_script_path/ifcfg-$dev
			service network restart >/dev/null
		}
	else
		local iface=$(get_default_if)
		echo "[${FUNCNAME[0]}] creating bridge($brname $iface) ..."
		echo -e "TYPE=Bridge\nBOOTPROTO=dhcp\nDEVICE=$brname\nONBOOT=yes" \
			> $net_script_path/ifcfg-$brname
		grep -q "^ *BRIDGE=$brname" $net_script_path/ifcfg-$iface || {
			echo "BRIDGE=$brname" >>$net_script_path/ifcfg-$iface
		}
		echo "[${FUNCNAME[0]}] restart network service ..."
		service network restart >/dev/null
	fi
	echo
	brctl show $brname
}

br_delif() {
	local net_script_path=/etc/sysconfig/network-scripts
	local br=$(get_default_if)

	if is_bridge $br; then
		local dev=$(get_default_if dev)
		echo "[${FUNCNAME[0]}] br delif($br $dev) and restart network service ..."
		sed -i "/BRIDGE=$br *$/d" $net_script_path/ifcfg-$dev
		service network restart >/dev/null
	fi
}

# Generate a random mac address with 54:52:00: prefix
gen_virt_mac() {
    echo 54:52:00:${1:-00}$(od -txC -An -N2 /dev/random | tr \  :)
}

# Eject CDs
eject_cds() {
	local vm_name=$1; shift
	local media_list="$@"

	for media in $media_list; do
		vm_media=$(virsh domblklist "$vm_name" | awk -v media=$media '$2==media {print $1}')
		virsh change-media "$vm_name" "$vm_media" --eject
	done
}

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

  --ad-forest-level <Default|Win2008|Win2008R2|Win2012|Win2012R2|WinThreshold>
		#Specify active directory forest level.
		  Windows Server 2003: 2 or Win2003
		  Windows Server 2008: 3 or Win2008
		  Windows Server 2008 R2: 4 or Win2008R2
		  Windows Server 2012: 5 or Win2012
		  Windows Server 2012 R2: 6 or Win2012R2
		  Windows Server 2016: 7 or WinThreshold
		#The default forest functional level in Windows Server is typically the same -
		#as the version you are running. However, the default forest functional level -
		#in Windows Server 2008 R2 when you create a new forest is Windows Server 2003 or 2.
		#see: https://docs.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest?view=win10-ps
  --ad-domain-level <Default|Win2008|Win2008R2|Win2012|Win2012R2|WinThreshold>
		#Specify active directory domain level.
		  Windows Server 2003: 2 or Win2003
		  Windows Server 2008: 3 or Win2008
		  Windows Server 2008 R2: 4 or Win2008R2
		  Windows Server 2012: 5 or Win2012
		  Windows Server 2012 R2: 6 or Win2012R2
		  Windows Server 2016: 7 or WinThreshold
		#The domain functional level cannot be lower than the forest functional level,
		#but it can be higher. The default is automatically computed and set.
		#see: https://docs.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest?view=win10-ps

  --vm-name <VM_NAME>
		#*Specify the vm guest's name.
  --ram         #VM's ram size
  --cpus        #Numbers of cpu cores for VM.
  --disk-size   #VM disk size, in .qcow2 format.
  --os-variant  <win2k12|win2k12r2|win2k16|win10|win7|...>
                #*Use the command "osinfo-query os" to get the list of the accepted OS variants
  -t --ans-file-media-type <cdrom|floppy>
		#Specify the answerfiles media type loaded to KVM.
  -b, --bridge  #Use traditional bridge interface br0. Not recommended.
  --timeout     #Set waiting timeout for installation.
  --vncport <>  #Set vncport
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
	--long vncport: \
	-n "$PROG" -- "$@")
eval set -- "$ARGS"
while true; do
	case "$1" in
	-h|--help) Usage; exit 1;; 
	--image) WIN_ISO="$2"; shift 2;;
	--product-key) PRODUCT_KEY="$2"; shift 2;;
	--hostname) GUEST_HOSTNAME="$2"; shift 2;;
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
	-b|--bridge) MacvTap=bridge; shift 1;; 
	--timeout) VM_TIMEOUT="$2"; shift 2;;
	--vncport) VNC_PORT="$2"; shift 2;;
	--) shift; break;;
	*) Usage; exit 1;; 
	esac
done

AD_FOREST_LEVEL=${AD_FOREST_LEVEL:-Default}
AD_DOMAIN_LEVEL=${AD_DOMAIN_LEVEL:-$AD_FOREST_LEVEL}

[[ -z "$WIN_ISO" || -z "$ADMINPASSWORD" ||
   -z "$VM_NAME" || -z "$VM_OS_VARIANT" ]] && {
	Usage
	exit 1
}
[[ -z "$PRODUCT_KEY" ]] && {
	echo -e "{WARN} *** There is no Product Key specified, We assume that you are using evaluation version."
	echo -e "{WARN} *** Otherwise please use the '--product-key <key>' to ensure successful installation."
}

# =======================================================================
# Global variable
# =======================================================================
IPCONFIG_LOGF=ipconfig.log
INSTALL_COMPLETE_FILE=installcomplete
POST_INSTALL_LOGP=C:
POST_INSTALL_LOGF=postinstall.log
VM_IMG_DIR=/var/lib/libvirt/images
VM_TIMEOUT=${VM_TIMEOUT:-60}

# =======================================================================
# Windows Preparation
# =======================================================================
GUEST_HOSTNAME=${GUEST_HOSTNAME:-$VM_NAME}
DOMAIN=${DOMAIN:-mytest.com}
ADMINNAME=${ADMINNAME:-Administrator}
ADMINPASSWORD=${ADMINPASSWORD:-password}

# Setup Active Directory
FQDN=$GUEST_HOSTNAME.$DOMAIN
NETBIOS_NAME=$(echo ${DOMAIN//./} | tr '[a-z]' '[A-Z]')

# =======================================================================
# KVM Preparation
# =======================================================================
# Enable libvirtd remote access
sed -i -e "/#libvirtd_args/s/^#//" /etc/sysconfig/libvirtd
sed -i -e "/#listen_tls/s/^#//" /etc/libvirt/libvirtd.conf
systemctl restart libvirtd.service
systemctl restart virtlogd.service

# VM network parameters
MacvTap=${MacvTap:-vepa}
VM_EXT_MAC=$(gen_virt_mac 01)
BR_NAME=br0
echo -e "\n{INFO} vm nic for reach outside network(mac: $VM_EXT_MAC) (MacvTap:$MacvTap) ..."
if [[ "$MacvTap" = vepa ]]; then
	br_delif
	DEFAULT_NIC=$(get_default_if dev)
	VM_NET_OPT_EXTERNAL="type=direct,source=$DEFAULT_NIC,source_mode=vepa,mac=$VM_EXT_MAC"
else
	create_bridge $BR_NAME
	VM_NET_OPT_EXTERNAL="bridge=$BR_NAME,model=rtl8139,mac=$VM_EXT_MAC"
fi

VM_NET_NAME=default
VM_INT_MAC=$(gen_virt_mac)
echo -e "\n{INFO} vm nic for inside network(mac: $VM_INT_MAC) ..."
VM_NET_OPT_INTERNAL="network=$VM_NET_NAME,model=rtl8139,mac=$VM_INT_MAC"

# VM disk parameters ...
ANSF_MEDIA_TYPE=${ANSF_MEDIA_TYPE:-floppy}
ANSF_CDROM=${ANSF_CDROM:-$VM_IMG_DIR/$VM_NAME-ansf-cdrom.iso}
ANSF_FLOPPY=${ANSF_FLOPPY:-$VM_IMG_DIR/$VM_NAME-ansf-floppy.vfd}
VM_IMAGE=${VM_IMAGE:-$VM_IMG_DIR/$VM_NAME.qcow2}
SERIAL_PATH=/tmp/serial-$(date +%Y%m%d%H%M%S).$$

# ====================================================================
# Generate cdrom/floppy of answerfiles
# ====================================================================
process_ansf() {
	local destdir=$1; shift
	for f; do fname=${f##*/}; cp ${f} $destdir/${fname%.in}; done

	local VIRTHOST=$(hostname -f)
	sed -i -e "s/@ADMINPASSWORD@/$ADMINPASSWORD/g" \
		-e "s/@ADMINNAME@/$ADMINNAME/g" \
		-e "s/@AD_DOMAIN@/$DOMAIN/g" \
		-e "s/@NETBIOS_NAME@/$NETBIOS_NAME/g" \
		-e "s/@VM_NAME@/$VM_NAME/g" \
		-e "s/@FQDN@/$FQDN/g" \
		-e "s/@PRODUCT_KEY@/$PRODUCT_KEY/g" \
		-e "s/@ANSF_DRIVE_LETTER@/$ANSF_DRIVE_LETTER/g" \
		-e "s/@INSTALL_COMPLETE_FILE@/$INSTALL_COMPLETE_FILE/g" \
		-e "s/@AD_FOREST_LEVEL@/$AD_FOREST_LEVEL/g" \
		-e "s/@AD_DOMAIN_LEVEL@/$AD_DOMAIN_LEVEL/g" \
		-e "s/@MAC_DISABLE@/$VM_INT_MAC/g" \
		-e "s/@DNS_IF_MAC@/$VM_EXT_MAC/g" \
		-e "s/@VIRTHOST@/$VIRTHOST/g" \
		-e "s/@IPCONFIG_LOGF@/$IPCONFIG_LOGF/g" \
		-e "s/@POST_INSTALL_LOG@/$POST_INSTALL_LOGP\\\\$POST_INSTALL_LOGF/g" \
		$destdir/*
	unix2dos $destdir/* >/dev/null
	[[ -z "$PRODUCT_KEY" ]] &&
		sed -i '/<ProductKey>/ { :loop /<\/ProductKey>/! {N; b loop}; s;<ProductKey>.*</ProductKey>;; }' $destdir/*.xml
}

echo -e "\n{INFO} make answer file media ..."
\rm -f $ANSF_FLOPPY $ANSF_CDROM  #remove old/exist media file
media_mp=$(mktemp -d)
case "$ANSF_MEDIA_TYPE" in
"floppy")
	ANSF_MEDIA_PATH=$ANSF_FLOPPY
	ANSF_DRIVE_LETTER="A:"
	POST_INSTALL_LOGP="A:"
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
\rm -rf $media_mp

# Execute virt-install command with the parameters given
echo -e "\n{INFO} virt-install ..."
\rm -f $VM_IMAGE
virt-install --connect=qemu:///system --hvm --clock offset=utc \
	--accelerate --cpu host,-invtsc \
	--name "$VM_NAME" --ram=${VM_RAM:-2048} --vcpu=${VM_CPUS:-2} \
	--os-variant ${VM_OS_VARIANT} \
	--disk path=$WIN_ISO,device=cdrom \
	--disk path=$VM_IMAGE,bus=ide,size=$VM_DISKSIZE,format=qcow2,cache=none \
	--disk path=$ANSF_MEDIA_PATH,device=$ANSF_MEDIA_TYPE \
	--serial file,path=$SERIAL_PATH --serial pty \
	--network $VM_NET_OPT_EXTERNAL --network $VM_NET_OPT_INTERNAL \
	--vnc --vnclisten 0.0.0.0 --vncport ${VNC_PORT:-7788} || { echo error $? from virt-install ; exit 1 ; }
\rm $SERIAL_PATH

# To check whether the installation is done
echo -e "\n{INFO} waiting install done ..."
fsdev=/dev/sdb1
[[ "$ANSF_MEDIA_TYPE" = floppy ]] && fsdev=/dev/sdc
for ((i=0; i<=VM_TIMEOUT; i++)) ; do
	virt-cat -d $VM_NAME -m $fsdev /$INSTALL_COMPLETE_FILE &>/dev/null && break
	sleep 1m
done
((i > $VM_TIMEOUT)) && { echo -e "\n{WARN} Install timeout($VM_TIMEOUT)"; }

# Get install and ipconfig log
WIN_INSTALL_LOG=/tmp/$VM_NAME.install.log
virt-cat -d $VM_NAME -m $fsdev /$POST_INSTALL_LOGF |
	iconv -f UTF-16LE -t UTF-8 - >$WIN_INSTALL_LOG
WIN_IPCONFIG_LOG=/tmp/$VM_NAME.ipconfig.txt
virt-cat -d $VM_NAME -m $fsdev /$IPCONFIG_LOGF >$WIN_IPCONFIG_LOG
dos2unix $WIN_INSTALL_LOG $WIN_IPCONFIG_LOG

# Eject CDs
echo -e "\n{INFO} eject media ..."
eject_cds $VM_NAME  $WIN_ISO $ANSF_MEDIA_PATH

# =======================================================================
# Post Setup
# =======================================================================
# Save relative variables into a log file
echo -e "\n{INFO} show guest info:"
VM_INT_IP=$(awk '/^ *IPv4 Address/ {if ($NF ~ /^192/) print $NF}' $WIN_IPCONFIG_LOG)
VM_EXT_IP=$(awk '/^ *IPv4 Address/ {if ($NF !~ /^192/) print $NF}' $WIN_IPCONFIG_LOG)
VM_EXT_IP6=$(awk '/^ *IPv6 Address/ {printf("[%s]", $NF)}' $WIN_IPCONFIG_LOG)
[[ -z "$VM_EXT_IP" ]] && VM_EXT_IP=$VM_EXT_IP6

VM_INFO_FILE=/tmp/$VM_NAME.env
cat <<-EOF | tee $VM_INFO_FILE
	VM_NAME=$VM_NAME
	VM_INT_IP=$VM_INT_IP
	VM_EXT_IP=$VM_EXT_IP
	ADMINNAME=$ADMINNAME
	ADMINPASSWORD=$ADMINPASSWORD
	DOMAIN=$DOMAIN
	FQDN=$FQDN
	NETBIOS_NAME=$NETBIOS_NAME
EOF

# Test AD connection and get AD CA cert
echo -e "\n{INFO} Please run follow command to test AD connection"
ldapurl=ldap://${VM_INT_IP}
echo "./get-cert.sh $VM_NAME $FQDN $DOMAIN $ADMINNAME:$ADMINPASSWORD $ldapurl"
echo "./get-cert.sh $VM_NAME $FQDN $DOMAIN $ADMINNAME:$ADMINPASSWORD $ldapurl"|bash

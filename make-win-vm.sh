#!/bin/bash

LANG=C
PROG=${0##*/}

is_bridge() {
	local ifname=$1
	[[ -z "$ifname" ]] && return 1
	ip -d a s $ifname | grep -qw bridge
}

get_default_if() {
	local notbr=$1  #indicate get real NIC not bridge
	local iface=

	iface=$(ip route get 1 | awk '/^[0-9]/{print $5}')
	if [[ -n "$notbr" ]] && is_bridge $iface; then
		# ls /sys/class/net/$iface/brif
		if command -v brctl; then
			brctl show $iface | awk 'NR==2 {print $4}'
		else
			ip link show type bridge_slave | awk -F'[ :]+' '/master '$iface' state UP/{print $2}' | head -n1
		fi
		return 0
	fi
	echo $iface
}

add_bridge() {
	local brname=$1

	if [[ -f /etc/init.d/network ]]; then
		local net_script_path=/etc/sysconfig/network-scripts
		echo -e "TYPE=Bridge\nBOOTPROTO=dhcp\nDEVICE=$brname\nONBOOT=yes" \
			> $net_script_path/ifcfg-$brname
	else
		ip link add $brname type bridge
	fi
}

add_if_to_bridge() {
	local iface=$1
	local brname=$2

	if [[ -f /etc/init.d/network ]]; then
		local net_script_path=/etc/sysconfig/network-scripts
		echo "[${FUNCNAME[0]}] br addif($brname $iface) and restart network service ..."
		grep -q "^ *BRIDGE=$brname" $net_script_path/ifcfg-$iface || {
			echo "BRIDGE=$brname" >>$net_script_path/ifcfg-$iface
		}
		service network restart
	else
		echo "[${FUNCNAME[0]}] br addif($brname $iface) and up by dhclient ..."
		ip link set $iface master $brname
		dhclient $brname
	fi
}

create_bridge() {
	local brname=${1:-br0}

	if is_bridge $brname; then
		local iface=$(get_default_if notbr)
		echo "[${FUNCNAME[0]}] bridge $brname exist"
		add_if_to_bridge $iface $brname
	else
		local iface=$(get_default_if)
		echo "[${FUNCNAME[0]}] creating bridge($brname $iface) ..."
		add_bridge $brname
		add_if_to_bridge $iface $brname
	fi
	echo
	{ brctl show $brname || ip link show $brname type bridge; } 2>/dev/null
}

br_delif() {
	local br=$(get_default_if)

	if is_bridge $br; then
		local dev=$(get_default_if notbr)
		if [[ -f /etc/init.d/network ]]; then
			echo "[${FUNCNAME[0]}] remove if from br($dev $br) and restart network service ..."
			sed -i "/BRIDGE=$br *$/d" $net_script_path/ifcfg-$dev
			service network restart
		else
			echo "[${FUNCNAME[0]}] remove if from br($dev $br) and up by dhclient ..."
			ip link set $dev promisc off
			ip link set $dev down
			ip link set dev $dev nomaster
			dhclient $dev
		fi
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
Usage: $PROG [OPTION]...

  -h, --help    #Display this help.

  --image </path/to/image>
		#*Specify the path to windows image.
  --wim-index <wim image index>
  --product-key #Prodcut key for windows activation.
  --hostname <hostname>
		#hostname of windows
  --domain <domain>
		#*Specify windows domain name.
  -u, --user <user>
		#Specify user for install and config, default: Administrator
  -p, --password <password>
		#*Specify user's password for windows. for configure AD/DC:
		  must use a mix of uppercase letters, lowercase letters, numbers, and symbols

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
  --ram <>      #VM's ram size
  --cpus <>     #Numbers of cpu cores for VM.
  --disk-size <>#VM disk size, in .qcow2 format.
  --os-variant  <win2k12|win2k12r2|win2k16|win10|win7|...>
		#*Use command 'virt-install --os-variant list' to get accepted OS variants
                #*or Use command "osinfo-query os" *after RHEL-6 (yum install libosinfo)
  -t --ans-file-media-type <cdrom|floppy>
		#Specify the answerfiles media type loaded to KVM.
  -b, --bridge  #Use traditional bridge interface br0. Not recommended.
  --timeout <>  #Set waiting timeout for installation.
  --vncport <>  #Set vncport
  --check-ad    #do ad connection test after install complete
  --vmshome <>  #folder to save vm dir/images
  --enable-kdc  #enable AD KDC service(in case use answerfiles-cifs-nfs/postinstall.ps1)
		#- to do nfs/cifs krb5 test
  --parent-domain <parent-domain>
		#Domain name of an existing domain.
  --parent-ip <parent-ip>
		#IP address of an existing domain.
  --openssh <url>
		#url to download OpenSSH-Win64.zip
  --overwrite	#Force to set vm-name, regardless whether the name is in use or not.
EOF
}

ARGS=$(getopt -o hu:p:t:b \
	--long help \
	--long image: \
	--long wim-index: \
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
	--long check-ad \
	--long vmshome: \
	--long password: \
	--long enable-kdc \
	--long parent-domain: \
	--long parent-ip: \
	--long openssh: \
	--long overwrite \
	--long user: \
	-a -n "$PROG" -- "$@")
eval set -- "$ARGS"
while true; do
	case "$1" in
	-h|--help) Usage; exit 1;; 
	--image) WIN_ISO="$2"; shift 2;;
	--wim-index) WIM_IMAGE_INDEX="$2"; shift 2;;
	--product-key) PRODUCT_KEY="$2"; shift 2;;
	--hostname) GUEST_HOSTNAME="$2"; shift 2;;
	--domain) DOMAIN="$2"; shift 2;;
	-u|--user) ADMINUSER="$2"; shift 2;;
	-p|password) ADMINPASSWORD="$2"; shift 2;;
	--ad-forest-level) AD_FOREST_LEVEL="$2"; shift 2;;
	--ad-domain-level) AD_DOMAIN_LEVEL="$2"; shift 2;;
	--vm-name) VM_NAME="$2"; shift 2;;
	--ram) VM_RAM="$2"; shift 2;;
	--cpus) VM_CPUS="$2"; shift 2;;
	--disk-size) VM_DISKSIZE="$2"; shift 2;;
	--os-variant) VM_OS_VARIANT="$2"; shift 2;;
	-t|--ans-file-media-type) ANSF_MEDIA_TYPE="$2"; shift 2;;
	-b|--bridge) NetMode=bridge; shift 1;;
	--timeout) VM_TIMEOUT="$2"; shift 2;;
	--vncport) VNCPORT="$2"; shift 2;;
	--check-ad) CHECK_AD="yes"; shift 1;;
	--vmshome) VMS_HOME=$2; shift 2;;
	--enable-kdc) KDC_OPT="-kdc"; shift 1;;
	--parent-domain) PARENT_DOMAIN="$2"; shift 2;;
	--parent-ip) PARENT_IP="$2"; shift 2;;
	--openssh) OpenSSHUrl="$2"; shift 2;;
	--overwrite) OVERWRITE="yes"; shift 1;;
	--) shift; break;;
	*) Usage; exit 1;; 
	esac
done

AD_FOREST_LEVEL=${AD_FOREST_LEVEL:-Default}
AD_DOMAIN_LEVEL=${AD_DOMAIN_LEVEL:-$AD_FOREST_LEVEL}

[[ -z "$WIN_ISO" || -z "$VM_OS_VARIANT" || -z "$VM_NAME" ]] && {
	Usage
	exit 1
}
if egrep -q "@PARENT_(DOMAIN|IP)@" "$@"; then
	[[ -z "$PARENT_DOMAIN" || -z "$PARENT_IP" ]] && {
		echo "Missing parent-domain or parent-ip"
		Usage
		exit 1
	}
fi

[[ -z "$PRODUCT_KEY" ]] && {
	echo -e "{WARN} *** There is no Product Key specified, We assume that you are using evaluation version."
	echo -e "{WARN} *** Otherwise please use the '--product-key <key>' to ensure successful installation."
}

osvariants=$(virt-install --os-variant list 2>/dev/null) ||
	osvariants=$(osinfo-query os 2>/dev/null)
[[ -n "$osvariants" ]] && {
	grep -q -w "$VM_OS_VARIANT" <<<"$osvariants" || {
		echo -e "Unknown OS variant '$VM_OS_VARIANT'; accepted os variants:\n$osvariants"|less
		exit 1
	}
}

# =======================================================================
# Global variable
# =======================================================================
IPCONFIG_LOGF=ipconfig.log
INSTALL_COMPLETE_FILE=installcomplete
POST_INSTALL_LOGP=C:
POST_INSTALL_LOGF=postinstall.log
DEFAULT_VM_IMG_DIR=/var/lib/libvirt/images
VMS_HOME=${VMS_HOME:-/home/virt-images}
VM_PATH=$VMS_HOME/$VM_NAME
VM_TIMEOUT=${VM_TIMEOUT:-60}
VIRTHOST=$(hostname -f)
VNCPORT=${VNCPORT:-7788}
mkdir -p $VM_PATH
chcon -R --reference=$DEFAULT_VM_IMG_DIR $VMS_HOME
eval setfacl -mu:qemu:rx $VMS_HOME


# =======================================================================
# Windows Preparation
# =======================================================================
WIM_IMAGE_INDEX=${WIM_IMAGE_INDEX:-4}
[[ "$VM_OS_VARIANT" = win10 ]] && WIM_IMAGE_INDEX=1
GUEST_HOSTNAME=${GUEST_HOSTNAME:-$VM_NAME}
DOMAIN=${DOMAIN:-win.com}
ADMINUSER=${ADMINUSER:-Administrator}
ADMINPASSWORD=${ADMINPASSWORD:-Sesame~0pen}

# Setup Active Directory
FQDN=$GUEST_HOSTNAME.$DOMAIN
[[ -n "$PARENT_DOMAIN" ]] && FQDN+=.$PARENT_DOMAIN
NETBIOS_NAME=$(echo ${DOMAIN//./} | tr '[a-z]' '[A-Z]')

# =======================================================================
# KVM Preparation
# =======================================================================
if [[ "$OVERWRITE" = "yes" ]]; then
	virsh destroy $VM_NAME
	virsh undefine $VM_NAME --remove-all-storage
fi

service libvirtd start
service virtlogd start
{ #for RHEL-6 "ERROR  Format cannot be specified for unmanaged storage."
  virsh pool-define-as --name extpool --type dir --target $VMS_HOME
  virsh pool-start extpool
}

# VM network parameters
NetMode=${NetMode:-macvtap}
[[ "$NetMode" = macvtap ]] && MacvtapMode=vepa
VM_EXT_MAC=$(gen_virt_mac 01)
BR_NAME=br0
echo -e "\n{INFO} vm nic for reach outside network(mac: $VM_EXT_MAC) (NetMode:$NetMode) ..."
if [[ "$NetMode" = macvtap ]]; then
	br_delif
	DEFAULT_NIC=$(get_default_if dev)
	VM_NET_OPT_EXTERNAL="type=direct,source=$DEFAULT_NIC,source_mode=$MacvtapMode,mac=$VM_EXT_MAC"
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
ANSF_CDROM=$VM_PATH/$VM_NAME-ansf-cdrom.iso
ANSF_FLOPPY=$VM_PATH/$VM_NAME-ansf-floppy.vfd
VM_IMAGE=$VM_PATH/$VM_NAME.qcow2
EXTRA_DISK=$VM_PATH/cifstest.qcow2
SERIAL_PATH=/tmp/serial-$(date +%Y%m%d%H%M%S).$$

# VM memory parameters ...
VM_RAM=${VM_RAM:-4096}

# ====================================================================
# Generate cdrom/floppy of answerfiles
# ====================================================================
process_ansf() {
	local destdir=$1; shift
	for f; do fname=${f##*/}; cp ${f} $destdir/${fname%.in}; done

	sed -i -e "s/@ADMINPASSWORD@/$ADMINPASSWORD/g" \
		-e "s/@ADMINUSER@/$ADMINUSER/g" \
		-e "s/@AD_DOMAIN@/$DOMAIN/g" \
		-e "s/@NETBIOS_NAME@/$NETBIOS_NAME/g" \
		-e "s/@VM_NAME@/$VM_NAME/g" \
		-e "s/@FQDN@/$FQDN/g" \
		-e "s/@PRODUCT_KEY@/$PRODUCT_KEY/g" \
		-e "s/@WIM_IMAGE_INDEX@/$WIM_IMAGE_INDEX/g" \
		-e "s/@ANSF_DRIVE_LETTER@/$ANSF_DRIVE_LETTER/g" \
		-e "s/@INSTALL_COMPLETE_FILE@/$INSTALL_COMPLETE_FILE/g" \
		-e "s/@AD_FOREST_LEVEL@/$AD_FOREST_LEVEL/g" \
		-e "s/@AD_DOMAIN_LEVEL@/$AD_DOMAIN_LEVEL/g" \
		-e "s/@MAC_DISABLE@/$VM_INT_MAC/g" \
		-e "s/@DNS_IF_MAC@/$VM_EXT_MAC/g" \
		-e "s/@VIRTHOST@/$VIRTHOST/g" \
		-e "s/@IPCONFIG_LOGF@/$IPCONFIG_LOGF/g" \
		-e "s/@GUEST_HOSTNAME@/$GUEST_HOSTNAME/g" \
		-e "s/@POST_INSTALL_LOG@/$POST_INSTALL_LOGP\\\\$POST_INSTALL_LOGF/g" \
		-e "s/@KDC_OPT@/$KDC_OPT/g" \
		-e "s/@PARENT_DOMAIN@/$PARENT_DOMAIN/g" \
		-e "s/@PARENT_IP@/$PARENT_IP/g" \
		-e "s|@OpenSSHUrl@|$OpenSSHUrl|g" \
		$destdir/*
	unix2dos $destdir/* >/dev/null
	[[ -z "$PRODUCT_KEY" ]] &&
		sed -i '/<ProductKey>/ { :loop /<\/ProductKey>/! {N; b loop}; s;<ProductKey>.*</ProductKey>;; }' $destdir/*.xml
}

echo -e "\n{INFO} make answer file media ..."
eval ls "$@" || {
	echo -e "\n{ERROR} answer files $@ is not exist"
	exit 1
}
rpm -q libguestfs-winsupport || ANSF_MEDIA_TYPE=floppy  #workaround for system without libguestfs-winsupport
virt-cat --help|grep -q .--mount || ANSF_MEDIA_TYPE=floppy  #workaround for old libguestfs-tools-c(on RHEL-6)
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

echo -e "\n{INFO} copy iso file # ..."
\rm -f $VM_IMAGE
\cp -f $WIN_ISO $VM_PATH/.

echo -e "\n{INFO} make extra test disk ..."
qemu-img create -f raw $EXTRA_DISK 5G
mkfs.vfat $EXTRA_DISK
qemu-img convert -f raw -O qcow2 $EXTRA_DISK $EXTRA_DISK

echo -e "\n{INFO} get available vnc port ..."
while nc 127.0.0.1 ${VNCPORT} </dev/null &>/dev/null; do
        let VNCPORT++
done
echo $VNCPORT >$VM_PATH/vncport
echo -e "\tvncviewer $VIRTHOST:$VNCPORT #"

# =======================================================================
# Execute virt-install command with the parameters given
# =======================================================================
echo -e "\n{INFO} virt-install ..."
virt-install --connect=qemu:///system --hvm --accelerate --cpu host \
	--name "$VM_NAME" --ram=${VM_RAM} --vcpu=${VM_CPUS:-2} \
	--os-variant ${VM_OS_VARIANT} \
	--cdrom $VM_PATH/${WIN_ISO##*/} \
	--disk path=$VM_IMAGE,size=$VM_DISKSIZE,format=qcow2,cache=none \
	--disk path=$ANSF_MEDIA_PATH,device=$ANSF_MEDIA_TYPE \
	--disk path=$EXTRA_DISK,bus=sata \
	--serial file,path=$SERIAL_PATH --serial pty \
	--network $VM_NET_OPT_EXTERNAL --network $VM_NET_OPT_INTERNAL \
	--vnc --vnclisten 0.0.0.0 --vncport ${VNCPORT} || { echo error $? from virt-install ; exit 1 ; }
\rm $SERIAL_PATH

#virsh attach-disk $VM_NAME --subdriver raw $VMpath/test.raw vdc --current --targetbus usb

# workaround for https://bugzilla.redhat.com/1043249
export LIBGUESTFS_BACKEND=direct

# =======================================================================
# To check whether the installation is done
# =======================================================================
virtcat() {
	local vm=$1 dev=$2 file=$3 ret=0
	if virt-cat --help|grep -q .--mount; then
		virt-cat -d $vm -m $dev $file
		ret=$?
	else
		local tmp_mp=$(mktemp -d)
		mount -oro,loop $ANSF_FLOPPY $tmp_mp
		cat $tmp_mp/$file
		ret=$?
		umount $tmp_mp; \rm -rf $tmp_mp
	fi
	return $ret
}
echo -e "\n{INFO} waiting install done ...\n\tvncviewer $VIRTHOST:$VNCPORT"

fsdev=/dev/sdb1
[[ "$ANSF_MEDIA_TYPE" = floppy ]] && fsdev=/dev/sdc
for ((i=0; i<=VM_TIMEOUT; i++)) ; do
	virtcat $VM_NAME $fsdev /$INSTALL_COMPLETE_FILE &>/dev/null && break
	sleep 1m
done
((i > $VM_TIMEOUT)) && { echo -e "\n{WARN} Install timeout($VM_TIMEOUT)"; }

# =======================================================================
# Post Setup
# =======================================================================

# Get install and ipconfig log
WIN_INSTALL_LOG=/tmp/$VM_NAME.install.log
virtcat $VM_NAME $fsdev /$POST_INSTALL_LOGF |
	iconv -f UTF-16LE -t UTF-8 - >$WIN_INSTALL_LOG
WIN_IPCONFIG_LOG=/tmp/$VM_NAME.ipconfig.log
virtcat $VM_NAME $fsdev /$IPCONFIG_LOGF >$WIN_IPCONFIG_LOG
dos2unix $WIN_INSTALL_LOG $WIN_IPCONFIG_LOG

# Eject CDs
echo -e "\n{INFO} eject media ..."
eject_cds $VM_NAME  $WIN_ISO $ANSF_MEDIA_PATH

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
	VM_EXT_IP6=$VM_EXT_IP6
	ADMINUSER=$ADMINUSER
	ADMINPASSWORD=$ADMINPASSWORD
	DOMAIN=$DOMAIN
	FQDN=$FQDN
	NETBIOS_NAME=$NETBIOS_NAME
	VNC_URL=$VIRTHOST:$VNCPORT
EOF

# Test SSH connection
if [[ -n "$OpenSSHUrl" ]]; then
	echo -e "\n{INFO} run follow command to test SSH connection"
	echo "VM_INT_IP=$VM_INT_IP ADMINUSER=$ADMINUSER ADMINPASSWORD=$ADMINPASSWORD ./test-ssh.sh"
	echo "VM_INT_IP=$VM_INT_IP ADMINUSER=$ADMINUSER ADMINPASSWORD=$ADMINPASSWORD ./test-ssh.sh"|bash|
		sed -r -e 's|\x1b.[0-9]+;1H||' -e '/administrator@/s/ *(\x1b.2J)?(\x1b.[0-9]+;[0-9]+H){1,2}/ /' -e 's/ *\x1b[^ ]*.*$//'
fi

if [[ "$CHECK_AD" = yes ]]; then
	echo -e "\n{INFO} run follow command to test AD connection"
	ldapurl=ldap://${VM_INT_IP}
	echo "./test-cert.sh $VM_NAME $FQDN $DOMAIN $ADMINUSER:$ADMINPASSWORD $ldapurl"
	echo "./test-cert.sh $VM_NAME $FQDN $DOMAIN $ADMINUSER:$ADMINPASSWORD $ldapurl"|bash
fi

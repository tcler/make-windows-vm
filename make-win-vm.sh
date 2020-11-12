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

# Generate a random mac address with 54:52:00: prefix
gen_virt_mac() {
    echo 54:52:00:${1:-00}$(od -txC -An -N2 /dev/random | tr \  :)
}

# Eject CDs
eject_cds() {
	local vm_name=$1; shift
	local media_list="$@"

	for media in $media_list; do
		_path=$(readlink -f ${media})
		vm_media=$(virsh domblklist "$vm_name" | awk -v path=$_path '$2==path {print $1}')
		echo -e "{INFO} eject [$vm_media] -> $_path ..."
		virsh change-media "$vm_name" "$vm_media" --eject
	done
}

enable_loop_part() {
	local partn=$(< /sys/module/loop/parameters/max_part)
	if test "$partn" = 0; then
		modprobe -r loop
		modprobe loop max_part=31
	fi
}

create_vdisk() {
	local path=$1
	local size=$2
	local fstype=$3

	dd if=/dev/null of=$path bs=1${size//[0-9]/} seek=${size//[^0-9]/}
	local dev=$(losetup --partscan --show --find $path)
	printf "o\nn\np\n1\n\n\nw\n" | fdisk "$dev"
	mkfs.$fstype $MKFS_OPT "${dev}p1"
	losetup -d $dev
}

mount_vdisk() {
	local path=$1
	local mp=$2
	local partN=${3:-1}
	local offset=$(fdisk -l -o Start "$path" |
		awk -v N=$partN '
			/^Units:/ { unit=$(NF-1); offset=0; }
			/^Start/ {
				for(i=0;i<N;i++)
					if(getline == 0) { $0=""; break; }
				offset=$1*unit;
			}
			END { print offset; }'
	)
	echo "offset: $offset"

	[[ -d "$mp" ]] || {
		echo "{warn} mount_vdisk: dir '$mp' not exist"
		return 1
	}

	if [[ "$offset" -ne 0 || "$partN" -eq 1 ]]; then
		mount $MNT_OPT -oloop,offset=$offset $path $mp
	else
		echo "{warn} mount_vdisk: there's not part($partN) on disk $path"
		return 1
	fi
}

is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
is_intranet() { is_available_url http://download.devel.redhat.com; }

# ==============================================================================
# Parameter Processing
# ==============================================================================
Usage() {
cat <<EOF
Usage: $PROG [OPTION]...

Options for vm:
  -h, --help    #Display this help.

  --image </path/to/image>
		#*Specify the path to windows image.
  --hostname <hostname>
		#hostname of windows

  --vm-name|--vmname <VM_NAME>
		#*Specify the vm guest's name.
  --ram <>      #VM's ram size
  --cpus <>     #Numbers of cpu cores for VM.
  --disk-size <>#VM disk size, in .qcow2 format.
  --os-variant  <win2k12|win2k12r2|win2k16|win10|win7|...>
		#*Use command 'virt-install --os-variant list' to get accepted OS variants
                #*or Use command "osinfo-query os" *after RHEL-6 (yum install libosinfo)
  --timeout <>  #Set waiting timeout for installation.
  --vncport <>  #Set vncport
  --check-ad    #do ad connection test after install complete
  --vmshome <>  #folder to save vm dir/images
  -f, --force	#Force to set vm-name, regardless whether the name is in use or not.
  --net <>	#libvirt network name, default value: 'default'
  --static-ip-ext <>
		#set static ip for the nic that connect to public network
  --static-ip-int <>
		#set static ip for the nic that connect to internal libvirt network

Options for windows anwserfile:
  --wim-index <wim image index>
  --product-key #Prodcut key for windows activation.
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
  --enable-kdc  #enable AD KDC service(in case use answerfiles-cifs-nfs/postinstall.ps1)
		#- to do nfs/cifs krb5 test
  --parent-domain <parent-domain>
		#Domain name of an existing domain.
  --parent-ip <parent-ip>
		#IP address of an existing domain.
  --dfs-target <server:sharename>
		#The specified cifs share will be added into dfs target.
  --openssh <url>
		#url to download OpenSSH-Win64.zip

Examples:
  #Setup Active Directory forest Win2012r2:
  ./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2.iso --os-variant win2k12r2 \
    --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 --vmname rootds --domain ad.test -p ~Ocgxyz --cpus 2 \
    --ram 2048 --disk-size 20 --vncport 7777 --ad-forest-level Win2012R2  ./answerfiles-addsforest/*

  ./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2-Evaluation.iso \
    --os-variant win2k12r2 --vmname rootds --domain kernel.test -p ~Ocgabc \
    --cpus 2 --ram 2048 --disk-size 20 --vncport 7788 ./answerfiles-addsforest/*

  #Setup Active Directory child domain:
  ./make-win-vm.sh --image /var/lib/libvirt/images/Win2016-Evaluation.iso \
    --os-variant win2k16 --vmname child --parent-domain kernel.test --domain fs  -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 20 --vncport 7789 ./answerfiles-addsdomain/* --parent-ip \$addr

  #Setup Windows as NFS/CIFS server, and enable KDC(--enable-kdc):
  ./make-win-vm.sh --image /var/lib/libvirt/images/Win2019-Evaluation.iso \
    --os-variant win2k19 --vmname win2019-cifs-nfs --domain cifs-nfs.test -p ~Ocgxyz \
    --cpus 4 --ram 4096 --disk-size 60 --vncport 7799  ./answerfiles-cifs-nfs/* --enable-kdc

  #Setup Windows as NFS/CIFS server, and enable KDC(--enable-kdc), and add dfs target:
  ./make-win-vm.sh --image /var/lib/libvirt/images/Win2019-Evaluation.iso \
    --os-variant win2k19 --vmname win2019-cifs-nfs --domain cifs-nfs.test -p ~Ocgxyz \
    --cpus 4 --ram 4096 --disk-size 60 --vncport 7799  ./answerfiles-cifs-nfs/* --enable-kdc \
    --dfs-target hostname:cifs
EOF
}

ARGS=$(getopt -o hu:p:f \
	--long help \
	--long image: \
	--long wim-index: \
	--long product-key: \
	--long hostname: \
	--long domain: \
	--long ad-forest-level: \
	--long ad-domain-level: \
	--long vm-name: --long vmname: \
	--long ram: \
	--long cpus: \
	--long disk-size: \
	--long net: \
	--long static-ip-ext: \
	--long static-ip-int: \
	--long os-variant: \
	--long timeout: \
	--long vncport: \
	--long check-ad \
	--long vmshome: \
	--long password: \
	--long enable-kdc \
	--long parent-domain: \
	--long parent-ip: \
	--long openssh: \
	--long dfs-target: \
	--long force --long overwrite \
	--long user: \
	--long xdisk \
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
	--vm-name|--vmname) VM_NAME="$2"; shift 2;;
	--ram) VM_RAM="$2"; shift 2;;
	--cpus) VM_CPUS="$2"; shift 2;;
	--disk-size) VM_DISKSIZE="$2"; shift 2;;
	--net) VNET_NAME="$2"; shift 2;;
	--static-ip-ext) EXT_STATIC_IP="$2"; shift 2;;
	--static-ip-int) INT_STATIC_IP="$2"; shift 2;;
	--os-variant) VM_OS_VARIANT="$2"; shift 2;;
	--timeout) VM_TIMEOUT="$2"; shift 2;;
	--vncport) VNCPORT="$2"; shift 2;;
	--check-ad) CHECK_AD="yes"; shift 1;;
	--vmshome) VMS_HOME=$2; shift 2;;
	--enable-kdc) KDC_OPT="-kdc"; shift 1;;
	--parent-domain) PARENT_DOMAIN="$2"; shift 2;;
	--parent-ip) PARENT_IP="$2"; shift 2;;
	--openssh) OpenSSHUrl="$2"; shift 2;;
	--dfs-target) DFS_TARGET="$2"; shift 2;;
	-f|--force|--overwrite) OVERWRITE="yes"; shift 1;;
	--xdisk) XDISK="yes"; shift 1;;
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

is_intranet && {
	isobaseurl=http://download.eng.pek2.redhat.com/qa/rhts/lookaside/windows-images
	OpenSSHUrl=http://download.eng.pek2.redhat.com/qa/rhts/lookaside/windows-images/OpenSSH-Win64.zip
}
[[ ! -f "$WIN_ISO" ]] && {
	isoname=${WIN_ISO##*/}
	[[ -n "$isobaseurl" ]] && while ! curl -f -o $WIN_ISO -L $isobaseurl/$isoname; do sleep 1; done
}

# =======================================================================
# Global variable
# =======================================================================
IPCONFIG_LOGF=ipconfig.log
INSTALL_COMPLETE_FILE=installcomplete
POST_INSTALL_LOGF=postinstall.log
DEFAULT_VM_IMG_DIR=/var/lib/libvirt/images
VMS_HOME=${VMS_HOME:-/home/Windows_VMs}
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
NETBIOS_NAME=${NETBIOS_NAME:0:15}

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
NetMode=macvtap
[[ "$NetMode" = macvtap ]] && MacvtapMode=bridge
VNIC_EXT_MAC=$(gen_virt_mac 01)
echo -e "\n{INFO} vm nic for reach outside network(mac: $VNIC_EXT_MAC) (NetMode:$NetMode) ..."
DEFAULT_NIC=$(get_default_if dev)
VM_NET_OPT_EXTERNAL="type=direct,source=$DEFAULT_NIC,source_mode=$MacvtapMode,mac=$VNIC_EXT_MAC"

VM_NET_NAME=${VNET_NAME:-default}
HOST_IP=$(virsh net-dumpxml -- $VM_NET_NAME|sed -rn '/^ *<ip address=.([0-9.]+).*$/{s//\1/; p}')
VNIC_INT_MAC=$(gen_virt_mac)
echo -e "\n{INFO} vm nic for inside network(mac: $VNIC_INT_MAC) ..."
VM_NET_OPT_INTERNAL="network=$VM_NET_NAME,model=rtl8139,mac=$VNIC_INT_MAC"

# VM disk parameters ...
ANSF_USB=$VM_PATH/$VM_NAME-ansf-usb.image
VM_IMAGE=$VM_PATH/$VM_NAME.qcow2
SERIAL_PATH=/tmp/serial-$(date +%Y%m%d%H%M%S).$$
if [[ "$XDISK" = yes ]]; then
	EXTRA_DISK=$VM_PATH/cifstest.qcow2
fi

# VM memory parameters ...
VM_RAM=${VM_RAM:-4096}

# ====================================================================
# Generate answerfiles media(USB)
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
		-e "s/@VNIC_INT_MAC@/$VNIC_INT_MAC/g" \
		-e "s/@VNIC_EXT_MAC@/$VNIC_EXT_MAC/g" \
		-e "s/@INT_STATIC_IP@/$INT_STATIC_IP/g" \
		-e "s/@EXT_STATIC_IP@/$EXT_STATIC_IP/g" \
		-e "s/@VIRTHOST@/$VIRTHOST/g" \
		-e "s/@IPCONFIG_LOGF@/$IPCONFIG_LOGF/g" \
		-e "s/@GUEST_HOSTNAME@/$GUEST_HOSTNAME/g" \
		-e "s/@POST_INSTALL_LOG@/C:\\\\$POST_INSTALL_LOGF/g" \
		-e "s/@KDC_OPT@/$KDC_OPT/g" \
		-e "s/@PARENT_DOMAIN@/$PARENT_DOMAIN/g" \
		-e "s/@PARENT_IP@/$PARENT_IP/g" \
		-e "s/@DFS_TARGET@/$DFS_TARGET/g" \
		$destdir/*
	unix2dos $destdir/* >/dev/null
	[[ -z "$PRODUCT_KEY" ]] &&
		sed -i '/<ProductKey>/ { :loop /<\/ProductKey>/! {N; b loop}; s;<ProductKey>.*</ProductKey>;; }' $destdir/*.xml
	[[ -n "$OpenSSHUrl" ]] && while ! curl -L $OpenSSHUrl -f -o $destdir/OpenSSH.zip; do sleep 1; done
}

echo -e "\n{INFO} make answer file media ..."
eval ls "$@" || {
	echo -e "\n{ERROR} answer files $@ is not exist"
	exit 1
}
\rm -f $ANSF_USB #remove old/exist media file
media_mp=$(mktemp -d)
ANSF_MEDIA_PATH=$ANSF_USB
ANSF_DRIVE_LETTER="D:"
usbSize=512M
create_vdisk $ANSF_USB ${usbSize} vfat
mount_vdisk $ANSF_USB $media_mp
process_ansf $media_mp "$@"
umount $media_mp
DiskOption=bus=usb,format=raw,removable=on
\rm -rf $media_mp

echo -e "\n{INFO} copy iso file # ..."
\rm -f $VM_IMAGE
\cp -f $WIN_ISO $VM_PATH/.

if [[ "$XDISK" = yes ]]; then
	echo -e "\n{INFO} make extra test disk ..."
	qemu-img create -f qcow2 $EXTRA_DISK 4G
	XDISK_OPTS="--disk path=$EXTRA_DISK,bus=sata"
fi

echo -e "\n{INFO} get available vnc port ..."
while nc 127.0.0.1 ${VNCPORT} </dev/null &>/dev/null; do
        let VNCPORT++
done
echo $VNCPORT >$VM_PATH/vncport
echo -e "\tvncviewer $VIRTHOST:$VNCPORT #"

# =======================================================================
# Workaround for Bug 1867527 - libvirt: Guest startup broken when dm_mod is not loaded
# =======================================================================
echo -e "\n{INFO} Workaround for Bug 1867527"
if ! lsmod | grep -q dm_mod; then
	echo -e "\n{INFO} No dm_mod module loaded, loading..."
	if modprobe dm_mod && lsmod | grep -q dm_mod; then
		echo -e "\n{INFO} Load dm_mod module successfully"
	else
		echo -e "\n{INFO} Load dm_mod module failed"
	fi
fi

# =======================================================================
# Execute virt-install command with the parameters given
# =======================================================================
echo -e "\n{INFO} virt-install ..."
virt-install --connect=qemu:///system --hvm --accelerate --cpu host \
	--name "$VM_NAME" --ram=${VM_RAM} --vcpu=${VM_CPUS:-2} \
	--os-variant ${VM_OS_VARIANT} \
	--cdrom $VM_PATH/${WIN_ISO##*/} \
	--disk path=$VM_IMAGE,size=$VM_DISKSIZE,format=qcow2,cache=none \
	--disk path=$ANSF_MEDIA_PATH,$DiskOption \
	$XDISK_OPTS \
	--serial file,path=$SERIAL_PATH --serial pty \
	--network $VM_NET_OPT_EXTERNAL --network $VM_NET_OPT_INTERNAL \
	--vnc --vnclisten 0.0.0.0 --vncport ${VNCPORT} || { echo error $? from virt-install ; exit 1 ; }
\rm $SERIAL_PATH

# =======================================================================
# To check whether the installation is done
# =======================================================================
port_available() { nc $1 $2 </dev/null &>/dev/null; }
logcat() {
	local file=$1 ret=0
	local ansf=
	ansf=$ANSF_USB
	local tmp_mp=$(mktemp -d)
	MNT_OPT=-oro mount_vdisk $ansf $tmp_mp
	cat $tmp_mp/$file 2>/dev/null
	ret=$?
	umount $tmp_mp; \rm -rf $tmp_mp
	return $ret
}
echo -e "\n{INFO} waiting install done ...\n\tvncviewer $VIRTHOST:$VNCPORT"
#ipaddr=$(virsh domifaddr "$VM_NAME" | awk '$3=="ipv4" {print gensub("/.*","",1,$4)}')
#until port_available ${ipaddr} 22; do sleep 1; done   #nc check ssh port 22 ready
timeouts=$((VM_TIMEOUT*60))
timestep=10
for ((i=0; i<=timeouts; i+=timestep)) ; do
	logcat $INSTALL_COMPLETE_FILE &>/dev/null && break
	sleep $timestep
done
((i > $timeouts)) && { echo -e "\n{WARN} Install timeout(${VM_TIMEOUT}m)"; }

# =======================================================================
# Post Setup
# =======================================================================

# Get install and ipconfig log
WIN_INSTALL_LOG=/tmp/$VM_NAME.install.log
logcat $POST_INSTALL_LOGF |
	iconv -f UTF-16LE -t UTF-8 - >$WIN_INSTALL_LOG
WIN_IPCONFIG_LOG=/tmp/$VM_NAME.ipconfig.log
logcat $IPCONFIG_LOGF >$WIN_IPCONFIG_LOG
dos2unix $WIN_INSTALL_LOG $WIN_IPCONFIG_LOG

# Eject CDs
echo -e "\n{INFO} eject media ..."
eject_cds $VM_NAME  $WIN_ISO $ANSF_MEDIA_PATH

# Save relative variables into a log file
echo -e "\n{INFO} show guest info:"
VM_INT_IP=$(awk '/^ *IPv4 Address/ {if ($NF ~ /^192/) print $NF}' $WIN_IPCONFIG_LOG)
VM_EXT_IP=$(awk '/^ *IPv4 Address/ {if ($NF !~ /^192/) print $NF}' $WIN_IPCONFIG_LOG)
VM_EXT_IP6=$(awk '/^ *IPv6 Address/ {printf("[%s],", $NF)}' $WIN_IPCONFIG_LOG)
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

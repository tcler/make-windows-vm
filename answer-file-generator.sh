#!/bin/bash

LANG=C
PROG=${0##*/}

create_vdisk() {
	local path=$1
	local size=$2
	local fstype=$3

	dd if=/dev/null of=$path bs=1${size//[0-9]/} seek=${size//[^0-9]/}
	local dev=$(losetup --partscan --show --find $path)
	printf "o\nn\np\n1\n\n\nw\n" | fdisk "$dev"
	partprobe "$dev"
	while ! ls ${dev}p1 2>/dev/null; do sleep 1; done
	mkfs.$fstype $MKFS_OPT "${dev}p1"
	losetup -d $dev
}

mount_vdisk() {
	local path=$1
	local mp=$2
	local partN=${3:-1}
	local offset=

	if fdisk -l -o Start "$path" &>/dev/null; then
		read offset sizelimit < <(fdisk -l -o Start,Sectors "$path" |
			awk -v N=$partN '
				/^Units:/ { unit=$(NF-1); offset=0; }
				/^Start/ {
					for(i=0;i<N;i++)
						if(getline == 0) { $0=""; break; }
					offset=$1*unit;
					sizelimit=$2*unit;
				}
				END { print offset, sizelimit; }'
		)
	else
		read offset sizelimit < <(fdisk -l "$path" |
			awk -v N=$partN '
				/^Units/ { unit=$(NF-1); offset=0; }
				$3 == "Start" {
					for(i=0;i<N;i++)
						if(getline == 0) { $0=""; break; }
					offset=$2*unit; sizelimit=($3-$2)*unit;
					if ($2 == "*") {
						offset=$3*unit; end=($4-$3)*unit;
					}
				}
				END { print offset, sizelimit; }'
		)
	fi
	echo "offset: $offset, sizelimit: $sizelimit"

	[[ -d "$mp" ]] || {
		echo "{warn} mount_vdisk: dir '$mp' not exist"
		return 1
	}

	if [[ "$offset" -ne 0 || "$partN" -eq 1 ]]; then
		mount $MNT_OPT -oloop,offset=$offset,sizelimit=$sizelimit $path $mp
	else
		echo "{warn} mount_vdisk: there's not part($partN) on disk $path"
		return 1
	fi
}

# ==============================================================================
# Parameter Processing
# ==============================================================================
Usage() {
cat <<EOF
Usage: $PROG [OPTION] <AnswerFile Template dir>

Options for windows anwserfile:
  --path <answer file image path>
		#e.g: --path /path/to/ansf-usb.image
  --wim-index <wim image index>
  --product-key #Prodcut key for windows activation.
  --hostname    #hostname of Windows Guest VM.
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
  --enable-kdc  #enable AD KDC service(in case use AnswerFileTemplates/cifs-nfs/postinstall.ps1)
		#- to do nfs/cifs krb5 test
  --parent-domain <parent-domain>
		#Domain name of an existing domain, only for template: 'addsdomain'
  --parent-ip <parent-ip>
		#IP address of an existing domain, only for template: 'addsdomain'
  --dfs-target <server:sharename>
		#The specified cifs share will be added into dfs target.
  --openssh <url>
		#url to download OpenSSH-Win64.zip
  --driver-url,--download-url <url>
		#url to download extra drivers to anserfile media:
		#e.g: --driver-url=urlX --driver-url=urlY
  --run,--run-with-reboot <command line>
		#powershell cmd line need autorun and reboot
		#e.g: --run='./MLNX_VPI_WinOF-5_50_54000_All_win2019_x64.exe /S /V"qb /norestart"'
  --run-post <command line>
		#powershell cmd line need autorun without reboot
		#e.g: --run-post='ipconfig /all; ibstat'
  --static-ip-ext <>
		#set static ip for the nic that connect to public network
  --static-ip-int <>
		#set static ip for the nic that connect to internal libvirt network

Examples:
  #make answer file usb for Active Directory forest Win2012r2:
  $PROG --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 \
	--domain ad.test -p ~Ocgxyz --ad-forest-level Win2012R2 \
	./AnswerFileTemplates/addsforest --path ./ansf-usb.image

EOF
}

ARGS=$(getopt -o hu:p: \
	--long help \
	--long path: \
	--long user: \
	--long password: \
	--long wim-index: \
	--long product-key: \
	--long hostname: \
	--long domain: \
	--long ad-forest-level: \
	--long ad-domain-level: \
	--long static-ip-ext: \
	--long static-ip-int: \
	--long enable-kdc \
	--long parent-domain: \
	--long parent-ip: \
	--long openssh: \
	--long driver-url: --long download-url: \
	--long run: --long run-with-reboot: \
	--long run-post: \
	--long dfs-target: \
	-a -n "$PROG" -- "$@")
eval set -- "$ARGS"
while true; do
	case "$1" in
	-h|--help) Usage; exit 1;; 
	--path) ANSF_IMG_PATH="$2"; shift 2;;
	-u|--user) ADMINUSER="$2"; shift 2;;
	-p|password) ADMINPASSWORD="$2"; shift 2;;
	--wim-index) WIM_IMAGE_INDEX="$2"; shift 2;;
	--product-key) PRODUCT_KEY="$2"; shift 2;;
	--hostname) GUEST_HOSTNAME="$2"; shift 2;;
	--domain) DOMAIN="$2"; shift 2;;
	--ad-forest-level) AD_FOREST_LEVEL="$2"; shift 2;;
	--ad-domain-level) AD_DOMAIN_LEVEL="$2"; shift 2;;
	--static-ip-ext) EXT_STATIC_IP="$2"; shift 2;;
	--static-ip-int) INT_STATIC_IP="$2"; shift 2;;
	--enable-kdc) KDC_OPT="-kdc"; shift 1;;
	--parent-domain) PARENT_DOMAIN="$2"; shift 2;;
	--parent-ip) PARENT_IP="$2"; shift 2;;
	--openssh) OpenSSHUrl="$2"; shift 2;;
	--driver-url|--download-url) DL_URLS+=("$2"); shift 2;;
	--run|--run-with-reboot) RUN_CMDS+=("$2"); shift 2;;
	--run-post) RUN_POST_CMDS+=("$2"); shift 2;;
	--dfs-target) DFS_TARGET="$2"; DFS=yes; shift 2;;
	--) shift; break;;
	*) Usage; exit 1;; 
	esac
done

AD_FOREST_LEVEL=${AD_FOREST_LEVEL:-Default}
AD_DOMAIN_LEVEL=${AD_DOMAIN_LEVEL:-$AD_FOREST_LEVEL}
DefaultAnserfileTemplatePath=/usr/share/make-windows-vm/AnswerFilesTemplates/base
[[ -d "$DefaultAnserfileTemplatePath" ]] || DefaultAnserfileTemplatePath=AnswerFilesTemplates/base
AnserfileTemplatePath=${1%/}
if [[ -z "$AnserfileTemplatePath" ]]; then
	AnserfileTemplatePath=$DefaultAnserfileTemplatePath
	echo "[warn] no answer files template is given, use default($DefaultAnserfileTemplatePath)" >&2
fi

if [[ -d "$AnserfileTemplatePath" ]]; then
	echo "[error] template dir($AnserfileTemplatePath) not found" >&2
	exit 1
fi

if egrep -q "@PARENT_(DOMAIN|IP)@" -r "$AnserfileTemplatePath"; then
	[[ -z "$PARENT_DOMAIN" || -z "$PARENT_IP" ]] && {
		echo "[error] Missing parent-domain or parent-ip for template(${AnserfileTemplatePath##*/})" >&2
		Usage
		exit 1
	}
fi

[[ -z "$PRODUCT_KEY" ]] && {
	echo -e "{WARN} *** There is no Product Key specified, We assume that you are using evaluation version."
	echo -e "{WARN} *** Otherwise please use the '--product-key <key>' to ensure successful installation."
}

curl_download() {
	local filename=$1
	local url=$2
	shift 2;

	local curlopts="-f -L"
	local header=
	local fsizer=1
	local fsizel=0
	local rc=

	[[ -z "$filename" || -z "$url" ]] && {
		echo "Usage: curl_download <filename> <url> [curl options]" >&2
		return 1
	}

	header=$(curl -L -I -s $url|sed 's/\r//')
	fsizer=$(echo "$header"|awk '/Content-Length:/ {print $2; exit}')
	if echo "$header"|grep -q 'Accept-Ranges: bytes'; then
		curlopts+=' --continue-at -'
	fi

	echo "{INFO} run: curl -o $filename $curl $curlopts $curlOpt $@"
	curl -o $filename $url $curlopts $curlOpt "$@"
	rc=$?
	if [[ $rc != 0 && -s $filename ]]; then
		fsizel=$(stat --printf %s $filename)
		if [[ $fsizer -le $fsizel ]]; then
			echo "{INFO} *** '$filename' already exist $fsizel/$fsizer"
			rc=0
		fi
	fi

	return $rc
}
curl_download_x() { until curl_download "$@"; do sleep 1; done; }

# =======================================================================
# Global variable
# =======================================================================
IPCONFIG_LOGF=ipconfig.log
INSTALL_COMPLETE_FILE=installcomplete
POST_INSTALL_LOGF=postinstall.log
VIRTHOST=$(
for H in $(hostname -A); do
	if [[ ${#H} > 15 && $H = *.*.* ]]; then
		echo $H;
		break;
	fi
done)
[[ -z "$VIRTHOST" ]] && {
	_ipaddr=$(getDefaultIp4)
	VIRTHOST=$(host ${_ipaddr%/*} | awk '{print $NF; exit}')
	VIRTHOST=${VIRTHOST%.}
	[[ "$VIRTHOST" = *NXDOMAIN* ]] && {
		VIRTHOST=$_ipaddr
	}
}

# =======================================================================
# Windows Preparation
# =======================================================================
WIM_IMAGE_INDEX=${WIM_IMAGE_INDEX:-4}
[[ -n is_win10 ]] && WIM_IMAGE_INDEX=1
GUEST_HOSTNAME=${GUEST_HOSTNAME}
[[ ${#GUEST_HOSTNAME} -gt 15 || -z "$GUEST_HOSTNAME" ]] && {
	echo -e "{ERROR} length of hostname($GUEST_HOSTNAME) should < 16 and > 0" >&2
	exit 1
}
DOMAIN=${DOMAIN:-win.com}
ADMINUSER=${ADMINUSER:-Administrator}
ADMINPASSWORD=${ADMINPASSWORD:-Sesame~0pen}

# Setup Active Directory
FQDN=$GUEST_HOSTNAME.$DOMAIN
[[ -n "$PARENT_DOMAIN" ]] && FQDN+=.$PARENT_DOMAIN
NETBIOS_NAME=$(echo ${DOMAIN//./} | tr '[a-z]' '[A-Z]')
NETBIOS_NAME=${NETBIOS_NAME:0:15}

# anwser file usb image path ...
ANSF_IMG_PATH=${ANSF_IMG_PATH:-ansf-usb.image}

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
		-e "s/@VNIC_INT_MAC@/$MAC_INT/g" \
		-e "s/@VNIC_EXT_MAC@/$MAC_EXT/g" \
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
		-e "s/@HOST_NAME@/$HOSTNAME/g" \
		-e "s/@AUTORUN_DIR@/$ANSF_AUTORUN_DIR/g" \
		$destdir/*
	[[ -z "$PRODUCT_KEY" ]] && {
		echo -e "{INFO} remove ProductKey node from xml ..."
		sed -i '/<ProductKey>/ { :loop /<\/ProductKey>/! {N; b loop}; s;<ProductKey>.*</ProductKey>;; }' $destdir/*.xml
	}
	unix2dos $destdir/* >/dev/null

	[[ -n "$OpenSSHUrl" ]] && curl_download_x $destdir/OpenSSH.zip $OpenSSHUrl

	autorundir=$destdir/$ANSF_AUTORUN_DIR
	if [[ -n "$DL_URLS" ]]; then
		mkdir -p $autorundir
		for _url in "${DL_URLS[@]}"; do
			_fname=${_url##*/}
			curl_download_x $autorundir/${_fname} $_url
		done
	fi
	if [[ -n "$RUN_CMDS" || -n "$RUN_POST_CMDS" ]]; then
		mkdir -p $autorundir
		runf=$autorundir/autorun.ps1
		runpostf=$autorundir/autorun-post.ps1
		for _cmd in "${RUN_CMDS[@]}"; do
			echo "$_cmd" >>$runf
		done
		for _cmd in "${RUN_POST_CMDS[@]}"; do
			echo "$_cmd" >>$runpostf
		done
		unix2dos $runf $runpostf >/dev/null
	fi
}

echo -e "\n{INFO} make answer file media ..."
eval "ls $AnserfileTemplatePath/*" || {
	echo -e "\n{ERROR} answer files not found in $AnserfileTemplatePath"
	exit 1
}
\rm -f $ANSF_IMG_PATH #remove old/exist media file
media_mp=$(mktemp -d)
ANSF_DRIVE_LETTER="D:"
ANSF_AUTORUN_DIR=tools-drivers
usbSize=1024M
create_vdisk $ANSF_IMG_PATH ${usbSize} vfat
mount_vdisk $ANSF_IMG_PATH $media_mp
process_ansf $media_mp $AnserfileTemplatePath/*
umount $media_mp
\rm -rf $media_mp

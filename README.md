## make-windows-vm

## Why?
 There are some automated tests related to windows OS in our work. So we need to find ways to automate the installation and configuration of the windows OS, that's it.
 
 Actually this project is a reconstruction of https://github.com/richm/auto-win-vm-ad and aims to provide a more clear user interface.

 Ref: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup

## dependencies install
```
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install libvirt libvirt-client virt-install virt-viewer qemu-kvm genisoimage \
  libguestfs-tools libguestfs-tools-c openldap-clients dos2unix glibc-common libosinfo libguestfs-winsupport unix2dos
```

## example
```
vmname=win2012r2-yjh
virsh undefine $vmname; virsh destroy $vmname
./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2.iso --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 \
    --os-variant win2k12r2 --vm-name $vmname --domain ad.test -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 20 -b --vncport 7777 --ad-forest-level Win2012R2  ./answerfiles-ad/*

./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2-Evaluation.iso \
    --os-variant win2k12r2 --vm-name $vmname --domain ad.test -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 20 -b --vncport 7788 ./answerfiles-ad/*

./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2-Evaluation.iso \
    --os-variant win2k12r2 --vm-name $vmname --domain nfs.test -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 60 --vncport 7799  ./answerfiles-cifs-nfs/* --enable-kdc

# tips 1:
# libguestfs can't mount ntfs after RHEL-7.2, because libguestfs-winsupport was disabled for some reason.
# Now seems only the users of RHEL Server could get libguestfs-winsupport.
#
# for users of RHEL Workstation and Client, we provide a workaround: Use floppy as answer file media type,
# thus we can write windows guest info on floppy instead and still could read them from host.
#
# tips 2:
# if passwd is too week will cause failure to setup AD
```
 
## steps:
 - Download a windows ISO(If you have not bought a license, you can try evaluate versions)
   - https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server
 - Define global file name to share info between Host and Win Guest
   - install log file
   - complete file
 - Prepare answer file autounattend.xml and the data/parameters needed during install
   - win product key
   - win username & passwd
   - win hostname(eg: win2012)
   - win domain name(eg: ad.test)
   - win media type to keep answer files(floppy or cdrom)
 - Prepare windows config scripts and parameters # fix me
   - AD(Active Directory)
     - DOMAIN LEVEL
     - FOREST LEVEL
   - cert
     - ?
     - ?
   - NFS
     - export path
     - export options
   - CIFS
     - export path
     - export options
 - Prepare vm parameters
   - vm instance name
   - vm cpu vcpu
   - vm mem
   - vm network config
   - vm disk options



## Tips
### [0] about libguestfs ntfs and libguestfs-winsupport
```
# ref: http://libguestfs.org/guestfs-faq.1.html
Cannot open Windows guests which use NTFS.

You see errors like:

 mount: unknown filesystem type 'ntfs'

On Red Hat Enterprise Linux or CentOS < 7.2, you have to install the libguestfs-winsupport package. In RHEL ≥ 7.2, libguestfs-winsupport is part of the base RHEL distribution, but see the next question.
"mount: unsupported filesystem type" with NTFS in RHEL ≥ 7.2

In RHEL 7.2 we were able to add libguestfs-winsupport to the base RHEL distribution, but we had to disable the ability to use it for opening and editing filesystems. It is only supported when used with virt-v2v(1). If you try to use guestfish(1) or guestmount(1) or some other programs on an NTFS filesystem, you will see the error:

 mount: unsupported filesystem type

This is not a supported configuration, and it will not be made to work in RHEL. Don't bother to open a bug about it, as it will be immediately CLOSED -> WONTFIX.

You may compile your own libguestfs removing this restriction, but that won't be endorsed or supported by Red Hat. 
```

### [1] get wim images info
```
# from windows
CMD C:\> dism /Get-WimInfo /WimFile:F:\sources\install.wim
PS C:\> Get-WindowsImage -ImagePath "c:\imagestore\install.wim" -Name Ultimate
PS C:\> Get-WindowsImage -ImagePath "c:\imagestore\install.vhd"

# from linux
# install winlib (https://wimlib.net/)
sudo yum install libxml2-devel fuse-devel
git clone git://wimlib.net/wimlib && cd wimlib && ./confiure && make && sudo make install

# mount your windows install ISO file
sudo mkdir -p /mnt/image
ISO=/var/lib/libvirt/images/Win2012r2-Evaluation.iso
sudo mount $ISO /mnt/image

# get all images info
wiminfo /mnt/image/sources/install.wim
<skip>

# get info of Image with Index=1
wiminfo /mnt/image/sources/install.wim 1
<skip>

# get info of Image with Name="Windows Server 2012 R2 SERVERSTANDARD"
wiminfo /mnt/image/sources/install.wim "Windows Server 2012 R2 SERVERSTANDARD"
Information for Image 2
-----------------------
Index:                  2
Name:                   Windows Server 2012 R2 SERVERSTANDARD
Description:            Windows Server 2012 R2 SERVERSTANDARD
Display Name:           Windows Server 2012 R2 Standard Evaluation (Server with a GUI)
Display Description:    This option is useful when a GUI is required—for example, to provide backward compatibility for an application that cannot be run on a Server Core installation. All server roles and features are supported. You can switch to a different installation option later. See "Windows Server Installation Options."
Directory Count:        19342
File Count:             89400
Total Bytes:            12051460352
Hard Link Bytes:        4403205238
Creation Time:          Fri Mar 21 20:40:33 2014 UTC
Last Modification Time: Fri Mar 21 20:41:07 2014 UTC
Architecture:           x86_64
Product Name:           Microsoft® Windows® Operating System
Edition ID:             ServerStandardEval
Installation Type:      Server
HAL:                    acpiapic
Product Type:           ServerNT
Product Suite:          Terminal Server
Languages:              en-US
Default Language:       en-US
System Root:            WINDOWS
Major Version:          6
Minor Version:          3
Build:                  9600
Service Pack Build:     17031
Service Pack Level:     0
Flags:                  ServerStandardEval
WIMBoot compatible:     no
```

### [2] Convert UTF-16 encoded file to UTF-8
installlog generated by postinstall.ps1 is UTF-16 format, need convert to utf8
```
iconv -f UTF-16LE -t UTF-8 <filename>
```

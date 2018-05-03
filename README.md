## make-windows-vm

## Why?
 There are some automated tests related to windows OS in our work. So we need to find ways to automate the installation and configuration of the windows OS, that's it.
 
 Actually this project is a reconstruction of https://github.com/richm/auto-win-vm-ad and aims to provide a more clear user interface.

## dependencies install
```
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install libvirt libvirt-client virt-install virt-viewer qemu-kvm \
  libguestfs-tools libguestfs-tools-c openldap-clients genisoimage dosfstools unix2dos libguestfs-winsupport
```

## example
```
# vmname=win2012r2-yjh
# virsh undefine $vmname; virsh destroy $vmname
# ./make-win-vm.sh --image /var/lib/libvirt/images/en*.iso --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 \
    ---os-variant win2k12r2 -vm-name $vmname --domain ad.test -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 20 -b --vncport 7799 --ad-forest-level Win2012R2  answerfiles-ad/*

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
   - windows env
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
 - Prepare vm parameters
   - vm instance name
   - vm cpu vcpu
   - vm mem
   - vm network config
   - vm disk options



## [0] about libguestfs ntfs and libguestfs-winsupport
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

## make-windows-vm

## Why?
 There are some automated tests related to windows OS in our work. So we need to find ways to automate the installation and configuration of the windows OS, that's it.
 
 Actually this project is a reconstruction of https://github.com/richm/auto-win-vm-ad and aims to provide a more clear user interface.

## dependencies install
```
sudo yum install  https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum install libvirt libvirt-client virt-install virt-viewer qemu-kvm \
  libguestfs-tools libguestfs-tools-c openldap-clients genisoimage dosfstools unix2dos ntfs-3g
```

## example
```
sudo ./make-win-vm.sh --image /var/lib/libvirt/images/en*.iso --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 --domain ad.test --vm-name win2012r2 -p asd123 -t cdrom --os-variant win2k8 --cpus 2 --ram 2048 --disk-size 16  answerfiles/*.in
```
 
## steps:
 - Download a windows ISO file
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

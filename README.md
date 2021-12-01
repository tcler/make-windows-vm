# make-windows-vm

## Why?
 There are some automated tests related to windows OS in our work. So we need to find ways to automate the installation and configuration of the windows OS, that's it.
 
 Actually this project is a reconstruction of https://github.com/richm/auto-win-vm-ad and aims to meet our specific requirements and provide a more clear user interface.

 Ref: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup


![example](https://github.com/tcler/bkr-client-improved/blob/master/img/reserve-windows-sample.png)


## Files layout:
```
make-windows-vm/
├── answerfiles
│   ├── autounattend.xml.in
│   └── postinstall.ps1.in
├── answerfiles-addsdomain
│   ├── autounattend.xml.in -> ../answerfiles/autounattend.xml.in
│   └── postinstall.ps1.in
├── answerfiles-addsforest
│   ├── autounattend.xml.in -> ../answerfiles/autounattend.xml.in
│   └── postinstall.ps1.in
├── answerfiles-cifs-nfs
│   ├── autounattend.xml.in -> ../answerfiles/autounattend.xml.in
│   └── postinstall.ps1.in
├── make-win-vm.sh
├── README.md
└── utils
    ├── test-cert.sh
    ├── test-cifs-nfs.sh
    └── test-ssh.sh
```

***Note***: There are four answerfiles{, -addsdomain, -addsforest, -cifs-nfs} directories for different usages. 
Generally, answerfiles are used to deploy windows automatically. Usages are listed below:

| Directory              | Usage                                         |
| ---------------------- | --------------------------------------------- |
| answerfiles            | windows server without any services cofigured |
| answerfiles-addsdomain | active directory child domain                 |
| answerfiles-addsforest | active directory forest                       |
| answerfiles-cifs-nfs   | windows NFS/CIFS server                       |

## Dependencies:

| Package            	| Notes                                                   |
| --------------------- | ------------------------------------------------------- |
| libvirt            	| virtual machine service daemon                          |
| libvirt-client     	| virtual machine/network management                      |
| virt-install       	| virtual machine creation                                |
| virt-viewer           | graphical interface for viewing virtual machine         |
| qemu-kvm              | core virt package                                       |
| genisoimage           | for creating the CD-ROM answerfile disk                 |
| libguestfs-tools      | windows vm registry reader                              |
| libguestfs-tools-c    | used to check for the wait file                         |
| libguestfs-winsupport | windows vm files reader (**OPTIONAL**)                  |
| openldap-clients   	| for testing AD connection and getting AD CA cert        |
| dos2unix/unix2dos     | for byte encoding conversion                            |
| libosinfo             | used to check windows image information (**OPTIONAL**)  |

##### On RHEL/CentOS:
```
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
```
```
sudo yum install libvirt libvirt-client virt-install virt-viewer qemu-kvm dosfstools \
 openldap-clients dos2unix unix2dos glibc-common expect
```

## Steps:
 - Make sure the dependencies mentioned above are installed and services are started
 - Download a windows ISO(If you have not bought a license, you can try evaluation versions)
   - https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server
 - Run make-win-vm.sh script with the required parameters (see ***Examples*** below)
 - Get information about windows after installation from /tmp directory if necessary
   - */tmp/$vnmane.env* contains windows IP, FQDN, username, etc.
   - */tmp/postinstall.log* contains the configuration log of windows installation.

## Examples:
##### Setup Active Directory forest:
```
./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2.iso --os-variant win2k12r2 \
    --product-key W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9 --vm-name rootds --domain ad.test -p ~Ocgxyz --cpus 2 \
    --ram 2048 --disk-size 20 --vncport 7777 --ad-forest-level Win2012R2  ./answerfiles-addsforest/*

./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2-Evaluation.iso \
    --os-variant win2k12r2 --vm-name rootds --domain kernel.test -p ~Ocgabc \
    --cpus 2 --ram 2048 --disk-size 20 --vncport 7788 ./answerfiles-addsforest/*
```
##### Setup Active Directory child domain:
```
./make-win-vm.sh --image /var/lib/libvirt/images/Win2012r2-Evaluation.iso \
    --os-variant win2k12r2 --vm-name child --parent-domain kernel.test --domain fs  -p ~Ocgxyz \
    --cpus 2 --ram 2048 --disk-size 20 --vncport 7789 ./answerfiles-addsdomain/* --parent-ip $addr
```
##### Setup Windows as NFS/CIFS server:
```
./make-win-vm.sh --image /var/lib/libvirt/images/Win2019-Evaluation.iso \
    --os-variant win2k19 --vm-name winfs --domain nfs.test -p ~Ocgxyz \
    --cpus 4 --ram 4096 --disk-size 80 --vncport 7799 \
    --driver-url=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.208-1/virtio-win-guest-tools.exe \
    --driver-url=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.208-1/virtio-win-gt-x64.msi \
    --run-with-reboot='./virtio-win-guest-tools.exe /install /passive'
    --run-post='./qemu-ga-x86_64.msi /passive'
    ./answerfiles-cifs-nfs/* --enable-kdc
```

 ***NOTE:***
1. All the examples above provide as much details as possible but generally not all the parameters above are
mandatory. To get more help, see [README-options](./README-options.md) or just use -h (--help).

2. libguestfs can't mount ntfs after RHEL-7.2, because libguestfs-winsupport was disabled for some reason. 
Now it seems only RHEL Server provides libguestfs-winsupport.

3. For users of other distributions, we provide a workaround: Use USB as answer file media type instead of iso, 
thus we can write windows guest info on USB instead and still could read them from host (This is done automatically 
so no extra operations are needed).

4. If the password of windows is too weak, it will fail to deploy windows.

5. all examples above test pass on Windows Server 2012,2012r2,2016,2019; and Windows 10 pass on basic ./answerfiles/\*


## Tips
### [-1] About Windows iso

Note: our example autounattend.xml just works fine on en-us version's ISO file

so please select language en-us while you download evaluate iso from Microsoft site.

### [0] About libguestfs ntfs and libguestfs-winsupport
Ref: http://libguestfs.org/guestfs-faq.1.html

If you cannot open Windows guests which use NTFS. You may see errors like:
```
 mount: unknown filesystem type 'ntfs'
```
On Red Hat Enterprise Linux or CentOS < 7.2, you have to install the libguestfs-winsupport package. In RHEL ≥ 7.2, libguestfs-winsupport is part of the base RHEL distribution, but see the next question.
"mount: unsupported filesystem type" with NTFS in RHEL ≥ 7.2

In RHEL 7.2 we were able to add libguestfs-winsupport to the base RHEL distribution, but we had to disable the ability to use it for opening and editing filesystems. It is only supported when used with virt-v2v(1). If you try to use guestfish(1) or guestmount(1) or some other programs on an NTFS filesystem, you will see the error:
```
 mount: unsupported filesystem type
```
This is not a supported configuration, and it will not be made to work in RHEL. Don't bother to open a bug about it, as it will be immediately CLOSED -> WONTFIX.

You may compile your own libguestfs removing this restriction, but that won't be endorsed or supported by Red Hat. 

### [1] Get wim images info
#### From windows:
```
CMD C:\> dism /Get-WimInfo /WimFile:F:\sources\install.wim
PS C:\> Get-WindowsImage -ImagePath "c:\imagestore\install.wim" -Name Ultimate
PS C:\> Get-WindowsImage -ImagePath "c:\imagestore\install.vhd"
```

#### From linux:
 - Install dependencies:
```
sudo yum install libxml2-devel fuse-devel
```
 - Install winlib for source (https://wimlib.net/):
```
git clone git://wimlib.net/wimlib && cd wimlib && ./confiure && make && sudo make install
```
 - Mount your windows install ISO file:
```
sudo mkdir -p /mnt/image
ISO=/var/lib/libvirt/images/Win2012r2-Evaluation.iso
sudo mount $ISO /mnt/image
```

 - Get all images info:
```
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
install log generated by postinstall.ps1 is UTF-16 format, need convert to utf8
```
iconv -f UTF-16LE -t UTF-8 <filename>
```

### [3] Windows KDC and Domain Controller how-to
Ref1: https://adsecurity.org/?p=483  
Every Domain Controller in an Active Directory domain runs a KDC
(Kerberos Distribution Center) service which handles all Kerberos
ticket requests.

Ref2: https://blogs.technet.microsoft.com/uktechnet/2016/06/08/setting-up-active-directory-via-powershell/  
Now, you will need to promote your server to a domain
controller as per your requirements - there are several commands
that you can use to do this. I will provide a list and description
so that you can figure out which one best suits your needs.
However, for this article, we are going to use the
Install-ADDSForest command.

Commands to Promote Server as Domain Controller:

| Command                                        | Description                                                                       |
| ---------------------------------------------- | --------------------------------------------------------------------------------- |
| Add-ADDSReadOnlyDomainControllerAccount        | Install read only domain controller                                               |
| Install-ADDSDomain                             | Install first domain controller in a child or tree domain                         |
| Install-ADDSDomainController                   | Install additional domain controller in domain                                    |
| Install-ADDSForest                             | Install first domain controller in new forest                                     |
| Test-ADDSDomainControllerInstallation          | Verify prerequisites to install additional domain controller in domain            |
| Test-ADDSDomainControllerUninstallation        | Uninstall AD services from server                                                 |
| Test-ADDSDomainInstallation                    | Verify prerequisites to install first domain controller in a child or tree domain |
| Test-ADDSForestInstallation                    | Install first domain controller in new forest                                     |
| Test-ADDSReadOnlyDomainControllAccountCreation | Verify prerequisites to install read only domain controller                       |
| Uninstall-ADDSDomainController                 | Uninstall the domain controller from server                                       |

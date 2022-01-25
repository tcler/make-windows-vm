## Usage
```
./make-win-vm.sh [OPTION]...
```
## Options
| Options                      | Default value       | Mandatory     | Condition                                    |
| :--------------------------: | :-----------------: | :-----------: | :------------------------------------------: |
| --ad-forest-level <>         | Default             | No            |                                              |
| --ad-domain-level <>         | Default             | No            |                                              |
| --cpus <>                    | 2                   | No            |                                              |
| --check-ad                   |                     | No            |                                              |
| --disk-size <>               |                     | Yes           |                                              |
| --domain <>                  | win.com             | No            |                                              |
| --enable-kdc                 |                     | No            |                                              |
| -h, --help                   |                     | No            |                                              |
| --hostname <>                | (same as --vm-name) | No            |                                              |
| --image <>                   |                     | Yes           |                                              |
| --image-dir <>               | /home/virt-images   | No            |                                              |
| --openssh <>                 |                     | No            |                                              |
| --os-variant <>              |                     | Yes           |                                              |
| --parent-domain <>           |                     | Conditionally | Mandatory when using AnswerFileTemplates/addsdomain/ |
| --parent-ip <>               |                     | Conditionally | Ditto                                        |
| --product-key <>             |                     | Conditionally | Mandatory when not using evaluation versions |
| -p, --password <>            | Sesame~0pen         | No            |                                              |
| --ram <>                     | 2048                | No            |                                              |
| --timeout <>                 | 60                  | No            |                                              |
| -u, --user <>                | Administrator       | No            |                                              |
| --vm-name <>                 |                     | Yes           |                                              |
| --vncport <>                 | 7788                | No            |                                              |
| --wim-index <>               | 4                   | No            |                                              |

## Description
**--ad-forest-level**  
- Specify active directory forest level. It can be one of the values listed below:
  - Default
  - Windows Server 2003: 2 or Win2003
  - Windows Server 2008: 3 or Win2008
  - Windows Server 2008 R2: 4 or Win2008R2
  - Windows Server 2012: 5 or Win2012
  - Windows Server 2012 R2: 6 or Win2012R2
  - Windows Server 2016: 7 or WinThreshold  

The default forest functional level in Windows Server is typically the same as 
the version you are running. However, the default forest functional level in 
Windows Server 2008 R2 when you create a new forest is Windows Server 2003 or 2

**--ad-domain-level**  
- Specify active directory domain level. It can be one of the values listed below:
  - Default
  - Windows Server 2003: 2 or Win2003
  - Windows Server 2008: 3 or Win2008
  - Windows Server 2008 R2: 4 or Win2008R2
  - Windows Server 2012: 5 or Win2012
  - Windows Server 2012 R2: 6 or Win2012R2
  - Windows Server 2016: 7 or WinThreshold  

The domain functional level cannot be lower than the forest functional level, 
but it can be higher. The default is automatically computed and set.  

**--cpus**  
Numbers of cpu cores for VM.  

**--check-ad**  
Optional. Used to check whether AD connection is working.  

**-disk-size**  
Specify VM disk size in GB (usually with .qcow2 format).  

**--domain**  
Specify windows domain name.  

**--enable-kdc**  
Enable kerberos service. This is only used with AnswerFileTemplates/cifs-nfs/ to test NFS/CIFS
exporting option "sec=krb5,krb5i,krb5p".  

**-h, --help**  
Print a brief version of help.  
	
**--hostname**  
Specify host name of windows. If it's not specified, it will be the same as the VM name.  

**--image**  
Specify the path to windows image (usually with .iso suffix). Please put the image at 
/var/lib/libvirt/images/ or the script may fail to read it. Be aware that it's NOT the
same as **--image-dir** below.  

**--image-dir**  
Specify the path to save VM disk image (usually with .qcow2 suffix). This is used when 
there is no enough disk space in the default directory.  

**--openssh**  
Specify openssh download link if you want to access windows via SSH after installation.
For example, --openssh=https://github.com/PowerShell/Win32-OpenSSH/releases/download/v7.7.1.0p1-Beta/OpenSSH-Win64.zip.

**--os-variant**  
Specify KVM OS variant. There are lots of variants but in the specific case we only care 
about windows variants:
- win2k8
- win2k12
- win2k12r2
- win2k16
- win10
- win7  
...  

Use command 'virt-install --os-variant list' to get accepted OS variants or Use command 
"osinfo-query os" after RHEL-6 (yum install libosinfo). Note that os variant doesn't 
have to 100% match the windows image you are using (e.g. It works even if you specify 
win2k8 when using win2k16 image) because it's used to optimize the setup process.  

**--parent-domain**  
Specify a parent domain name. It's only used when deploying a child domain and this parent 
domain must've existed. This is used together with **--parent-ip**  

**--parent-ip**  
Specify a parent domain ip. It's only used when deploying a child domain and this parent 
domain must've existed. This is used together with **--parent-domain**  

**--product-key**  
Specify windows product key. This is not recommended for testing purpose. Using evaluation
windows is preferred.  

**-p, --password**  
Specify windows login password. Note that the password can't be too weak or the deployment will fail.  

**--ram**  
Specify size of RAM for VM in MB.  

**--timeout**  
Set timeout for windows installation in minutes.  

**-u, --user**  
Specify windows user name.  

**--vm-name**  
Specify VM windows name.  

**--vncport**  
Specify VNC port to connect to windows VM for checking.  

**--wim-index**  
Specify wim index for windows installation. See [READNE](./README.md) Tips[1] Get wim images info.  


#!/bin/bash

host=$1
[[ -z "$host" ]] && {
	echo "$0 <hostname|ipaddress>"
	exit 1
}

echo "{Info} get cifs share list ..."
rpm -q samba-client &>/dev/null || yum install -y samba-client
smbclient -m SMB3 -L $host -U guest%
echo
echo "{Info} get nfs share list ..."
showmount -e $host

